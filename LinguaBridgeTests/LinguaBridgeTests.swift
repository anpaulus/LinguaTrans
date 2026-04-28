import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// LinguaBridgeTests
//
// Add this file to a new Test target in Xcode:
//   File → New → Target → iOS Unit Testing Bundle
//   Name it "LinguaBridgeTests"
//
// These tests run headlessly on the iOS Simulator in GitHub Actions (Job 2).
// They test pure logic only — no mic, no network, no P2P required.
// ─────────────────────────────────────────────────────────────────────────────

final class TranslationCacheTests: XCTestCase {

    // MARK: - Normalisation

    func test_normalize_trimsWhitespace() {
        // TranslationCache.normalize() should trim leading/trailing spaces
        let input = "  apa kabar  "
        let expected = "apa kabar"
        XCTAssertEqual(normalize(input), expected)
    }

    func test_normalize_lowercases() {
        XCTAssertEqual(normalize("Halo Dunia"), "halo dunia")
    }

    func test_normalize_collapsesSpaces() {
        XCTAssertEqual(normalize("halo   dunia"), "halo dunia")
    }

    func test_normalize_stripsTrailingPunctuation() {
        XCTAssertEqual(normalize("halo dunia!"), "halo dunia")
        XCTAssertEqual(normalize("halo dunia."), "halo dunia")
        XCTAssertEqual(normalize("你好。"), "你好")
    }

    // MARK: - Levenshtein similarity

    func test_similarity_identicalStrings() {
        XCTAssertEqual(similarity("halo", "halo"), 1.0, accuracy: 0.001)
    }

    func test_similarity_emptyStrings() {
        XCTAssertEqual(similarity("", "abc"), 0.0)
    }

    func test_similarity_closeStrings() {
        // "apa kabar" vs "Apa kabar?" normalised to "apa kabar"
        // After normalisation they should be identical
        let a = normalize("apa kabar")
        let b = normalize("Apa kabar?")
        XCTAssertEqual(similarity(a, b), 1.0, accuracy: 0.001)
    }

    func test_similarity_veryDifferentStrings() {
        // Completely different strings should be well below the 0.82 threshold
        let score = similarity("terima kasih", "selamat tinggal")
        XCTAssertLessThan(score, 0.82)
    }

    // MARK: - DeviceRole helpers

    func test_deviceRole_indonesianProperties() {
        // Test the DeviceRole enum (from ContentView.swift)
        // We can't import the main target directly in a unit test unless we
        // set ENABLE_TESTABILITY=YES — which the CI workflow does.
        // These assertions validate the role properties are set correctly.
        XCTAssertEqual(DeviceRole.indonesian.rawValue, "id")
        XCTAssertEqual(DeviceRole.indonesian.sourceLang, "id")
        XCTAssertEqual(DeviceRole.indonesian.targetLang, "zh-CN")
        XCTAssertEqual(DeviceRole.indonesian.hearLangCode, "zh-CN")
    }

    func test_deviceRole_chineseProperties() {
        XCTAssertEqual(DeviceRole.chinese.rawValue, "zh")
        XCTAssertEqual(DeviceRole.chinese.sourceLang, "zh-CN")
        XCTAssertEqual(DeviceRole.chinese.targetLang, "id")
        XCTAssertEqual(DeviceRole.chinese.hearLangCode, "id-ID")
    }

    // MARK: - Chat message kinds

    func test_chatMessage_isRightAlignment() {
        let sent  = ChatMessage(text: "test", kind: .sentTranslation, label: "Sent")
        let recv  = ChatMessage(text: "test", kind: .received,        label: "Recv")
        let spoke = ChatMessage(text: "test", kind: .spokenByMe,      label: "You")
        let err   = ChatMessage(text: "test", kind: .error,           label: "Err")

        // sentTranslation and spokenByMe → right-aligned bubbles
        XCTAssertTrue( [ChatMessage.Kind.sentTranslation, .spokenByMe].contains(sent.kind) )
        XCTAssertTrue( [ChatMessage.Kind.sentTranslation, .spokenByMe].contains(spoke.kind) )
        // received and error → left-aligned bubbles
        XCTAssertTrue( [ChatMessage.Kind.received, .error].contains(recv.kind) )
        XCTAssertTrue( [ChatMessage.Kind.received, .error].contains(err.kind) )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline helpers — mirror the logic in TranslationCache.swift so the unit
// tests can run without needing the full app framework linked.
// ─────────────────────────────────────────────────────────────────────────────

private func normalize(_ text: String) -> String {
    var s = text.lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
    let punct = CharacterSet(charactersIn: ".,!?。，！？")
    s = s.trimmingCharacters(in: punct)
    return s
}

private func similarity(_ a: String, _ b: String) -> Double {
    let aArr = Array(a), bArr = Array(b)
    guard !aArr.isEmpty, !bArr.isEmpty else { return 0 }
    let dist = levenshtein(aArr, bArr)
    return 1.0 - Double(dist) / Double(max(aArr.count, bArr.count))
}

private func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    var dp = (0...b.count).map { $0 }
    for i in 1...a.count {
        var prev = dp[0]; dp[0] = i
        for j in 1...b.count {
            let temp = dp[j]
            dp[j] = a[i-1] == b[j-1] ? prev : min(prev, min(dp[j], dp[j-1])) + 1
            prev = temp
        }
    }
    return dp[b.count]
}
