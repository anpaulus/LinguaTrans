import AVFoundation
import Foundation
import Combine

/// Speaks translated text aloud using on-device TTS (AVSpeechSynthesizer).
/// No internet required. Language voices are built into iOS.
class TTSManager: NSObject, ObservableObject {
    @Published var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speak
    /// Speak `text` in the given BCP-47 language code.
    /// e.g. "zh-CN" for Mandarin, "id-ID" for Indonesian.
    func speak(_ text: String, languageCode: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Stop anything currently playing
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default,
                options: [.duckOthers, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[TTS] Audio session error: \(error.localizedDescription)")
        }

        let utterance           = AVSpeechUtterance(string: text)
        utterance.voice         = AVSpeechSynthesisVoice(language: languageCode)
        // Slightly slower than default for clarity
        utterance.rate          = AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.pitchMultiplier = 1.0
        utterance.volume        = 1.0

        if utterance.voice == nil {
            print("[TTS] Warning: no voice found for '\(languageCode)'. Using default.")
        }

        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
        try? AVAudioSession.sharedInstance().setActive(false,
             options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
