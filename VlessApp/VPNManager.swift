import Foundation
import NetworkExtension

final class VPNManager {
    static let shared = VPNManager()
    static let extBundleID = "com.yourid.VlessApp.VlessPacketTunnel"

    enum State: String {
        case off = "disconnected"
        case connecting = "connecting"
        case connected = "connected"
    }

    private(set) var manager: NETunnelProviderManager?

    var status: State {
        switch manager?.connection.status ?? .invalid {
        case .connected:
            return .connected
        case .connecting, .reasserting:
            return .connecting
        default:
            return .off
        }
    }

    var session: NETunnelProviderSession? {
        manager?.connection as? NETunnelProviderSession
    }

    /// Adds a stage label while preserving the original error domain and code.
    private func diagnosticError(_ error: Error, stage: String) -> NSError {
        let original = error as NSError
        var info = original.userInfo
        info[NSLocalizedDescriptionKey] = "\(stage): \(original.localizedDescription)"
        info[NSUnderlyingErrorKey] = original
        info["VPNDiagnosticStage"] = stage

        return NSError(
            domain: original.domain,
            code: original.code,
            userInfo: info
        )
    }

    func prepare(completion: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                completion(self.diagnosticError(error, stage: "loadAllFromPreferences"))
                return
            }

            let ours = (managers ?? []).filter { candidate in
                let proto = candidate.protocolConfiguration as? NETunnelProviderProtocol
                return proto?.providerBundleIdentifier == VPNManager.extBundleID
            }

            for extra in ours.dropFirst() {
                extra.removeFromPreferences()
            }

            let manager = ours.first ?? NETunnelProviderManager()

            manager.loadFromPreferences { loadError in
                if let loadError = loadError, ours.first != nil {
                    completion(self.diagnosticError(loadError, stage: "manager.loadFromPreferences"))
                    return
                }

                if loadError != nil || !VPNManager.isConfigured(manager) {
                    let proto = NETunnelProviderProtocol()
                    proto.providerBundleIdentifier = VPNManager.extBundleID
                    proto.serverAddress = ServerStore.shared.selected?.address ?? "VLESS"
                    proto.providerConfiguration = ["version": NSNumber(value: 1)]
                    manager.protocolConfiguration = proto
                    manager.localizedDescription = "VLESS"
                } else if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
                    proto.serverAddress = ServerStore.shared.selected?.address
                        ?? proto.serverAddress
                        ?? "VLESS"
                    manager.protocolConfiguration = proto
                }

                manager.isEnabled = true
                manager.saveToPreferences { saveError in
                    if let saveError = saveError {
                        completion(self.diagnosticError(saveError, stage: "manager.saveToPreferences"))
                        return
                    }

                    manager.loadFromPreferences { reloadError in
                        if let reloadError = reloadError {
                            completion(self.diagnosticError(reloadError, stage: "manager.reloadAfterSave"))
                            return
                        }

                        self.manager = manager
                        completion(nil)
                    }
                }
            }
        }
    }

    private static func isConfigured(_ manager: NETunnelProviderManager) -> Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
              proto.providerBundleIdentifier == extBundleID else {
            return false
        }

        return manager.localizedDescription == "VLESS"
    }

    func connect(completion: @escaping (Error?) -> Void) {
        prepare { [weak self] error in
            if let error = error {
                completion(error)
                return
            }

            guard let self = self, let session = self.session else {
                completion(NSError(
                    domain: "Vless",
                    code: 10,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Не удалось создать VPN-профиль",
                        "VPNDiagnosticStage": "session creation"
                    ]
                ))
                return
            }

            do {
                try session.startVPNTunnel()
                completion(nil)
            } catch {
                completion(self.diagnosticError(error, stage: "session.startVPNTunnel"))
            }
        }
    }

    func disconnect() {
        session?.stopVPNTunnel()
    }

    func reconnect(completion: @escaping (Error?) -> Void) {
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.connect(completion: completion)
        }
    }
}
