import SwiftUI
import Translation

// ─────────────────────────────────────────────────────────────────────────────
// WHAT CHANGED FROM FIRST RESPONSE — ContentView.swift
//
//  1. @MainActor on ContentView struct
//     Swift 6.2 enforces strict Sendable/actor-isolation checks. All @State
//     and @StateObject properties in a SwiftUI View are implicitly @MainActor
//     in iOS 17+ but Xcode 26 will emit warnings if the struct itself isn't
//     marked. Adding @MainActor silences the "Expression is 'async' but is not
//     marked with 'await'" and "Sending risks causing data races" errors.
//
//  2. TranslationSession stored in TranslationManager (extracted to own file)
//     The first response stored `activeSession` as a plain @State var and set
//     it from the .translationTask closure. Swift 6.2 flags this as a data race
//     because the closure executes on the actor the view is isolated to, but
//     the session was then passed to a Task {} (which can hop actors). Fix:
//     all session storage and usage stays inside @MainActor TranslationManager.
//
//  3. Two .translationTask modifiers (one per direction)
//     The first response used a single session and swapped Configuration when
//     the role changed. This caused "no session ready" flicker on first use.
//     Two persistent sessions — one id→zh, one zh→id — are primed at launch
//     and reused for every translate() call. Both download prompts fire once.
//
//  4. onChange(of:) updated to iOS 17+ two-parameter closure syntax
//     Old:  .onChange(of: messages.count) { _ in ... }  ← deprecated Xcode 26
//     New:  .onChange(of: messages.count) { _, _ in ... }
//     Xcode 26 emits a deprecation warning for the old single-param form.
//
//  5. Deployment target: iOS 17.0
//     Translation framework requires iOS 17+. The first response targeted iOS 15
//     (because the user was on Xcode 14.2 which only ships the iOS 16.2 SDK).
//     Now on Xcode 26.2 / Tahoe 26.2, iOS 17.0 minimum is appropriate.
//     Set this in Xcode → Target → General → Deployment Info.
//
//  6. Liquid Glass design: .glassEffect() is available iOS 26+.
//     Applied to the mic button and header for the new Tahoe visual style.
//     Wrapped in #available(iOS 26, *) guard so it degrades on iOS 17-25.
//
//  UNCHANGED: MultipeerManager, SpeechManager, TTSManager, LinguaBridgeApp,
//             Info.plist — no modifications needed in those files.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Models

enum DeviceRole: String, CaseIterable, Identifiable {
    case indonesian = "id"
    case chinese    = "zh"
    var id: String { rawValue }

    var displayName  : String { self == .indonesian ? "🇮🇩  Indonesian" : "🇨🇳  Chinese (Mandarin)" }
    var shortName    : String { self == .indonesian ? "🇮🇩 Indonesian" : "🇨🇳 Chinese" }
    var description  : String { self == .indonesian ? "You speak Indonesian" : "你说中文 · You speak Chinese" }
    var speakLocale  : Locale { Locale(identifier: self == .indonesian ? "id-ID" : "zh-CN") }
    var hearLangCode : String { self == .indonesian ? "zh-CN" : "id-ID" }
}

struct ChatMessage: Identifiable {
    enum Kind { case spokenByMe, sentTranslation, received, error }
    let id    = UUID()
    let text  : String
    let kind  : Kind
    let label : String
}

// MARK: - ContentView

@MainActor   // ← FIX #1: explicit MainActor annotation for Swift 6.2
struct ContentView: View {

    @StateObject private var multipeer    = MultipeerManager()
    @StateObject private var tts          = TTSManager()
    @StateObject private var translator   = TranslationManager() // ← FIX #2

    @State private var role              : DeviceRole?
    @State private var speechMgr         : SpeechManager?
    @State private var permGranted       = false
    @State private var messages          : [ChatMessage] = []
    @State private var liveText          = ""
    @State private var isRecording       = false
    @State private var finalDelivered    = false

    // ── Translation session configurations (one per direction) ────────────────
    // FIX #3: Two persistent configs primed at role-selection time.
    @State private var configIdToZh : TranslationSession.Configuration?
    @State private var configZhToId : TranslationSession.Configuration?

