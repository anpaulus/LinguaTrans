import Speech
import AVFoundation
import Foundation

/// Wraps Apple's Speech framework for on-device speech recognition.
/// Works offline after the language model is downloaded (automatic on first use).
class SpeechManager: NSObject, ObservableObject {

    // MARK: - State
    @Published var isRecording    : Bool   = false
    @Published var liveTranscript : String = ""
    @Published var isAvailable    : Bool   = false

    /// Fires on the main thread with the final recognised string when the user stops speaking.
    var onFinalResult: ((String) -> Void)?

    // MARK: - Private
    private var recognizer       : SFSpeechRecognizer?
    private var recognitionTask  : SFSpeechRecognitionTask?
    private var recognitionReq   : SFSpeechAudioBufferRecognitionRequest?
    private let audioEngine       = AVAudioEngine()
    private var currentLocale    : Locale

    // MARK: - Init
    init(locale: Locale = Locale(identifier: "id-ID")) {
        currentLocale = locale
        super.init()
        setupRecognizer(for: locale)
    }

    // MARK: - Setup
    private func setupRecognizer(for locale: Locale) {
        recognizer          = SFSpeechRecognizer(locale: locale)
        recognizer?.delegate = self
        DispatchQueue.main.async {
            self.isAvailable = self.recognizer?.isAvailable ?? false
        }
    }

    /// Call this after role selection to switch languages.
    func updateLocale(_ locale: Locale) {
        currentLocale = locale
        setupRecognizer(for: locale)
    }

    // MARK: - Permissions
    /// Request microphone + speech recognition permissions.
    /// Returns `true` if both are granted.
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            guard authStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // MARK: - Recording
    func startRecording() {
        guard !isRecording, let recognizer, recognizer.isAvailable else { return }

        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        DispatchQueue.main.async { self.liveTranscript = "" }

        // Configure audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement,
                                         options: [.duckOthers, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[STT] Audio session error: \(error.localizedDescription)")
            return
        }

        // Build recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults   = true
        // Prefer on-device recognition (iOS 13+); falls back to server if unavailable
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionReq = request

        // Tap the microphone
        let inputNode = audioEngine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.liveTranscript = text }

                if result.isFinal {
                    DispatchQueue.main.async {
                        self.onFinalResult?(text)
                        self.stopRecording()
                    }
                }
            }

            if let error {
                // Ignore "no speech detected" errors silently
                let code = (error as NSError).code
                if code != 1110 {
                    print("[STT] Recognition error: \(error.localizedDescription)")
                }
                self.stopRecording()
            }
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            print("[STT] Engine start error: \(error.localizedDescription)")
            stopRecording()
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionReq?.endAudio()
        recognitionTask?.finish()   // triggers isFinal
        recognitionReq  = nil
        recognitionTask = nil

        DispatchQueue.main.async { self.isRecording = false }

        // Deactivate audio session so TTS can take over
        try? AVAudioSession.sharedInstance().setActive(false,
             options: .notifyOthersOnDeactivation)
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension SpeechManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                          availabilityDidChange available: Bool) {
        DispatchQueue.main.async { self.isAvailable = available }
    }
}
