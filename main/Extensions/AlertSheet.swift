import UIKit

extension UIAlertController {
	func presentIn(_ viewController: UIViewController) {
		viewController.present(self, animated: true)
	}
}

// MARK: Basic Alerts

/// - Parameters:
///   - buttonText: Default: `"Dismiss"`
func Alert(title: String?, text: String?, buttonText: String = "Dismiss") -> UIAlertController {
	let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
	alert.addAction(UIAlertAction(title: buttonText, style: .cancel, handler: nil))
	return alert
}

/// - Parameters:
///   - buttonText: Default:`"Dismiss"`
func ErrorAlert(_ error: Error, buttonText: String = "Dismiss") -> UIAlertController {
	return Alert(title: "Error", text: error.localizedDescription, buttonText: buttonText)
}

/// - Parameters:
///   - buttonText: Default: `"Dismiss"`
func ErrorAlert(_ errorDescription: String, buttonText: String = "Dismiss") -> UIAlertController {
	return Alert(title: "Error", text: errorDescription, buttonText: buttonText)
}

/// - Parameters:
///   - buttonText: Default: `"Continue"`
///   - buttonStyle: Default: `.default`
func AskAlert(title: String?, text: String?, buttonText: String = "Continue", cancelButton: String = "Cancel", buttonStyle: UIAlertAction.Style = .default, action: @escaping (UIAlertController) -> Void) -> UIAlertController {
	let alert = Alert(title: title, text: text, buttonText: cancelButton)
	alert.addAction(UIAlertAction(title: buttonText, style: buttonStyle) { _ in action(alert) })
	return alert
}

/// Show alert hinting the user to go to system settings and re-enable notifications.
func NotificationsDisabledAlert(presentIn viewController: UIViewController) {
	AskAlert(title: "Notifications Disabled",
			 text: "Go to System Settings > Notifications > AppCheck to re-enable notifications.",
			 buttonText: "Open settings") { _ in
		URL(string: UIApplication.openSettingsURLString)?.open()
	}.presentIn(viewController)
}

// MARK: Alert with multiple options

/// - Parameters:
///   - buttons: Default: `[]`
///   - lastIsDestructive: Default: `false`
///   - cancelButtonText: Default: `"Dismiss"`
func BottomAlert(title: String?, text: String?, buttons: [String] = [], lastIsDestructive: Bool = false, cancelButtonText: String = "Cancel", callback: @escaping (_ index: Int?) -> Void) -> UIAlertController {
	let alert = UIAlertController(title: title, message: text, preferredStyle: .actionSheet)
	for (i, btn) in buttons.enumerated() {
		let dangerous = (lastIsDestructive && i + 1 == buttons.count)
		alert.addAction(UIAlertAction(title: btn, style: dangerous ? .destructive : .default) { _ in callback(i) })
	}
	alert.addAction(UIAlertAction(title: cancelButtonText, style: .cancel) { _ in callback(nil) })
	return alert
}

func AlertDeleteLogs(_ domain: String, latest: Timestamp, success: @escaping (_ tsMin: Timestamp) -> Void) -> UIAlertController {
	let minutesPassed = (Timestamp.now() - latest) / 60
	let times: [Int] = [5, 15, 60, 1440].compactMap { minutesPassed < $0 ? $0 : nil }
	let fmt = TimeFormat(.full, allowed: [.hour, .minute])
	let labels = times.map { "Last " + (fmt.from(minutes: $0) ?? "?") }
	return BottomAlert(title: "Delete logs", text: "Delete logs for domain '\(domain)'", buttons: labels + ["Delete everything"], lastIsDestructive: true) {
		if let i = $0 {
			success(i < times.count ? Timestamp.past(minutes: times[i]) : 0)
		}
	}
}