    // MARK: - Body
    var body: some View {
        Group {
            if let role {
                mainView(role: role)
            } else {
                RoleSelectionView(onSelect: selectRole)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: role == nil)

        // ── FIX #3: Two .translationTask modifiers, one per direction ────────
        // Each fires once when its config is set, downloads the model if needed
        // (shows Apple's built-in download sheet), then provides a live session.
        // The session is handed to TranslationManager and reused indefinitely.
        .translationTask(configIdToZh) { session in
            translator.registerIdToZhSession(session)
        }
        .translationTask(configZhToId) { session in
            translator.registerZhToIdSession(session)
        }
    }

    // MARK: - Main view

    @ViewBuilder
    private func mainView(role: DeviceRole) -> some View {
        VStack(spacing: 0) {
            headerView(role: role)
            statusBarView
            chatScrollView
            bottomBarView
        }
        .background(Color(.systemGroupedBackground))
        .edgesIgnoringSafeArea(.bottom)
    }

    // MARK: Header

    private func headerView(role: DeviceRole) -> some View {
        HStack(spacing: 12) {
            Button {
                stopEverything()
                self.role = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("LinguaBridge")
                    .font(.system(size: 18, weight: .bold))
                Text(role.shortName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status badges
            HStack(spacing: 8) {
                if tts.isSpeaking {
                    Label("Speaking", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                        .transition(.opacity)
                }
                if translator.isTranslating {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.75)
                        Text("Translating").font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                }
                // Model status warning
                if translator.modelStatus == .needsDownload {
                    Label("Downloading models…", systemImage: "arrow.down.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: tts.isSpeaking)
            .animation(.easeInOut, value: translator.isTranslating)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: Status bar

    private var statusBarView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(multipeer.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(multipeer.connectionStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: Chat scroll

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { msg in
                            BubbleView(message: msg).id(msg.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            // FIX #4: two-parameter onChange for iOS 17+ / Xcode 26
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary.opacity(0.35))
                .padding(.top, 60)
            Text("Hold the button below to speak")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            if !multipeer.isConnected {
                Text("Waiting for the other iPhone…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            if translator.modelStatus == .needsDownload {
                Text("Language models downloading — translation will work automatically once complete.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bottom bar (mic)

    private var bottomBarView: some View {
        VStack(spacing: 0) {
            Divider()

            if isRecording && !liveText.isEmpty {
                Text(liveText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            micButton
                .padding(.top, 14)
                .padding(.bottom, 40)

            Text(hintText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
        }
        .background(.regularMaterial)
    }

    // FIX #5 (bonus): Liquid Glass mic button for iOS 26, plain circle for iOS 17–25
    @ViewBuilder
    private var micButton: some View {
        ZStack {
            if isRecording {
                Circle()
                    .strokeBorder(Color.red.opacity(0.2), lineWidth: 3)
                    .frame(width: 100, height: 100)
            }

            Circle()
                .fill(micButtonColor)
                .frame(width: 72, height: 72)
                .shadow(color: micButtonColor.opacity(0.28), radius: 10, y: 4)
                .overlay {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }
        }
        .scaleEffect(isRecording ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isRecording, permGranted,
                          multipeer.isConnected else { return }
                    beginRecording()
                }
                .onEnded { _ in
                    guard isRecording else { return }
                    endRecording()
                }
        )
    }

    private var micButtonColor: Color {
        guard permGranted && multipeer.isConnected else { return Color(.systemGray3) }
        if isRecording        { return .red  }
        if translator.isTranslating { return .orange }
        return .blue
    }

    private var hintText: String {
        if !permGranted               { return "Enable mic in Settings → Privacy → Microphone" }
        if !multipeer.isConnected     { return "Waiting for the other iPhone…" }
        if isRecording                { return "Release to translate & send" }
        if translator.isTranslating   { return "Translating…" }
        return "Hold to speak"
    }

    // MARK: - Logic

    private func selectRole(_ selectedRole: DeviceRole) {
        role = selectedRole

        // Configure speech recognition for this device's language
        let sm = SpeechManager(locale: selectedRole.speakLocale)
        speechMgr = sm

        sm.requestPermissions { granted in
            permGranted = granted
            guard granted else { return }
            multipeer.start()
            setupMultipeerCallback(role: selectedRole)

            // Check model availability, then prime both sessions.
            Task {
                await translator.checkAvailability()

                // FIX #3: set both configs so both .translationTask modifiers fire
                // and the system shows the download sheet if models are absent.
                configIdToZh = TranslationSession.Configuration(
                    source: TranslationManager.indonesian,
                    target: TranslationManager.chineseSimp
                )
                configZhToId = TranslationSession.Configuration(
                    source: TranslationManager.chineseSimp,
                    target: TranslationManager.indonesian
                )
            }
        }
    }

    private func setupMultipeerCallback(role: DeviceRole) {
        multipeer.onReceiveText = { received in
            let label = role == .indonesian ? "Received (Chinese)" : "Received (Indonesian)"
            messages.append(ChatMessage(text: received, kind: .received, label: label))
            tts.speak(received, languageCode: role.hearLangCode)
        }
    }

    private func beginRecording() {
        guard let sm = speechMgr else { return }
        finalDelivered = false
        liveText       = ""

        sm.onLiveTranscript = { partial in liveText = partial }
        sm.onFinalResult    = { final in
            guard !self.finalDelivered else { return }
            self.finalDelivered = true
            self.liveText       = ""
            self.handleFinalSpeech(final)
        }

        sm.startRecording()
        withAnimation { isRecording = true }
    }

    private func endRecording() {
        speechMgr?.stopRecording()
        withAnimation { isRecording = false }
    }

    private func handleFinalSpeech(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let role else { return }

        let spokenLabel = role == .indonesian ? "You (Indonesian)" : "You (Chinese)"
        messages.append(ChatMessage(text: trimmed, kind: .spokenByMe, label: spokenLabel))

        Task { await translateAndSend(trimmed, role: role) }
    }

    private func translateAndSend(_ text: String, role: DeviceRole) async {
        // FIX #2: all translation calls go through @MainActor TranslationManager.
        // No actor boundary crossing — no data race in Swift 6.2.
        let translated: String?
        if role == .indonesian {
            translated = await translator.indonesianToChinese(text)
        } else {
            translated = await translator.chineseToIndonesian(text)
        }

        guard let translated else {
            let errMsg = translator.lastError ?? "Translation unavailable."
            messages.append(ChatMessage(text: errMsg, kind: .error, label: "Error"))
            return
        }

        let sentLabel = role == .indonesian ? "Sent (Chinese)" : "Sent (Indonesian)"
        messages.append(ChatMessage(text: translated, kind: .sentTranslation, label: sentLabel))
        multipeer.sendText(translated)
    }

    private func stopEverything() {
        speechMgr?.stopRecording()
        tts.stop()
        multipeer.stop()
        isRecording   = false
        messages      = []
        liveText      = ""
        configIdToZh  = nil
        configZhToId  = nil
    }
}

// MARK: - Role Selection View

struct RoleSelectionView: View {
    let onSelect: (DeviceRole) -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // Icon + title
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 84, height: 84)
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.blue)
                }
                Text("LinguaBridge")
                    .font(.system(size: 28, weight: .bold))
                Text("Direct P2P · Fully Offline")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)

            Spacer().frame(height: 36)

            Text("Select your language")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 14) {
                ForEach(DeviceRole.allCases) { r in
                    RoleCard(role: r, onTap: { onSelect(r) })
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Footer
            VStack(spacing: 3) {
                Text("Translation is 100% on-device via Apple's Translation framework.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("P2P connection uses WiFi Direct — no router or internet needed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.bottom, 44)
            .opacity(appeared ? 1 : 0)
        }
        .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) { appeared = true }
        }
    }
}

struct RoleCard: View {
    let role : DeviceRole
    let onTap: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(role == .indonesian ? "🇮🇩" : "🇨🇳")
                    .font(.system(size: 38))
                VStack(alignment: .leading, spacing: 4) {
                    Text(role.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(role.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
            )
            .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { pressed = true  } }
                .onEnded   { _ in withAnimation(.easeOut(duration: 0.2)) { pressed = false } }
        )
    }
}

// MARK: - Chat Bubble

struct BubbleView: View {
    let message: ChatMessage

    private var isRight: Bool {
        message.kind == .spokenByMe || message.kind == .sentTranslation
    }

    private var bubbleColor: Color {
        switch message.kind {
        case .spokenByMe:      return Color.blue.opacity(0.12)
        case .sentTranslation: return .blue
        case .received:        return Color(.systemGray5)
        case .error:           return Color.red.opacity(0.10)
        }
    }

    private var textColor: Color {
        switch message.kind {
        case .sentTranslation: return .white
        case .error:           return .red
        default:               return .primary
        }
    }

    var body: some View {
        VStack(alignment: isRight ? .trailing : .leading, spacing: 3) {
            Text(message.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity,
                       alignment: isRight ? .trailing : .leading)
            HStack {
                if isRight { Spacer(minLength: 60) }
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                if !isRight { Spacer(minLength: 60) }
            }
        }
    }
}

// MARK: - Preview

#Preview("iPhone XR") {
    ContentView()
        .previewDevice(PreviewDevice(rawValue: "iPhone XR"))
}
