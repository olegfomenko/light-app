//
//  OnboardingFlow.swift
//  LightApp
//
//  Create / restore onboarding: welcome, seed reveal or 24-box restore entry,
//  Greenlight developer certificates, and node registration / recovery.
//  Port of android/src/main/java/app/light/wallet/ui/onboarding/OnboardingFlow.kt.
//
//  Android's per-screen SecureScreen() (FLAG_SECURE) has no iOS equivalent;
//  the app root's `privacyCover()` blanks the app-switcher snapshot instead.
//  Android's BackHandler is replaced by the explicit Back buttons only — iOS
//  has no system back to mirror.
//

import SwiftUI
import UniformTypeIdentifiers

private enum ObStep {
    case welcome, create, restore, certs, register
}

@MainActor
struct OnboardingFlow: View {
    let repository: WalletRepository
    let onDone: () -> Void

    @State private var step: ObStep = .welcome
    @State private var mnemonic: String = ""
    @State private var isRestore: Bool = false
    @State private var certBytes: Data? = nil
    @State private var keyBytes: Data? = nil

    init(repository: WalletRepository, onDone: @escaping () -> Void) {
        self.repository = repository
        self.onDone = onDone
    }

    var body: some View {
        ZStack(alignment: .top) {
            Tokens.Bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    stepContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 78)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Android draws edge-to-edge; 78pt of top padding is measured
            // from the physical top of the screen, like the design mock.
            .ignoresSafeArea(edges: .top)
            .dismissesKeyboard()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            ObWelcome(
                onCreate: {
                    isRestore = false
                    mnemonic = (try? generateMnemonic()) ?? ""
                    step = .create
                },
                onRestore: {
                    isRestore = true
                    // A previously generated (create-flow) seed must never
                    // leak into the restore boxes.
                    mnemonic = ""
                    step = .restore
                }
            )
        case .create:
            ObCreateWallet(
                mnemonic: mnemonic,
                onNext: { step = .certs },
                onBack: { step = .welcome }
            )
        case .restore:
            ObRestoreWallet(
                mnemonic: mnemonic,
                onMnemonic: { mnemonic = $0 },
                onNext: { step = .certs },
                onBack: { step = .welcome }
            )
        case .certs:
            ObCertificates(
                certBytes: $certBytes,
                keyBytes: $keyBytes,
                onNext: { step = .register },
                onBack: { step = isRestore ? .restore : .create }
            )
        case .register:
            ObRegister(
                repository: repository,
                mnemonic: mnemonic,
                certBytes: certBytes,
                keyBytes: keyBytes,
                isRestore: isRestore,
                onDone: onDone,
                onBack: { step = .certs }
            )
        }
    }
}

// ─────────────────────────── Shared bits ───────────────────────────

/// Step heading (Android `headlineSmall` → Space Grotesk 700 24, per design).
private func obHeadline(_ text: String) -> some View {
    Text(text)
        .font(Tokens.spaceGrotesk(24, .bold))
        .foregroundStyle(Tokens.Text)
}

