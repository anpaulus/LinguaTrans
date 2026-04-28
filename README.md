# LinguaBridge — P2P Indonesian ↔ Chinese Translator

A fully offline, peer-to-peer translation app for two iPhone XRs.
No router, no internet, no server required.

---

## How It Works

```
iPhone A (Indonesian)              iPhone B (Chinese)
───────────────────                ────────────────────
  1. Hold mic button   ──────────────────────────────>
  2. Speak Indonesian                                 
  3. On-device STT (id-ID)                           
  4. Apple Translation (id→zh)                       
  5. Send Chinese text ──WiFi Direct──>  Receive Chinese text
                                         6. TTS speaks Chinese 🔊

                       <──WiFi Direct── Send Indonesian text
  Receive Indonesian                   3. On-device STT (zh-CN)
  6. TTS speaks Indonesian 🔊          4. Apple Translation (zh→id)
                                       1. Hold mic button (vice versa)
```

---

## Requirements

| Item | Requirement |
|---|---|
| iOS | **17.0 or later** (for Apple Translation framework) |
| iPhone XR | Fully supported — ships up to iOS 17 |
| Xcode | 15.0+ |
| Internet | **Not required** after language models downloaded |
| Router | **Not required** — pure P2P WiFi Direct |

---

## Project Structure

```
LinguaBridge/
├── LinguaBridgeApp.swift      App entry point (@main)
├── ContentView.swift          Main SwiftUI UI + app coordinator
├── MultipeerManager.swift     P2P WiFi Direct (MCNearbyService)
├── SpeechManager.swift        On-device speech-to-text (SFSpeechRecognizer)
├── TTSManager.swift           Text-to-speech (AVSpeechSynthesizer)
└── Info.plist                 Required permission keys
```

---

## Xcode Setup Steps

### 1. Create a new Xcode project
- Template: **iOS → App**
- Language: **Swift**
- Interface: **SwiftUI**
- Minimum deployment: **iOS 17.0**

### 2. Add source files
Replace the generated files with all `.swift` files in this folder.

### 3. Add Info.plist keys
Either:
- Replace the Xcode-generated `Info.plist` with the one in this folder, **or**
- Manually add these keys in **Xcode → Target → Info**:
  - `Privacy - Microphone Usage Description`
  - `Privacy - Speech Recognition Usage Description`
  - `Privacy - Local Network Usage Description`
  - `Bonjour services` → `_lingua-bridge._tcp`, `_lingua-bridge._udp`

### 4. Capabilities (Xcode → Target → Signing & Capabilities)
- **Background Modes** — add "Uses Bluetooth LE accessories" (optional, for background connectivity)
- Make sure **App Sandbox** allows **Outgoing Connections (Client)** and **Incoming Connections (Server)** if targeting macOS simulator

### 5. Signing
- Set your Team in **Signing & Capabilities**
- Use a real device (Multipeer Connectivity doesn't work in Simulator)

### 6. First launch
On first use:
1. Open the app on **both iPhones**
2. Select language on each (one picks 🇮🇩, the other picks 🇨🇳)
3. Both devices will automatically connect via WiFi Direct
4. iOS will prompt to download the Indonesian ↔ Chinese translation model (~50 MB each)
5. After download, all translation works **100% offline**

---

## Usage

1. **Hold** the blue mic button to start speaking
2. **Release** to stop and send the translation to the other phone
3. The other phone **automatically plays the translation** through its speaker
4. Repeat in both directions — full duplex conversation

---

## Technology Stack

| Component | API Used | Offline? |
|---|---|---|
| P2P Connection | `MultipeerConnectivity` | ✅ Yes |
| Speech Recognition | `Speech` (SFSpeechRecognizer) | ✅ Yes (on-device model) |
| Translation | `Translation` (iOS 17+) | ✅ Yes (downloaded model) |
| Text-to-Speech | `AVSpeechSynthesizer` | ✅ Yes (built-in voices) |

---

## Troubleshooting

**Devices don't connect**
- Both iPhones must have WiFi turned ON (no need to join same network — P2P creates its own)
- Make sure Bluetooth is also ON (Multipeer Connectivity uses both WiFi + BT for discovery)
- Try force-quitting and reopening the app on both devices

**Translation says "no session"**
- The Apple Translation language pack needs to download once on first use
- Connect to WiFi/cellular briefly, open the app, and wait for the download prompt

**Speech recognition not working**
- Check `Settings → Privacy → Speech Recognition` — LinguaBridge must be allowed
- For Indonesian (id-ID): the on-device model should be available on iOS 17
- If it fails, the app will fall back to server-based recognition (requires internet)

**TTS has wrong accent / voice**
- Go to `Settings → Accessibility → Spoken Content → Voices`
- Download the Indonesian (id-ID) or Chinese Mandarin (zh-CN) voice for best quality

---

## Limitations & Possible Improvements

- Currently **hold-to-talk** only. Could add VAD (voice activity detection) for hands-free mode.
- Translation language pair is fixed (Indonesian ↔ Chinese). Easy to extend to other pairs via `DeviceRole`.
- No conversation history persistence across app launches.
- Could add **audio streaming** (send audio bytes instead of text) to reduce latency further.

---

## License
GNU GENERAL PUBLIC LICENSE.
