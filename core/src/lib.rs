//! lightcore — Rust core for LightApp.
//!
//! Wraps Blockstream Greenlight's `gl-client` and exposes a mobile-friendly
//! API through UniFFI (Kotlin now, Swift later).

mod models;

pub use models::*;

use std::sync::Arc;

use bip39::{Language, Mnemonic};
use gl_client::bitcoin::Network;
use gl_client::credentials::{Device, Nobody};
use gl_client::node::ClnClient;
use gl_client::pb::cln;
use gl_client::scheduler::Scheduler;
use gl_client::signer::Signer;
use rand::RngCore;
use zeroize::{Zeroize, Zeroizing};

uniffi::setup_scaffolding!();

/// Route Rust logs to Android logcat under the tag "lightcore".
///
/// `enable` must be `false` on release builds: gl-client / tonic / hyper emit
/// node ids, peer ids and payment metadata at info/error level, which anything
/// holding READ_LOGS could harvest. Pass `BuildConfig.DEBUG` from Kotlin so the
/// signer's logs only ever reach logcat on developer builds.
#[uniffi::export]
pub fn init_logging(enable: bool) {
    if !enable {
        return;
    }
    #[cfg(target_os = "android")]
    {
        use std::sync::Once;
        static ONCE: Once = Once::new();
        ONCE.call_once(|| {
            android_logger::init_once(
                android_logger::Config::default()
                    .with_max_level(log::LevelFilter::Info)
                    .with_tag("lightcore"),
            );
        });
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn gl_err<E: std::fmt::Display>(e: E) -> CoreError {
    CoreError::Msg(format!("{e}"))
}

fn parse_network(network: &str) -> CoreResult<Network> {
    match network.to_lowercase().as_str() {
        "bitcoin" | "mainnet" => Ok(Network::Bitcoin),
        "testnet" => Ok(Network::Testnet),
        "signet" => Ok(Network::Signet),
        "regtest" => Ok(Network::Regtest),
        other => Err(CoreError::Msg(format!("unknown network: {other}"))),
    }
}

fn seed_from_mnemonic(phrase: &str, passphrase: &str) -> CoreResult<Zeroizing<Vec<u8>>> {
    let mnemonic = Mnemonic::parse_in(Language::English, phrase.trim())
        .map_err(|e| CoreError::Msg(format!("invalid mnemonic: {e}")))?;
    // Greenlight expects a 32-byte seed (first half of the BIP39 seed).
    // Zero the full 64-byte buffer and hand back a self-wiping 32-byte copy so
    // our own heap/stack copies don't outlive the call.
    let mut full = mnemonic.to_seed(passphrase);
    let seed = Zeroizing::new(full[0..32].to_vec());
    full.zeroize();
    Ok(seed)
}

fn amount(msat: u64) -> cln::Amount {
    cln::Amount { msat }
}

/// sat → msat with overflow rejected. `opt-level=3` builds have overflow
/// checks off, so an unchecked `sat * 1000` would silently wrap to a tiny
/// value and send/fund the wrong amount.
fn checked_msat(sat: u64) -> CoreResult<u64> {
    sat.checked_mul(1000)
        .ok_or_else(|| CoreError::Msg(format!("amount too large: {sat} sat")))
}

fn amount_or_any(msat: Option<u64>) -> cln::AmountOrAny {
    cln::AmountOrAny {
        value: Some(match msat {
            Some(m) => cln::amount_or_any::Value::Amount(amount(m)),
            None => cln::amount_or_any::Value::Any(true),
        }),
    }
}

fn amount_or_all(msat: u64, all: bool) -> cln::AmountOrAll {
    cln::AmountOrAll {
        value: Some(if all {
            cln::amount_or_all::Value::All(true)
        } else {
            cln::amount_or_all::Value::Amount(amount(msat))
        }),
    }
}

/// Parse "slow" | "normal" | "urgent" | "<n>perkw" | "<n>perkb".
fn parse_feerate(s: &str) -> CoreResult<cln::Feerate> {
    use cln::feerate::Style;
    let s = s.trim().to_lowercase();
    let style = match s.as_str() {
        "slow" => Style::Slow(true),
        "normal" => Style::Normal(true),
        "urgent" => Style::Urgent(true),
        _ => {
            if let Some(n) = s.strip_suffix("perkw") {
                Style::Perkw(n.parse().map_err(gl_err)?)
            } else if let Some(n) = s.strip_suffix("perkb") {
                Style::Perkb(n.parse().map_err(gl_err)?)
            } else {
                return Err(CoreError::Msg(format!("invalid feerate: {s}")));
            }
        }
    };
    Ok(cln::Feerate { style: Some(style) })
}

fn opt_feerate(s: &Option<String>) -> CoreResult<Option<cln::Feerate>> {
    match s {
        Some(v) if !v.trim().is_empty() => Ok(Some(parse_feerate(v)?)),
        _ => Ok(None),
    }
}

fn msat_of(a: &Option<cln::Amount>) -> Option<u64> {
    a.as_ref().map(|x| x.msat)
}

fn hexs(b: &[u8]) -> String {
    hex::encode(b)
}

fn channel_state_name(v: i32) -> String {
    match v {
        0 => "OPENINGD",
        1 => "CHANNELD_AWAITING_LOCKIN",
        2 => "CHANNELD_NORMAL",
        3 => "CHANNELD_SHUTTING_DOWN",
        4 => "CLOSINGD_SIGEXCHANGE",
        5 => "CLOSINGD_COMPLETE",
        6 => "AWAITING_UNILATERAL",
        7 => "FUNDING_SPEND_SEEN",
        8 => "ONCHAIN",
        9 => "DUALOPEND_OPEN_INIT",
        10 => "DUALOPEND_AWAITING_LOCKIN",
        11 => "CHANNELD_AWAITING_SPLICE",
        12 => "DUALOPEND_OPEN_COMMITTED",
        13 => "DUALOPEND_OPEN_COMMIT_READY",
        14 => "CLOSED",
        _ => "UNKNOWN",
    }
    .to_string()
}

// ---------------------------------------------------------------------------
// Mnemonic / seed utilities (sync, no network)
// ---------------------------------------------------------------------------

/// Generate a fresh 24-word BIP39 mnemonic from 32 bytes of OS entropy.
#[uniffi::export]
pub fn generate_mnemonic() -> CoreResult<String> {
    let mut entropy = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut entropy);
    let mnemonic = Mnemonic::from_entropy_in(Language::English, &entropy)
        .map_err(|e| CoreError::Msg(e.to_string()))?;
    Ok(mnemonic.words().collect::<Vec<_>>().join(" "))
}

/// Validate a user-supplied mnemonic (word list + checksum).
#[uniffi::export]
pub fn validate_mnemonic(phrase: String) -> bool {
    Mnemonic::parse_in(Language::English, phrase.trim()).is_ok()
}

// ---------------------------------------------------------------------------
// Registration / recovery (Nobody credentials + developer cert)
// ---------------------------------------------------------------------------

/// Register a brand-new Greenlight node for this seed.
///
/// `developer_cert` / `developer_key` are the PEM files downloaded from the
/// Greenlight developer console. Returns the device credentials blob that must
/// be persisted (encrypted!) and passed to `connect_node` afterwards.
#[uniffi::export(async_runtime = "tokio")]
pub async fn register_node(
    mnemonic: String,
    passphrase: String,
    network: String,
    developer_cert: Vec<u8>,
    developer_key: Vec<u8>,
) -> CoreResult<Vec<u8>> {
    let net = parse_network(&network)?;
    let seed = seed_from_mnemonic(&mnemonic, &passphrase)?;
    let creds = Nobody {
        cert: developer_cert,
        key: developer_key,
        ..Nobody::default()
    };
    let signer = Signer::new(seed.to_vec(), net, creds.clone()).map_err(gl_err)?;
    let scheduler = Scheduler::new(net, creds).await.map_err(gl_err)?;
    let resp = scheduler.register(&signer, None).await.map_err(gl_err)?;
    Ok(resp.creds)
}

/// Recover access to an already-registered node (e.g. after reinstalling the
/// app with the same mnemonic). Returns fresh device credentials.
#[uniffi::export(async_runtime = "tokio")]
pub async fn recover_node(
    mnemonic: String,
    passphrase: String,
    network: String,
    developer_cert: Vec<u8>,
    developer_key: Vec<u8>,
) -> CoreResult<Vec<u8>> {
    let net = parse_network(&network)?;
    let seed = seed_from_mnemonic(&mnemonic, &passphrase)?;
    let creds = Nobody {
        cert: developer_cert,
        key: developer_key,
        ..Nobody::default()
    };
    let signer = Signer::new(seed.to_vec(), net, creds.clone()).map_err(gl_err)?;
    let scheduler = Scheduler::new(net, creds).await.map_err(gl_err)?;
    let resp = scheduler.recover(&signer).await.map_err(gl_err)?;
    Ok(resp.creds)
}


/// Description tag of a bolt11 invoice, if it carries a direct (non-hash) one.
fn bolt11_description(b11: &str) -> Option<String> {
    let inv: lightning_invoice::Bolt11Invoice = b11.parse().ok()?;
    match inv.description() {
        lightning_invoice::Bolt11InvoiceDescriptionRef::Direct(d) => {
            let s = d.to_string();
            if s.is_empty() { None } else { Some(s) }
        }
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// The connected node
// ---------------------------------------------------------------------------

/// A scheduled Greenlight node with a running signer.
///
/// Create it with `connect_node` every time the app starts; drop it (Kotlin:
/// `close()`) to shut the signer down.
#[derive(uniffi::Object)]
pub struct LightNode {
    client: tokio::sync::Mutex<ClnClient>,
    // Keeping the sender alive keeps the signer loop running; dropping it
    // signals `run_forever` to stop *once it is past init_scheduler*.
    _signer_shutdown: tokio::sync::mpsc::Sender<()>,
    // Guaranteed stop: abort the task on Drop, which also stops a signer still
    // stuck retrying init_scheduler while the device is offline.
    signer_task: tokio::task::JoinHandle<()>,
}

impl Drop for LightNode {
    fn drop(&mut self) {
        self.signer_task.abort();
    }
}

/// Schedule the node on Greenlight's infrastructure, start the signer in the
/// background and return a handle for making RPC calls.
#[uniffi::export(async_runtime = "tokio")]
pub async fn connect_node(
    mnemonic: String,
    passphrase: String,
    network: String,
    device_creds: Vec<u8>,
) -> CoreResult<Arc<LightNode>> {
    let net = parse_network(&network)?;
    let seed = seed_from_mnemonic(&mnemonic, &passphrase)?;
    let creds = Device::from_bytes(device_creds);

    // The signer must keep running while the node is in use: it answers the
    // node's signature requests (payments, channel ops, ...).
    let signer = Signer::new(seed.to_vec(), net, creds.clone()).map_err(gl_err)?;
    let (tx, rx) = tokio::sync::mpsc::channel::<()>(1);
    let signer_task = tokio::spawn(async move {
        if let Err(e) = signer.run_forever(rx).await {
            log::error!("signer stopped: {e}");
        }
    });

    // If scheduling fails, the signer may be stuck in init_scheduler's retry
    // loop where dropping `tx` alone would not stop it — abort explicitly.
    let scheduler = match Scheduler::new(net, creds).await {
        Ok(s) => s,
        Err(e) => {
            signer_task.abort();
            return Err(gl_err(e));
        }
    };
    let client: ClnClient = match scheduler.node().await {
        Ok(c) => c,
        Err(e) => {
            signer_task.abort();
            return Err(gl_err(e));
        }
    };

    Ok(Arc::new(LightNode {
        client: tokio::sync::Mutex::new(client),
        _signer_shutdown: tx,
        signer_task,
    }))
}

#[uniffi::export(async_runtime = "tokio")]
impl LightNode {
    // -- Node info ---------------------------------------------------------

    pub async fn get_info(&self) -> CoreResult<NodeInfo> {
        let mut c = self.client.lock().await.clone();
        let r = c
            .getinfo(cln::GetinfoRequest::default())
            .await
            .map_err(rpc_err)?
            .into_inner();
        let id = hexs(&r.id);
        let connect_string = r
            .address
            .iter()
            .find_map(|a| {
                a.address
                    .as_ref()
                    .map(|host| format!("{id}@{host}:{}", a.port))
            })
            .unwrap_or_else(|| id.clone());
        Ok(NodeInfo {
            id,
            alias: r.alias.unwrap_or_default(),
            color: hexs(&r.color),
            network: r.network,
            blockheight: r.blockheight,
            version: r.version,
            num_peers: r.num_peers,
            num_active_channels: r.num_active_channels,
            num_inactive_channels: r.num_inactive_channels,
            num_pending_channels: r.num_pending_channels,
            fees_collected_msat: msat_of(&r.fees_collected_msat).unwrap_or(0),
            connect_string,
        })
    }

    // -- Funds / liquidity -------------------------------------------------

    pub async fn list_funds(&self) -> CoreResult<Funds> {
        let mut c = self.client.lock().await.clone();
        let r = c
            .list_funds(cln::ListfundsRequest { spent: Some(true) })
            .await
            .map_err(rpc_err)?
            .into_inner();

        let outputs: Vec<OnchainOutput> = r
            .outputs
            .iter()
            .map(|o| OnchainOutput {
                txid: hexs(&o.txid),
                output: o.output,
                amount_msat: msat_of(&o.amount_msat).unwrap_or(0),
                address: o.address.clone(),
                status: match o.status {
                    0 => "unconfirmed",
                    1 => "confirmed",
                    2 => "spent",
                    3 => "immature",
                    _ => "unknown",
                }
                .to_string(),
                blockheight: o.blockheight,
                reserved: o.reserved,
            })
            .collect();

        let channels: Vec<FundsChannel> = r
            .channels
            .iter()
            .map(|ch| FundsChannel {
                peer_id: hexs(&ch.peer_id),
                our_amount_msat: msat_of(&ch.our_amount_msat).unwrap_or(0),
                amount_msat: msat_of(&ch.amount_msat).unwrap_or(0),
                funding_txid: hexs(&ch.funding_txid),
                funding_output: ch.funding_output,
                connected: ch.connected,
                state: channel_state_name(ch.state),
                short_channel_id: ch.short_channel_id.clone(),
                channel_id: ch.channel_id.as_ref().map(|b| hexs(b)).unwrap_or_default(),
            })
            .collect();

        let onchain_confirmed_msat = outputs
            .iter()
            .filter(|o| o.status == "confirmed")
            .map(|o| o.amount_msat)
            .sum();
        let onchain_unconfirmed_msat = outputs
            .iter()
            .filter(|o| o.status == "unconfirmed" || o.status == "immature")
            .map(|o| o.amount_msat)
            .sum();
        // Liquidity: only usable (normal-state) channels count.
        let outbound_msat = channels
            .iter()
            .filter(|c| c.state == "CHANNELD_NORMAL")
            .map(|c| c.our_amount_msat)
            .sum();
        let inbound_msat = channels
            .iter()
            .filter(|c| c.state == "CHANNELD_NORMAL")
            .map(|c| c.amount_msat.saturating_sub(c.our_amount_msat))
            .sum();

        Ok(Funds {
            outputs,
            channels,
            onchain_confirmed_msat,
            onchain_unconfirmed_msat,
            outbound_msat,
            inbound_msat,
        })
    }

    // -- On-chain ----------------------------------------------------------

    /// addresstype: "bech32" | "p2tr" | "all" (None = node default)
    pub async fn new_address(&self, addresstype: Option<String>) -> CoreResult<NewAddressResult> {
        let t = match addresstype.as_deref().map(str::to_lowercase).as_deref() {
            None => None,
            Some("bech32") => Some(0),
            Some("all") => Some(2),
            Some("p2tr") => Some(3),
            Some(other) => {
                return Err(CoreError::Msg(format!("unknown address type: {other}")))
            }
        };
        let mut c = self.client.lock().await.clone();
        let r = c
            .new_addr(cln::NewaddrRequest { addresstype: t })
            .await
            .map_err(rpc_err)?
            .into_inner();
        Ok(NewAddressResult {
            bech32: r.bech32,
            p2tr: r.p2tr,
        })
    }

    pub async fn withdraw(&self, params: WithdrawParams) -> CoreResult<WithdrawResult> {
        let req = cln::WithdrawRequest {
            destination: params.destination.clone(),
            satoshi: Some(amount_or_all(
                if params.all { 0 } else { checked_msat(params.amount_sat)? },
                params.all,
            )),
            minconf: params.minconf,
            utxos: vec![],
            feerate: opt_feerate(&params.feerate)?,
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.withdraw(req).await.map_err(rpc_err)?.into_inner();
        Ok(WithdrawResult {
            txid: hexs(&r.txid),
            tx: hexs(&r.tx),
            psbt: r.psbt,
        })
    }

    // -- Peers & channels --------------------------------------------------

    pub async fn connect_peer(
        &self,
        id: String,
        host: Option<String>,
        port: Option<u32>,
    ) -> CoreResult<ConnectPeerResult> {
        let mut c = self.client.lock().await.clone();
        let r = c
            .connect_peer(cln::ConnectRequest { id, host, port })
            .await
            .map_err(rpc_err)?
            .into_inner();
        Ok(ConnectPeerResult {
            id: hexs(&r.id),
            direction: match r.direction {
                0 => "in",
                1 => "out",
                _ => "unknown",
            }
            .to_string(),
            address: r.address.and_then(|a| a.address),
        })
    }

    pub async fn disconnect_peer(&self, id: String, force: Option<bool>) -> CoreResult<()> {
        let id = hex::decode(&id).map_err(|e| CoreError::Msg(format!("bad peer id: {e}")))?;
        let mut c = self.client.lock().await.clone();
        c.disconnect(cln::DisconnectRequest { id, force })
            .await
            .map_err(rpc_err)?;
        Ok(())
    }

    pub async fn list_channels(&self) -> CoreResult<Vec<PeerChannel>> {
        let mut c = self.client.lock().await.clone();
        let r = c
            .list_peer_channels(cln::ListpeerchannelsRequest::default())
            .await
            .map_err(rpc_err)?
            .into_inner();
        // Resolve peer aliases from gossip — one listnodes per unique peer,
        // best-effort (a peer missing from our gossip store just has no alias).
        let mut aliases: std::collections::HashMap<Vec<u8>, Option<String>> =
            std::collections::HashMap::new();
        for ch in &r.channels {
            if aliases.contains_key(&ch.peer_id) {
                continue;
            }
            let alias = c
                .list_nodes(cln::ListnodesRequest {
                    id: Some(ch.peer_id.clone()),
                    ..Default::default()
                })
                .await
                .ok()
                .and_then(|n| n.into_inner().nodes.into_iter().next())
                .and_then(|n| n.alias)
                .filter(|a| !a.trim().is_empty());
            aliases.insert(ch.peer_id.clone(), alias);
        }
        Ok(r.channels
            .iter()
            .map(|ch| {
                let to_us = msat_of(&ch.to_us_msat);
                let total = msat_of(&ch.total_msat);
                PeerChannel {
                    peer_id: hexs(&ch.peer_id),
                    peer_alias: aliases.get(&ch.peer_id).cloned().flatten(),
                    peer_connected: ch.peer_connected,
                    state: channel_state_name(ch.state),
                    channel_id: ch.channel_id.as_ref().map(|b| hexs(b)),
                    short_channel_id: ch.short_channel_id.clone(),
                    funding_txid: ch.funding_txid.as_ref().map(|b| hexs(b)),
                    funding_outnum: ch.funding_outnum,
                    opener: match ch.opener {
                        0 => "local",
                        1 => "remote",
                        _ => "unknown",
                    }
                    .to_string(),
                    is_private: ch.private,
                    to_us_msat: to_us,
                    total_msat: total,
                    to_them_msat: match (total, to_us) {
                        (Some(t), Some(u)) => Some(t.saturating_sub(u)),
                        _ => None,
                    },
                    spendable_msat: msat_of(&ch.spendable_msat),
                    receivable_msat: msat_of(&ch.receivable_msat),
                    our_reserve_msat: msat_of(&ch.our_reserve_msat),
                    their_reserve_msat: msat_of(&ch.their_reserve_msat),
                    fee_base_msat: msat_of(&ch.fee_base_msat),
                    fee_proportional_millionths: ch.fee_proportional_millionths,
                    dust_limit_msat: msat_of(&ch.dust_limit_msat),
                    our_to_self_delay: ch.our_to_self_delay,
                    their_to_self_delay: ch.their_to_self_delay,
                    max_accepted_htlcs: ch.max_accepted_htlcs,
                    htlc_count: ch.htlcs.len() as u32,
                    in_payments_fulfilled: ch.in_payments_fulfilled,
                    in_fulfilled_msat: msat_of(&ch.in_fulfilled_msat),
                    out_payments_fulfilled: ch.out_payments_fulfilled,
                    out_fulfilled_msat: msat_of(&ch.out_fulfilled_msat),
                    alias_local: ch.alias.as_ref().and_then(|a| a.local.clone()),
                    alias_remote: ch.alias.as_ref().and_then(|a| a.remote.clone()),
                    status: ch.status.clone(),
                    last_stable_connection: ch.last_stable_connection,
                }
            })
            .collect())
    }

    pub async fn open_channel(&self, params: OpenChannelParams) -> CoreResult<OpenChannelResult> {
        let id = hex::decode(&params.peer_id)
            .map_err(|e| CoreError::Msg(format!("bad peer id: {e}")))?;
        let req = cln::FundchannelRequest {
            id,
            amount: Some(amount_or_all(
                if params.all { 0 } else { checked_msat(params.amount_sat)? },
                params.all,
            )),
            feerate: opt_feerate(&params.feerate)?,
            announce: params.announce,
            push_msat: params.push_msat.map(amount),
            close_to: params.close_to.clone(),
            minconf: params.minconf,
            mindepth: params.mindepth,
            reserve: params.reserve_msat.map(amount),
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.fund_channel(req).await.map_err(rpc_err)?.into_inner();
        Ok(OpenChannelResult {
            txid: hexs(&r.txid),
            outnum: r.outnum,
            channel_id: hexs(&r.channel_id),
            close_to: r.close_to.as_ref().map(|b| hexs(b)),
            mindepth: r.mindepth,
        })
    }

    pub async fn close_channel(
        &self,
        params: CloseChannelParams,
    ) -> CoreResult<CloseChannelResult> {
        let req = cln::CloseRequest {
            id: params.id.clone(),
            unilateraltimeout: params.unilateral_timeout,
            destination: params.destination.clone(),
            fee_negotiation_step: params.fee_negotiation_step.clone(),
            wrong_funding: None,
            force_lease_closed: params.force_lease_closed,
            feerange: vec![],
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.close(req).await.map_err(rpc_err)?.into_inner();
        Ok(CloseChannelResult {
            close_type: match r.item_type {
                0 => "mutual",
                1 => "unilateral",
                2 => "unopened",
                _ => "unknown",
            }
            .to_string(),
            txids: {
                let mut ids: Vec<String> = r
                    .txids
                    .iter()
                    .filter(|t| t.len() == 32)
                    .map(|t| hexs(t))
                    .collect();
                if ids.is_empty() {
                    if let Some(t) = r.txid.as_ref().filter(|t| t.len() == 32) {
                        ids.push(hexs(t));
                    }
                }
                ids
            },
        })
    }

    // -- Invoices ----------------------------------------------------------

    pub async fn create_invoice(
        &self,
        params: CreateInvoiceParams,
    ) -> CoreResult<CreateInvoiceResult> {
        let preimage = match &params.preimage_hex {
            Some(p) if !p.is_empty() => Some(
                hex::decode(p).map_err(|e| CoreError::Msg(format!("bad preimage: {e}")))?,
            ),
            _ => None,
        };
        let req = cln::InvoiceRequest {
            amount_msat: Some(amount_or_any(params.amount_msat)),
            description: params.description.clone(),
            label: params.label.clone(),
            expiry: params.expiry,
            fallbacks: params.fallbacks.clone(),
            preimage,
            cltv: params.cltv,
            deschashonly: params.deschashonly,
            exposeprivatechannels: params.exposeprivatechannels.clone(),
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.invoice(req).await.map_err(rpc_err)?.into_inner();
        let warning = r
            .warning_capacity
            .or(r.warning_offline)
            .or(r.warning_deadends)
            .or(r.warning_private_unused)
            .or(r.warning_mpp);
        Ok(CreateInvoiceResult {
            bolt11: r.bolt11,
            payment_hash: hexs(&r.payment_hash),
            payment_secret: hexs(&r.payment_secret),
            expires_at: r.expires_at,
            created_index: r.created_index.unwrap_or(0),
            warning,
        })
    }

    pub async fn list_invoices(
        &self,
        params: ListInvoicesParams,
    ) -> CoreResult<Vec<InvoiceEntry>> {
        let payment_hash = match &params.payment_hash_hex {
            Some(h) if !h.is_empty() => Some(
                hex::decode(h).map_err(|e| CoreError::Msg(format!("bad payment hash: {e}")))?,
            ),
            _ => None,
        };
        let index = match params.index.as_deref() {
            Some("updated") => Some(1),
            Some("created") => Some(0),
            _ => None,
        };
        let req = cln::ListinvoicesRequest {
            label: params.label.clone(),
            invstring: params.invstring.clone(),
            payment_hash,
            offer_id: None,
            index,
            start: params.start,
            limit: params.limit,
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.list_invoices(req).await.map_err(rpc_err)?.into_inner();
        Ok(r.invoices
            .iter()
            .map(|i| InvoiceEntry {
                label: i.label.clone(),
                description: i.description.clone(),
                payment_hash: hexs(&i.payment_hash),
                status: match i.status {
                    0 => "unpaid",
                    1 => "paid",
                    2 => "expired",
                    _ => "unknown",
                }
                .to_string(),
                expires_at: i.expires_at,
                amount_msat: msat_of(&i.amount_msat),
                amount_received_msat: msat_of(&i.amount_received_msat),
                bolt11: i.bolt11.clone(),
                bolt12: i.bolt12.clone(),
                pay_index: i.pay_index,
                paid_at: i.paid_at,
                payment_preimage: i.payment_preimage.as_ref().map(|b| hexs(b)),
                created_index: i.created_index.unwrap_or(0),
                updated_index: i.updated_index,
            })
            .collect())
    }

    // -- Paying ------------------------------------------------------------

    pub async fn pay(&self, params: PayParams) -> CoreResult<PayResult> {
        let req = cln::PayRequest {
            bolt11: params.bolt11.clone(),
            amount_msat: params.amount_msat.map(amount),
            label: params.label.clone(),
            riskfactor: params.riskfactor,
            maxfeepercent: params.maxfeepercent,
            retry_for: params.retry_for,
            maxdelay: params.maxdelay,
            exemptfee: params.exemptfee_msat.map(amount),
            maxfee: params.maxfee_msat.map(amount),
            description: params.description.clone(),
            exclude: params.exclude.clone(),
            partial_msat: params.partial_msat.map(amount),
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.pay(req).await.map_err(rpc_err)?.into_inner();
        Ok(PayResult {
            payment_preimage: hexs(&r.payment_preimage),
            payment_hash: hexs(&r.payment_hash),
            destination: r.destination.as_ref().map(|b| hexs(b)),
            created_at: r.created_at,
            parts: r.parts,
            amount_msat: msat_of(&r.amount_msat).unwrap_or(0),
            amount_sent_msat: msat_of(&r.amount_sent_msat).unwrap_or(0),
            status: match r.status {
                0 => "complete",
                1 => "pending",
                2 => "failed",
                _ => "unknown",
            }
            .to_string(),
            warning_partial_completion: r.warning_partial_completion,
        })
    }

    pub async fn xpay(&self, params: XpayParams) -> CoreResult<XpayResult> {
        let req = cln::XpayRequest {
            invstring: params.invstring.clone(),
            amount_msat: params.amount_msat.map(amount),
            maxfee: params.maxfee_msat.map(amount),
            layers: params.layers.clone(),
            retry_for: params.retry_for,
            partial_msat: params.partial_msat.map(amount),
            maxdelay: params.maxdelay,
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.xpay(req).await.map_err(rpc_err)?.into_inner();
        Ok(XpayResult {
            payment_preimage: hexs(&r.payment_preimage),
            failed_parts: r.failed_parts,
            successful_parts: r.successful_parts,
            amount_msat: msat_of(&r.amount_msat).unwrap_or(0),
            amount_sent_msat: msat_of(&r.amount_sent_msat).unwrap_or(0),
        })
    }

    pub async fn rene_pay(&self, params: RenepayParams) -> CoreResult<RenepayResult> {
        let req = cln::RenepayRequest {
            invstring: params.invstring.clone(),
            amount_msat: params.amount_msat.map(amount),
            maxfee: params.maxfee_msat.map(amount),
            maxdelay: params.maxdelay,
            retry_for: params.retry_for,
            description: params.description.clone(),
            label: params.label.clone(),
            exclude: params.exclude.clone(),
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.rene_pay(req).await.map_err(rpc_err)?.into_inner();
        Ok(RenepayResult {
            payment_preimage: hexs(&r.payment_preimage),
            payment_hash: hexs(&r.payment_hash),
            created_at: r.created_at,
            parts: r.parts,
            amount_msat: msat_of(&r.amount_msat).unwrap_or(0),
            amount_sent_msat: msat_of(&r.amount_sent_msat).unwrap_or(0),
            status: match r.status {
                0 => "complete",
                1 => "pending",
                2 => "failed",
                _ => "unknown",
            }
            .to_string(),
            bolt11: r.bolt11.clone(),
            bolt12: r.bolt12.clone(),
            groupid: r.groupid,
        })
    }

    pub async fn list_pays(&self, params: ListPaysParams) -> CoreResult<Vec<PayListEntry>> {
        let payment_hash = match &params.payment_hash_hex {
            Some(h) if !h.is_empty() => Some(
                hex::decode(h).map_err(|e| CoreError::Msg(format!("bad payment hash: {e}")))?,
            ),
            _ => None,
        };
        let status = match params.status.as_deref() {
            Some("pending") => Some(0),
            Some("complete") => Some(1),
            Some("failed") => Some(2),
            _ => None,
        };
        let index = match params.index.as_deref() {
            Some("updated") => Some(1),
            Some("created") => Some(0),
            _ => None,
        };
        let req = cln::ListpaysRequest {
            bolt11: params.bolt11.clone(),
            payment_hash,
            status,
            index,
            start: params.start,
            limit: params.limit,
            ..Default::default()
        };
        let mut c = self.client.lock().await.clone();
        let r = c.list_pays(req).await.map_err(rpc_err)?.into_inner();
        Ok(r.pays
            .iter()
            .map(|p| PayListEntry {
                payment_hash: hexs(&p.payment_hash),
                // NB: ListpaysPaysStatus has a different order than PayStatus.
                status: match p.status {
                    0 => "pending",
                    1 => "failed",
                    2 => "complete",
                    _ => "unknown",
                }
                .to_string(),
                destination: p.destination.as_ref().map(|b| hexs(b)),
                created_at: p.created_at,
                completed_at: p.completed_at,
                label: p.label.clone(),
                bolt11: p.bolt11.clone(),
                bolt12: p.bolt12.clone(),
                // xpay does not persist the invoice description the way `pay`
                // does, so listpays often returns none — recover it from the
                // stored bolt11 instead (bolt12: the description is in the
                // local invoice copy, nothing to parse here).
                description: p
                    .description
                    .clone()
                    .filter(|d| !d.is_empty())
                    .or_else(|| p.bolt11.as_deref().and_then(bolt11_description)),
                amount_msat: msat_of(&p.amount_msat),
                amount_sent_msat: msat_of(&p.amount_sent_msat),
                preimage: p.preimage.as_ref().map(|b| hexs(b)),
                number_of_parts: p.number_of_parts,
                created_index: p.created_index,
                updated_index: p.updated_index,
            })
            .collect())
    }

    /// On-chain wallet transaction history, in the node's own order.
    pub async fn list_transactions(&self) -> CoreResult<Vec<WalletTx>> {
        let mut c = self.client.lock().await.clone();
        let r = c
            .list_transactions(cln::ListtransactionsRequest {})
            .await
            .map_err(rpc_err)?
            .into_inner();
        Ok(r.transactions
            .iter()
            .map(|t| WalletTx {
                txid: hexs(&t.hash),
                blockheight: t.blockheight,
                inputs: t
                    .inputs
                    .iter()
                    .map(|i| WalletTxInput {
                        txid: hexs(&i.txid),
                        index: i.index,
                    })
                    .collect(),
                outputs: t
                    .outputs
                    .iter()
                    .map(|o| WalletTxOutput {
                        index: o.index,
                        amount_msat: o.amount_msat.as_ref().map(|a| a.msat).unwrap_or(0),
                    })
                    .collect(),
            })
            .collect())
    }

    // -- Decode ------------------------------------------------------------

    pub async fn decode(&self, invstring: String) -> CoreResult<DecodedInvoice> {
        let mut c = self.client.lock().await.clone();
        let r = c
            .decode(cln::DecodeRequest { string: invstring })
            .await
            .map_err(rpc_err)?
            .into_inner();
        Ok(DecodedInvoice {
            item_type: match r.item_type {
                0 => "bolt12_offer",
                1 => "bolt12_invoice",
                2 => "bolt12_invoice_request",
                3 => "bolt11_invoice",
                4 => "rune",
                5 => "emergency_recover",
                _ => "unknown",
            }
            .to_string(),
            valid: r.valid,
            currency: r.currency.clone(),
            amount_msat: msat_of(&r.amount_msat),
            description: r.description.clone(),
            payee: r.payee.as_ref().map(|b| hexs(b)),
            payment_hash: r.payment_hash.as_ref().map(|b| hexs(b)),
            created_at: r.created_at,
            expiry: r.expiry,
            min_final_cltv_expiry: r.min_final_cltv_expiry,
            offer_description: r.offer_description.clone(),
            offer_issuer: r.offer_issuer.clone(),
            invoice_amount_msat: msat_of(&r.invoice_amount_msat),
        })
    }
}
