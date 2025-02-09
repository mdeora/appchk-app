import NetworkExtension

let GlassVPN = GlassVPNManager()

enum VPNState : Int { case on = 1, inbetween, off }

final class GlassVPNManager {
	static let bundleIdentifier = "de.uni-bamberg.psi.AppCheck.VPN"
	private var managerVPN: NETunnelProviderManager?
	private(set) var state: VPNState = .off
	
	fileprivate init() {
#if IOS_SIMULATOR
		postProcessedVPNState(.on)
		SimulatorVPN.start()
#else
		NETunnelProviderManager.loadAllFromPreferences { managers, error in
			self.managerVPN = managers?.first {
				($0.protocolConfiguration as? NETunnelProviderProtocol)?
					.providerBundleIdentifier == GlassVPNManager.bundleIdentifier
			}
			guard let mgr = self.managerVPN else {
				self.postRawVPNState(.invalid)
				return
			}
			mgr.loadFromPreferences { _ in
				self.postRawVPNState(mgr.connection.status)
			}
		}
		NSNotification.Name.NEVPNStatusDidChange.observe(call: #selector(vpnStatusChanged(_:)), on: self)
#endif
		NotifyDNSFilterChanged.observe(call: #selector(didChangeDomainFilter), on: self)
	}
	
	func setEnabled(_ newState: Bool) {
#if IOS_SIMULATOR
		postProcessedVPNState(newState ? .on : .off)
		newState ? SimulatorVPN.start() : SimulatorVPN.stop()
#else
		guard let mgr = self.managerVPN else {
			self.createNewVPN { manager in
				self.managerVPN = manager
				self.setEnabled(newState)
			}
			return
		}
		let state = mgr.isEnabled && (mgr.connection.status == .connected)
		if state != newState {
			self.updateVPN({ mgr.isEnabled = true }) {
				newState ? try? mgr.connection.startVPNTunnel() : mgr.connection.stopVPNTunnel()
			}
		}
#endif
	}
	
	/// Notify VPN extension about changes
	/// - Returns: `true` on success, `false` if VPN is off or message could not be converted to `.utf8`
	@discardableResult func send(_ message: VPNAppMessage) -> Bool {
#if IOS_SIMULATOR
		if state == .on, let data = message.raw {
			SimulatorVPN.sendMsg(data)
			return true
		}
#else
		if let session = self.managerVPN?.connection as? NETunnelProviderSession,
			session.status == .connected, let data = message.raw {
			do {
				try session.sendProviderMessage(data, responseHandler: nil)
				return true
			} catch {}
		}
#endif
		return false
	}
	
	
	// MARK: - Notify callback
	
	@objc private func vpnStatusChanged(_ notification: Notification) {
		postRawVPNState((notification.object as? NETunnelProviderSession)?.status ?? .invalid)
	}
	
	@objc private func didChangeDomainFilter(_ notification: Notification) {
		send(.filterUpdate(domain: notification.object as? String))
	}
	
	
	// MARK: - Manage configuration
	
	private func createNewVPN(_ success: @escaping (_ manager: NETunnelProviderManager) -> Void) {
		let mgr = NETunnelProviderManager()
		mgr.localizedDescription = "AppCheck Monitor"
		let proto = NETunnelProviderProtocol()
		proto.providerBundleIdentifier = GlassVPNManager.bundleIdentifier
		proto.serverAddress = "127.0.0.1"
		mgr.protocolConfiguration = proto
		mgr.isEnabled = true
		mgr.saveToPreferences { error in
			guard error == nil else {
				self.postProcessedVPNState(.off)
				//ErrorAlert(error!).presentIn(self.window?.rootViewController)
				return
			}
			success(mgr)
		}
	}
	
	private func updateVPN(_ body: @escaping () -> Void, _ onSuccess: @escaping () -> Void) {
		self.managerVPN?.loadFromPreferences { error in
			guard error == nil else { return }
			body()
			self.managerVPN?.saveToPreferences { error in
				guard error == nil else { return }
				onSuccess()
			}
		}
	}
	
	
	// MARK: - Post Notifications
	
	private func postRawVPNState(_ origState: NEVPNStatus) {
		let state: VPNState
		switch origState {
		case .connected: 								state = .on
		case .connecting, .disconnecting, .reasserting: state = .inbetween
		case .invalid, .disconnected: fallthrough
		@unknown default: 								state = .off
		}
		postProcessedVPNState(state)
	}
	
	private func postProcessedVPNState(_ state: VPNState) {
		self.state = state
		NotifyVPNStateChanged.post()
	}
}


//  ---------------------------------------------------------------
// |
// |    MARK: - VPN message
// |
//  ---------------------------------------------------------------

struct VPNAppMessage {
	let raw: Data?
	init(_ string: String) { raw = string.data(using: .utf8) }
	
	static func filterUpdate(domain: String? = nil) -> Self {
		.init("filter-update:\(domain ?? "")")
	}
	static func autoDelete(after interval: Int) -> Self {
		.init("auto-delete:\(interval)")
	}
	/// Only used for connection alert notifications
	static func notificationSettingsChanged() -> Self {
		.init("notify-prefs-change:1")
	}
	/// Triggered whenever user taps on the start/stop recording button
	static func isRecording(_ state: CurrentRecordingState) -> Self {
		.init("recording-now:\(state.rawValue)")
	}
	/// Triggered whenever user taps on the switch in settings
	static func disconnectUnresolvable(_ state: Bool) -> Self {
		.init("disconnect-unresolvable:\(state ? 1 : 0)")
	}
	/// Triggered whenever user taps on the switch in settings
	static func disconnectSWCD(_ state: Bool) -> Self {
		.init("disconnect-swcd:\(state ? 1 : 0)")
	}
}
