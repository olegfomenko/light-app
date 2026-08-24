//! Plain data types exposed to Kotlin/Swift through UniFFI.

/// Errors surfaced to the mobile side.
#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum CoreError {
    #[error("{0}")]
    Msg(String),
}

impl From<anyhow::Error> for CoreError {
    fn from(e: anyhow::Error) -> Self {
        CoreError::Msg(format!("{e:#}"))
    }
}

/// Map any displayable error (e.g. tonic::Status) into a CoreError.
pub fn rpc_err<E: std::fmt::Display>(e: E) -> CoreError {
    CoreError::Msg(format!("rpc error: {e}"))
}

pub type CoreResult<T> = Result<T, CoreError>;

// ---------------------------------------------------------------------------
// Node / info
// ---------------------------------------------------------------------------

#[derive(uniffi::Record, Clone, Debug)]
pub struct NodeInfo {
    pub id: String,
    pub alias: String,
    pub color: String,
    pub network: String,
    pub blockheight: u32,
    pub version: String,
    pub num_peers: u32,
    pub num_active_channels: u32,
    pub num_inactive_channels: u32,
    pub num_pending_channels: u32,
    pub fees_collected_msat: u64,
    /// "id@host:port" when the node has a public address, otherwise just the id.
    pub connect_string: String,
}

// ---------------------------------------------------------------------------
// Funds / liquidity
// ---------------------------------------------------------------------------