/// No-ink pressed feedback (Android's `noRipple`); Components' PressFadeStyle
/// is private to that file, so the flow carries its own copy.
private struct ObPressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Closed polygon in the logo's 1024×1024 viewBox, scaled to the frame.
private struct ObPoly: Shape {
    let points: [(CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaled = points.map { p in
            CGPoint(x: rect.minX + p.0 / 1024 * rect.width,
                    y: rect.minY + p.1 / 1024 * rect.height)
        }
        guard let first = scaled.first else { return path }
        path.move(to: first)
        for p in scaled.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}

/// The app logo, ported from res/drawable/logo_lightapp.xml (the iOS asset
/// catalog only carries the AppIcon): radial dark tile, three concentric
/// accent rings, and the two-tone bolt over its offset shadow.
private struct ObLogo: View {
    var size: CGFloat = 88
    var radius: CGFloat = 22

    var body: some View {
        ZStack {
            RadialGradient(
                stops: [
                    .init(color: Color(hex: 0xFF241C09), location: 0),
                    .init(color: Color(hex: 0xFF120E05), location: 0.55),
                    .init(color: Color(hex: 0xFF070809), location: 1),
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: size * 870 / 1024
            )
            ring(r: 170, w: 14, opacity: 0.28)
            ring(r: 290, w: 12, opacity: 0.18)
            ring(r: 420, w: 12, opacity: 0.09)
            ObPoly(points: [
                (567, 247), (336, 593.5), (487.8, 593.5),
                (448.2, 841), (732, 494.5), (563.7, 494.5),
            ])
            .fill(Color(hex: 0x990A0803))
            ObPoly(points: [(555, 225), (324, 571.5), (475.8, 571.5), (436.2, 819)])
                .fill(LinearGradient(
                    colors: [Color(hex: 0xFFFFF085), Color(hex: 0xFFFACC15)],
                    startPoint: UnitPoint(x: 324 / 1024, y: 225 / 1024),
                    endPoint: UnitPoint(x: 720 / 1024, y: 403 / 1024)
                ))
            ObPoly(points: [(555, 225), (436.2, 819), (720, 472.5), (551.7, 472.5)])
                .fill(LinearGradient(
                    colors: [Color(hex: 0xFFEAB308), Color(hex: 0xFFB8860B)],
                    startPoint: UnitPoint(x: 436 / 1024, y: 225 / 1024),
                    endPoint: UnitPoint(x: 720 / 1024, y: 819 / 1024)
                ))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // Design: box-shadow 0 0 60px rgba(250,204,21,.18).
        .shadow(color: Tokens.Accent.opacity(0.18), radius: 30)
    }

    private func ring(r: CGFloat, w: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(Tokens.Accent.opacity(opacity), lineWidth: size * w / 1024)
            .frame(width: size * 2 * r / 1024, height: size * 2 * r / 1024)
    }
}

/// Open-source disclaimer with the repo URL highlighted; tapping opens GitHub.
private struct ObOpenSourceNote: View {
    let prefix: String
    let suffix: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        (Text(prefix)
            + Text("github.com/olegfomenko/light-app")
                .font(Tokens.jetBrainsMono(12.5, .bold))
                .foregroundColor(Tokens.Accent)
            + Text(suffix))
            .font(Tokens.manrope(12.5))
            .foregroundColor(Tokens.Faint)
            .lineSpacing(6)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: "https://github.com/olegfomenko/light-app") {
                    openURL(url)
                }
            }
    }
}

// ─────────────────────────── Welcome ───────────────────────────

private struct ObWelcome: View {
    let onCreate: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ObLogo()
            Text("LightApp")
                .font(Tokens.spaceGrotesk(34, .bold))
                .kerning(-0.5)
                .foregroundStyle(Tokens.Text)
            Text("A full Core Lightning node in your pocket, powered by Greenlight. Built by Engineers for Engineers.")
                .font(Tokens.manrope(15))
                .foregroundStyle(Tokens.Label)
                .lineSpacing(8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)

        VStack(spacing: 12) {
            PillButton(text: "Create new wallet", height: 54) { onCreate() }
            GhostButton(text: "Restore from seed") { onRestore() }
            ObOpenSourceNote(
                prefix: "LightApp is open source. We recommend double-checking the code at ",
                suffix: " before using the application."
            )
        }
        .padding(.top, 120)
    }
}

// ─────────────────────────── Create ───────────────────────────

private struct ObCreateWallet: View {
    let mnemonic: String
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var revealed = false

    private var words: [String] {
        mnemonic.split(separator: " ").map(String.init)
    }

