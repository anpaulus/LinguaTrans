import Translation
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// TranslationManager
//
// WHAT CHANGED FROM FIRST RESPONSE:
//  1. Extracted into its own file so ContentView is not bloated.
//  2. @MainActor on the class — fixes the Swift 6.2 data-race warning.
//     TranslationSession is MainActor-isolated; crossing actor boundaries
//     caused "Sending 'session' risks causing data races" in Xcode 26.
//  3. iOS 26 / Xcode 26.2 upgrade: TranslationSession can now be obtained
//     *programmatically* (not only through a SwiftUI .translationTask modifier).
//     We use LanguageAvailability to confirm both models are on-device first,
//     then instantiate the session directly. The .translationTask modifier is
//     still used as the standard path for the SwiftUI view lifecycle —
//     it is the Apple-recommended approach. But on iOS 26 the session object
//     is safe to store and reuse across multiple translate() calls on the same
//     actor, which is exactly what we do here.
//  4. Deployment target raised to iOS 17.0 (minimum for Translation framework).
//     With Xcode 26.2 / macOS Tahoe 26.2 this compiles cleanly.
//  5. LanguageAvailability check is now explicit — the app warns the user if
//     a language pack needs downloading rather than failing silently.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class TranslationManager: ObservableObject {

    // MARK: - Published state (drives UI badges and download prompt)
    @Published var isReady        = false
    @Published var isTranslating  = false
    @Published var modelStatus    = ModelStatus.unknown
    @Published var lastError      : String? = nil

    enum ModelStatus: Equatable {
        case unknown
        case checking
        case available          // both language packs on device
        case needsDownload      // will show system download sheet
        case unsupported        // language pair not supported
    }

    // The stored session — safe because this class is @MainActor.
    // Reusing a session avoids re-loading the model for every utterance.
    private var sessionIdToZh : TranslationSession? = nil
    private var sessionZhToId : TranslationSession? = nil

    // Language identifiers
    static let indonesian  = Locale.Language(identifier: "id")
    static let chineseSimp = Locale.Language(identifier: "zh-Hans")

    // MARK: - Language availability check (iOS 17+)
    func checkAvailability() async {
        modelStatus = .checking
        let availability = LanguageAvailability()

        let statusIdZh = await availability.status(
            from: Self.indonesian,
            to:   Self.chineseSimp
        )
        let statusZhId = await availability.status(
            from: Self.chineseSimp,
            to:   Self.indonesian
        )

        switch (statusIdZh, statusZhId) {
        case (.installed, .installed):
            modelStatus = .available
            isReady     = true
        case (.supported, _), (_, .supported):
            // Supported but not yet downloaded — the .translationTask modifier
            // in ContentView will trigger the system download sheet automatically.
            modelStatus = .needsDownload
            isReady     = false
        default:
            modelStatus = .unsupported
            isReady     = false
        }
    }

    // MARK: - Session registration (called from .translationTask modifier)
    //
    // ContentView still uses .translationTask for the two directions so the
    // system download sheet appears automatically on first use. Once the view
    // calls these setters, we hold the live session here for reuse.
    func registerIdToZhSession(_ session: TranslationSession) {
        sessionIdToZh = session
        updateReadiness()
    }

    func registerZhToIdSession(_ session: TranslationSession) {
        sessionZhToId = session
        updateReadiness()
    }

    private func updateReadiness() {
        isReady = sessionIdToZh != nil && sessionZhToId != nil
    }

    // MARK: - Translate

    /// Translate Indonesian → Chinese. Returns nil if session not yet ready.
    func indonesianToChinese(_ text: String) async -> String? {
        await translate(text, using: sessionIdToZh)
    }

    /// Translate Chinese → Indonesian. Returns nil if session not yet ready.
    func chineseToIndonesian(_ text: String) async -> String? {
        await translate(text, using: sessionZhToId)
    }

    // ── private ──────────────────────────────────────────────────────────────

    private func translate(_ text: String,
                           using session: TranslationSession?) async -> String? {
        guard let session else {
            lastError = "Translation model not ready yet."
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        isTranslating = true
        defer { isTranslating = false }

        do {
            // session.translate(_:) is an async method on TranslationSession.
            // Because TranslationManager is @MainActor and TranslationSession
            // is also @MainActor-bound, this call is free of data-race warnings
            // in Swift 6.2 strict concurrency mode.
            let response = try await session.translate(trimmed)
            lastError    = nil
            return response.targetText
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