#[derive(uniffi::Record, Clone, Debug)]
pub struct OnchainOutput {
    pub txid: String,
    pub output: u32,
    pub amount_msat: u64,
    pub address: Option<String>,
    /// unconfirmed | confirmed | spent | immature
    pub status: String,
    pub blockheight: Option<u32>,
    pub reserved: bool,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FundsChannel {
    pub peer_id: String,
    pub our_amount_msat: u64,
    pub amount_msat: u64,
    pub funding_txid: String,
    pub funding_output: u32,
    pub connected: bool,
    pub state: String,
    pub short_channel_id: Option<String>,
    pub channel_id: String,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct Funds {
    pub outputs: Vec<OnchainOutput>,
    pub channels: Vec<FundsChannel>,
    // Convenience aggregates (computed in Rust so every UI gets them for free).
    pub onchain_confirmed_msat: u64,
    pub onchain_unconfirmed_msat: u64,
    pub outbound_msat: u64,
    pub inbound_msat: u64,
}

// ---------------------------------------------------------------------------
// Channels
// ---------------------------------------------------------------------------

#[derive(uniffi::Record, Clone, Debug)]
pub struct PeerChannel {
    pub peer_id: String,
    /// Node alias from gossip (listnodes) — None when the peer is unknown
    /// to our gossip store or has no alias.
    pub peer_alias: Option<String>,
    pub peer_connected: bool,
    pub state: String,
    pub channel_id: Option<String>,
    pub short_channel_id: Option<String>,
    pub funding_txid: Option<String>,
    pub funding_outnum: Option<u32>,
    pub opener: String,
    pub is_private: Option<bool>,
    pub to_us_msat: Option<u64>,
    pub total_msat: Option<u64>,
    /// total - to_us (what the peer owns in this channel)
    pub to_them_msat: Option<u64>,
    pub spendable_msat: Option<u64>,
    pub receivable_msat: Option<u64>,
    pub our_reserve_msat: Option<u64>,
    pub their_reserve_msat: Option<u64>,
    pub fee_base_msat: Option<u64>,
    pub fee_proportional_millionths: Option<u32>,
    pub dust_limit_msat: Option<u64>,
    pub our_to_self_delay: Option<u32>,
    pub their_to_self_delay: Option<u32>,
    pub max_accepted_htlcs: Option<u32>,
    pub htlc_count: u32,
    pub in_payments_fulfilled: Option<u64>,
    pub in_fulfilled_msat: Option<u64>,
    pub out_payments_fulfilled: Option<u64>,
    pub out_fulfilled_msat: Option<u64>,
    pub alias_local: Option<String>,
    pub alias_remote: Option<String>,
    pub status: Vec<String>,
    pub last_stable_connection: Option<u64>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct OpenChannelParams {
    pub peer_id: String,
    /// Amount in satoshi; ignored when `all` is true.
    pub amount_sat: u64,
    pub all: bool,
    /// "slow" | "normal" | "urgent" | "<n>perkw" | "<n>perkb"
    pub feerate: Option<String>,
    pub announce: Option<bool>,
    pub push_msat: Option<u64>,
    pub close_to: Option<String>,
    pub minconf: Option<u32>,
    pub mindepth: Option<u32>,
    pub reserve_msat: Option<u64>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct OpenChannelResult {
    pub txid: String,
    pub outnum: u32,
    pub channel_id: String,
    pub close_to: Option<String>,
    pub mindepth: Option<u32>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct CloseChannelParams {
    /// Channel id, short channel id or peer id.
    pub id: String,
    /// Seconds to wait for the peer before falling back to a unilateral close.
    pub unilateral_timeout: Option<u32>,
    pub destination: Option<String>,
    pub fee_negotiation_step: Option<String>,
    pub force_lease_closed: Option<bool>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct CloseChannelResult {
    /// mutual | unilateral | unopened
    pub close_type: String,
    pub txids: Vec<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct ConnectPeerResult {
    pub id: String,
    pub direction: String,
    pub address: Option<String>,
}

// ---------------------------------------------------------------------------
// On-chain
// ---------------------------------------------------------------------------

#[derive(uniffi::Record, Clone, Debug)]
pub struct NewAddressResult {
    pub bech32: Option<String>,
    pub p2tr: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct WithdrawParams {
    pub destination: String,
    /// Amount in satoshi; ignored when `all` is true.
    pub amount_sat: u64,
    pub all: bool,
    pub minconf: Option<u32>,
    /// "slow" | "normal" | "urgent" | "<n>perkw" | "<n>perkb"
    pub feerate: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct WithdrawResult {
    pub txid: String,
    pub tx: String,
    pub psbt: String,
}

// ---------------------------------------------------------------------------
// Invoices
// ---------------------------------------------------------------------------

#[derive(uniffi::Record, Clone, Debug)]
pub struct CreateInvoiceParams {
    /// None means "any amount".
    pub amount_msat: Option<u64>,
    pub description: String,
    pub label: String,
    /// Seconds until the invoice expires (CLN default: 7 days).
    pub expiry: Option<u64>,
    pub fallbacks: Vec<String>,
    pub preimage_hex: Option<String>,
    pub cltv: Option<u32>,
    pub deschashonly: Option<bool>,
    pub exposeprivatechannels: Vec<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct CreateInvoiceResult {
    pub bolt11: String,
    pub payment_hash: String,
    pub payment_secret: String,
    pub expires_at: u64,
    pub created_index: u64,
    pub warning: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct ListInvoicesParams {
    pub label: Option<String>,
    pub invstring: Option<String>,
    pub payment_hash_hex: Option<String>,
    /// "created" | "updated"
    pub index: Option<String>,
    pub start: Option<u64>,
    pub limit: Option<u32>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct InvoiceEntry {
    pub label: String,
    pub description: Option<String>,
    pub payment_hash: String,
    /// unpaid | paid | expired
    pub status: String,
    pub expires_at: u64,
    pub amount_msat: Option<u64>,
    pub amount_received_msat: Option<u64>,
    pub bolt11: Option<String>,
    pub bolt12: Option<String>,
    pub pay_index: Option<u64>,
    pub paid_at: Option<u64>,
    pub payment_preimage: Option<String>,
    pub created_index: u64,
    pub updated_index: Option<u64>,
}

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

#[derive(uniffi::Record, Clone, Debug)]
pub struct PayParams {
    pub bolt11: String,
    pub amount_msat: Option<u64>,
    pub label: Option<String>,
    pub riskfactor: Option<f64>,
    pub maxfeepercent: Option<f64>,
    pub retry_for: Option<u32>,
    pub maxdelay: Option<u32>,
    pub exemptfee_msat: Option<u64>,
    pub maxfee_msat: Option<u64>,
    pub description: Option<String>,
    pub exclude: Vec<String>,
    pub partial_msat: Option<u64>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct PayResult {
    pub payment_preimage: String,
    pub payment_hash: String,
    pub destination: Option<String>,
    pub created_at: f64,
    pub parts: u32,
    pub amount_msat: u64,
    pub amount_sent_msat: u64,
    /// complete | pending | failed
    pub status: String,
    pub warning_partial_completion: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct XpayParams {
    pub invstring: String,
    pub amount_msat: Option<u64>,
    pub maxfee_msat: Option<u64>,
    pub layers: Vec<String>,
    pub retry_for: Option<u32>,
    pub partial_msat: Option<u64>,
    pub maxdelay: Option<u32>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct XpayResult {
    pub payment_preimage: String,
    pub failed_parts: u64,
    pub successful_parts: u64,
    pub amount_msat: u64,
    pub amount_sent_msat: u64,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct RenepayParams {
    pub invstring: String,
    pub amount_msat: Option<u64>,
    pub maxfee_msat: Option<u64>,
    pub maxdelay: Option<u32>,
    pub retry_for: Option<u32>,
    pub description: Option<String>,
    pub label: Option<String>,
    pub exclude: Vec<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct RenepayResult {
    pub payment_preimage: String,
    pub payment_hash: String,
    pub created_at: f64,
    pub parts: u32,
    pub amount_msat: u64,
    pub amount_sent_msat: u64,
    /// complete | pending | failed
    pub status: String,
    pub bolt11: Option<String>,
    pub bolt12: Option<String>,
    pub groupid: Option<u64>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct ListPaysParams {
    pub bolt11: Option<String>,
    pub payment_hash_hex: Option<String>,
    /// "pending" | "complete" | "failed"
    pub status: Option<String>,
    /// "created" | "updated"
    pub index: Option<String>,
    pub start: Option<u64>,
    pub limit: Option<u32>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct PayListEntry {
    pub payment_hash: String,
    /// pending | failed | complete
    pub status: String,
    pub destination: Option<String>,
    pub created_at: u64,
    pub completed_at: Option<u64>,
    pub label: Option<String>,
    pub bolt11: Option<String>,
    pub bolt12: Option<String>,
    pub description: Option<String>,
    pub amount_msat: Option<u64>,
    pub amount_sent_msat: Option<u64>,
    pub preimage: Option<String>,
    pub number_of_parts: Option<u64>,
    pub created_index: Option<u64>,
    pub updated_index: Option<u64>,
}

// ---------------------------------------------------------------------------
// Decode (invoice preview before paying)
// ---------------------------------------------------------------------------

#[derive(uniffi::Record, Clone, Debug)]
pub struct DecodedInvoice {
    /// bolt11_invoice | bolt12_invoice | bolt12_offer | ...
    pub item_type: String,
    pub valid: bool,
    pub currency: Option<String>,
    pub amount_msat: Option<u64>,
    pub description: Option<String>,
    pub payee: Option<String>,
    pub payment_hash: Option<String>,
    pub created_at: Option<u64>,
    pub expiry: Option<u64>,
    pub min_final_cltv_expiry: Option<u32>,
    pub offer_description: Option<String>,
    pub offer_issuer: Option<String>,
    pub invoice_amount_msat: Option<u64>,
}

// ---------------------------------------------------------------------------
// On-chain wallet transactions (listtransactions)
// ---------------------------------------------------------------------------

#[derive(uniffi::Record, Clone, Debug)]
pub struct WalletTxInput {
    /// Funding txid of the outpoint this input spends (display byte order).
    pub txid: String,
    pub index: u32,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct WalletTxOutput {
    pub index: u32,
    pub amount_msat: u64,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct WalletTx {
    pub txid: String,
    /// 0 = unconfirmed (still in the mempool).
    pub blockheight: u32,
    pub inputs: Vec<WalletTxInput>,
    pub outputs: Vec<WalletTxOutput>,
}