    var body: some View {
        obHeadline("Your recovery phrase")
        Text("This BIP39 seed derives your node identity and on-chain keys. Write the \(words.count) words down, in order, on paper.")
            .font(Tokens.manrope(14))
            .foregroundStyle(Tokens.Label)
            .lineSpacing(6)
            .padding(.top, 8)
            .padding(.bottom, 20)
        SeedGrid(words: words, revealed: revealed, onReveal: { revealed = true })
        Text("Write these words down — they are the only way to recover your wallet. They never leave this device.")
            .font(Tokens.manrope(13.5))
            .foregroundStyle(Tokens.TextMid)
            .lineSpacing(5)
            .padding(.top, 14)
        SoftPillButton(text: "Copy seed", height: 46) {
            copyToClipboard(label: "Seed", value: mnemonic, sensitive: true)
        }
        .padding(.top, 14)
        PillButton(text: "I wrote it down", height: 54) { onNext() }
            .padding(.top, 20)
        GhostButton(text: "Back") { onBack() }
            .padding(.top, 10)
    }
}

// ─────────────────────────── Restore ───────────────────────────

/// Cheap per-word sanity check: lowercase a–z only (the full checksum runs on
/// the whole phrase).
private func obValidWordPrefix(_ word: String) -> Bool {
    word.allSatisfy { $0 >= "a" && $0 <= "z" }
}

private struct ObRestoreWallet: View {
    let onMnemonic: (String) -> Void
    let onNext: () -> Void
    let onBack: () -> Void

    // 24 separate boxes; pasting a whole phrase into any box distributes the
    // words across the following boxes (12-word seeds also validate).
    @State private var words: [String]

    init(
        mnemonic: String,
        onMnemonic: @escaping (String) -> Void,
        onNext: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.onMnemonic = onMnemonic
        self.onNext = onNext
        self.onBack = onBack
        let parts = mnemonic.split(separator: " ").map(String.init)
        _words = State(initialValue: (0..<24).map { i in
            i < parts.count ? parts[i].trimmingCharacters(in: .whitespaces) : ""
        })
    }

    @FocusState private var focusedBox: Int?

    private func update(_ index: Int, _ raw: String) {
        let parts = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        if parts.count > 1 {
            // A multi-word paste is the whole phrase: fill from the first box
            // regardless of which box received it. The rewrite MUST be
            // deferred one runloop: a focused TextField ignores a bound-value
            // mutation made synchronously inside its own `set` and keeps its
            // internal paste buffer — the bug where box 1 kept showing the
            // entire phrase while boxes 2-24 filled correctly.
            let distributed = (0..<24).map { i in i < parts.count ? parts[i].lowercased() : "" }
            // Unfocus FIRST: while a TextField is being edited it keeps its
            // internal (dirty) buffer and ignores external binding writes, so
            // the receiving box would keep showing the whole pasted phrase.
            // Dropping first-responder makes it re-read the binding.
            focusedBox = nil
            Task { @MainActor in
                words = distributed
                onMnemonic(words.filter { !$0.isEmpty }.joined(separator: " "))
            }
            return
        }
        words[index] = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        onMnemonic(words.filter { !$0.isEmpty }.joined(separator: " "))
    }

    private var filled: Int { words.filter { !$0.isEmpty }.count }
    private var phrase: String { words.filter { !$0.isEmpty }.joined(separator: " ") }
    private var complete: Bool {
        filled == 24 || (filled == 12
            && words.dropFirst(12).allSatisfy { $0.isEmpty }
            && words.prefix(12).allSatisfy { !$0.isEmpty })
    }
    private var valid: Bool { complete && validateMnemonic(phrase: phrase) }

    var body: some View {
        obHeadline("Restore from seed")
        Text("Enter your 12 or 24 word recovery phrase. Paste the whole phrase into any field to fill them all.")
            .font(Tokens.manrope(14))
            .foregroundStyle(Tokens.Label)
            .lineSpacing(6)
            .padding(.top, 8)
            .padding(.bottom, 20)
        VStack(spacing: 10) {
            ForEach(0..<12, id: \.self) { row in
                HStack(spacing: 10) {
                    wordBox(row * 2)
                    wordBox(row * 2 + 1)
                }
            }
        }
        if complete && !valid {
            Text("Invalid phrase (checksum failed)")
                .font(Tokens.manrope(12.5))
                .foregroundStyle(Tokens.Red)
                .padding(.top, 8)
        }
        PillButton(text: "Continue", enabled: valid, height: 54) { onNext() }
            .padding(.top, 20)
        GhostButton(text: "Back") { onBack() }
            .padding(.top, 10)
    }

