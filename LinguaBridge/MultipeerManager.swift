import MultipeerConnectivity
import Foundation
import Combine

/// Manages peer-to-peer WiFi Direct connection using Apple's Multipeer Connectivity.
/// No router or internet required — works completely offline between two iPhones.
class MultipeerManager: NSObject, ObservableObject {
    @Published var connectedPeers: [MCPeerID] = []
    // MARK: - Constants
    private static let serviceType = "lingua-bridge"   // Max 15 chars, lowercase/hyphen only

    // MARK: - MPC objects
    private let myPeerID   = MCPeerID(displayName: UIDevice.current.name)
    private var session    : MCSession!
    private var advertiser : MCNearbyServiceAdvertiser!
    private var browser    : MCNearbyServiceBrowser!

    // MARK: - Published state
    @Published var isConnected     : Bool   = false
    @Published var connectionStatus: String = "Not connected"
    //@Published var connectedPeers  : [MCPeerID] = []
    
    /// Called on the main thread whenever a text message arrives from the peer.
    var onReceiveText: ((String) -> Void)?

    // MARK: - Init
    override init() {
        super.init()
        buildSession()
    }

    private func buildSession() {
        session    = MCSession(peer: myPeerID,
                               securityIdentity: nil,
                               encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                              discoveryInfo: nil,
                                              serviceType: Self.serviceType)
        browser    = MCNearbyServiceBrowser(peer: myPeerID,
                                            serviceType: Self.serviceType)
        session.delegate    = self
        advertiser.delegate = self
        browser.delegate    = self
    }

    // MARK: - Public API

    /// Start advertising this device and browsing for peers simultaneously.
    /// Both devices should call this — whichever finds the other first sends the invite.
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        DispatchQueue.main.async {
            self.connectionStatus = "Searching for nearby device…"
        }
    }

    /// Stop all MPC activity and disconnect.
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectedPeers = []
            self.connectionStatus = "Disconnected"
        }
    }

    /// Send a UTF-8 text string to all connected peers reliably.
    func sendText(_ text: String) {
        guard !session.connectedPeers.isEmpty,
              let data = text.data(using: .utf8) else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("[MPC] Send error: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {

    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            self.isConnected    = !session.connectedPeers.isEmpty
            switch state {
            case .connected:
                self.connectionStatus = "Connected to \(peerID.displayName) ✓"
            case .connecting:
                self.connectionStatus = "Connecting to \(peerID.displayName)…"
            case .notConnected:
                self.connectionStatus = session.connectedPeers.isEmpty
                    ? "Connection lost — searching…"
                    : "Connected"
                // Re-browse if we lost the only peer
                if session.connectedPeers.isEmpty {
                    self.browser.startBrowsingForPeers()
                }
            @unknown default:
                break
            }
        }
    }

    /// Incoming text from the peer arrives here.
    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.onReceiveText?(text)
        }
    }

    // Required stubs
    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?,
                 withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    /// Auto-accept every invitation — fine for a private two-device app.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    /// Immediately invite any found peer.
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.connectedPeers = self.session.connectedPeers
        }
    }
}