    private func wordBox(_ index: Int) -> some View {
        let word = words[index]
        let borderColor: Color = (!word.isEmpty && !obValidWordPrefix(word))
            ? Tokens.Red.opacity(0.5)
            : Color(hex: 0x0FFFFFFF)
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(Tokens.jetBrainsMono(12.5, .semibold))
                .foregroundStyle(Tokens.Faint)
            TextField("", text: Binding(
                get: { words[index] },
                set: { update(index, $0) }
            ))
            .font(Tokens.jetBrainsMono(14, .semibold))
            .foregroundStyle(Tokens.Text)
            .tint(Tokens.Accent)
            .keyboardType(.asciiCapable)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .focused($focusedBox, equals: index)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity)
        .background(Tokens.Field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }
}

// ─────────────────────────── Certificates ───────────────────────────

private struct ObCertificates: View {
    @Binding var certBytes: Data?
    @Binding var keyBytes: Data?
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var showCertPicker = false
    @State private var showKeyPicker = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        obHeadline("Greenlight credentials")
        (Text("Upload the developer certificate pair from the ")
            + Text("Greenlight console")
                .font(Tokens.manrope(14, .bold))
                .foregroundColor(Tokens.Accent)
            + Text(". They authorize this app to register and schedule your node."))
            .font(Tokens.manrope(14))
            .foregroundColor(Tokens.Label)
            .lineSpacing(6)
            .padding(.top, 8)
            .padding(.bottom, 22)
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: "https://greenlight.blockstream.com/") {
                    openURL(url)
                }
            }
        VStack(spacing: 12) {
            ObCertCard(
                name: "client.crt",
                sub: certBytes.map { "\($0.count) bytes loaded" } ?? "Developer certificate · PEM",
                done: certBytes != nil
            ) { showCertPicker = true }
                .fileImporter(
                    isPresented: $showCertPicker,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: false
                ) { certBytes = Self.readPicked($0) }
            ObCertCard(
                name: "client-key.pem",
                sub: keyBytes.map { "\($0.count) bytes loaded" } ?? "Private key · keep secret",
                done: keyBytes != nil
            ) { showKeyPicker = true }
                .fileImporter(
                    isPresented: $showKeyPicker,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: false
                ) { keyBytes = Self.readPicked($0) }
        }
        Text("Certificate and key are stored encrypted in the iOS Keychain. The files you picked stay where you chose them — keep them safe.")
            .font(Tokens.manrope(12.5))
            .foregroundStyle(Tokens.Dim)
            .lineSpacing(5)
            .padding(.top, 14)
        PillButton(
            text: "Continue",
            enabled: certBytes != nil && keyBytes != nil,
            height: 54
        ) { onNext() }
            .padding(.top, 24)
        GhostButton(text: "Back") { onBack() }
            .padding(.top, 10)
    }

    /// Android's `readUri` analogue: a failed read yields nil (which clears a
    /// previously loaded file, exactly like the Android callback).
    private static func readPicked(_ result: Result<[URL], Error>) -> Data? {
        guard case .success(let urls) = result, let url = urls.first else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

private struct ObCertCard: View {
    let name: String
    let sub: String
    let done: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Tokens.jetBrainsMono(14, .bold))
                        .foregroundStyle(Tokens.Text)
                    Text(sub)
                        .font(Tokens.manrope(13))
                        .foregroundStyle(Tokens.Dim)
                }
                Spacer(minLength: 0)
                Text("✓")
                    .font(Tokens.manrope(14, .semibold))
                    .foregroundStyle(done ? Tokens.Green : Color(hex: 0x1AFFFFFF))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                // Dashed border per design.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        done ? Tokens.Green.opacity(0.5) : Color(hex: 0x26FFFFFF),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(ObPressFade())
    }
}

// ─────────────────────────── Register / recover ───────────────────────────

@MainActor
private struct ObRegister: View {
    let repository: WalletRepository
    let mnemonic: String
    let certBytes: Data?
    let keyBytes: Data?
    let isRestore: Bool
    let onDone: () -> Void
    let onBack: () -> Void

    @State private var busy = false
    /// -1 idle, 0..2 stages, 3 done.
    @State private var stage = -1
    @State private var error: String? = nil

    var body: some View {
        obHeadline(isRestore ? "Recovering your node" : "Registering your node")
        Text(isRestore
            ? "We'll recover your existing Greenlight node from the seed and issue fresh device credentials for this phone."
            : "We'll register a brand-new Core Lightning node for your seed on mainnet. Takes a few seconds.")
            .font(Tokens.manrope(14))
            .foregroundStyle(Tokens.Label)
            .lineSpacing(6)
            .padding(.top, 8)
            .padding(.bottom, 22)
        VStack(spacing: 12) {
            ObRegRow(
                title: "Loading credentials",
                sub: "mTLS keypair → keystore",
                stage: stage, index: 0
            )
            ObRegRow(
                title: isRestore ? "scheduler.recover(node)" : "scheduler.register(node)",
                sub: "gl.blckstrm.com:2111",
                stage: stage, index: 1
            )
            ObRegRow(
                title: "Node scheduled",
                sub: "signer ready · device credentials stored",
                stage: stage, index: 2
            )
        }
        if let error {
            Text(error)
                .font(Tokens.manrope(14))
                .foregroundStyle(Tokens.Red)
                .padding(.top, 14)
        }
        ObOpenSourceNote(
            prefix: "Before you continue: this app is open source — double-check the code at ",
            suffix: "."
        )
        .padding(.top, 24)
        PillButton(
            text: isRestore ? "Recover node" : "Register node",
            enabled: !busy,
            height: 54
        ) { run() }
            .padding(.top, 14)
        GhostButton(text: "Back", enabled: !busy) { onBack() }
            .padding(.top, 10)
    }

    private func run() {
        busy = true
        error = nil
        stage = 0
        Task { @MainActor in
            defer { busy = false }
            do {
                stage = 1
                try await repository.setupWallet(
                    mnemonic: mnemonic.trimmingCharacters(in: .whitespacesAndNewlines),
                    passphrase: "",
                    network: "bitcoin",
                    developerCert: certBytes ?? Data(),
                    developerKey: keyBytes ?? Data(),
                    restore: isRestore
                )
                stage = 3
                onDone()
            } catch {
                self.error = Self.message(error)
                stage = -1
            }
        }
    }

    /// Kotlin `e.message ?: "registration failed"` — unwrap the core's
    /// `CoreError.Msg` rather than showing its reflection-dump description.
    private nonisolated static func message(_ error: Error) -> String {
        if case CoreError.Msg(let message) = error, !message.isEmpty { return message }
        let d = (error as NSError).localizedDescription
        return d.isEmpty ? "registration failed" : d
    }
}

private struct ObRegRow: View {
    let title: String
    let sub: String
    let stage: Int
    let index: Int

    var body: some View {
        let done = stage > index
        let active = stage == index
        let ringColor: Color = done
            ? Tokens.Accent
            : (active ? Tokens.Accent.opacity(0.5) : Color(hex: 0x1FFFFFFF))
        HStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(ringColor, lineWidth: 2)
                if done {
                    Text("✓")
                        .font(Tokens.manrope(13, .bold))
                        .foregroundStyle(Tokens.Accent)
                } else if active {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Tokens.Accent)
                        .scaleEffect(0.6)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Tokens.manrope(14, .bold))
                    .foregroundStyle(done || active ? Tokens.Text : Tokens.Faint)
                Text(sub)
                    .font(Tokens.jetBrainsMono(12.5))
                    .foregroundStyle(Tokens.Dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: 0x0FFFFFFF), lineWidth: 1)
        )
    }
}
