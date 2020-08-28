import UIKit

class VCShareRecording : UIViewController {
	
	var record: Recording!
	private var jsonData: Data?
	
	@IBOutlet private var text : UITextView!
	@IBOutlet private var sendButton: UIBarButtonItem!
	@IBOutlet private var sendActivity : UIActivityIndicatorView!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		sendButton.isEnabled = !record.shared
		
		let start = record.start
		let comp = Calendar.current.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date(start))
		let wkYear = "\(comp.yearForWeekOfYear ?? 0).\(comp.weekOfYear ?? 0)"
		let lenSec = record.duration ?? 0
		
		let res = RecordingsDB.details(record)
		var cluster: [String : [Timestamp]] = [:]
		for (dom, ts) in res {
			if cluster[dom] == nil {
				cluster[dom] = []
			}
			cluster[dom]?.append(ts - start)
		}
		let domList = cluster.reduce("") {
			$0 + "\($1.key) : \($1.value.map{"\($0)"}.joined(separator: ", "))\n"
		}
		text.attributedText = NSMutableAttributedString()
			.h2("Review before sending\n")
			.normal("\nRead carefully. " +
				"You are about to upload the following information to our servers. " +
				"The data is anonymized in regards to device identifiers and time of recording. " +
				"It is however not anonymous to the domains requested during the recording." +
				"\n\n" +
				"If necessary, you can cancel this dialog and return to the recording overview. " +
				"Use swipe to delete individual domains." +
				"\n\n")
			.bold("Send to server:\n")
			.italic("\nDate: ", .callout).bold(wkYear, .callout)
			.italic("\nRec-Length: ", .callout).bold("\(lenSec) sec", .callout)
			.italic("\nApp-Bundle: ", .callout).bold(record.appId ?? "–", .callout)
			.italic("\nApp-Name: ", .callout).bold(record.title ?? "–", .callout)
			.italic("\n\n[domain name] : [relative time offsets]\n", .callout)
			.bold(domList, .callout)
		
		let json: [String : Any] = [
			"v" : 1,
			"date" : wkYear,
			"duration" : lenSec,
			"app-bundle" : record.appId ?? "",
			"app-name" : record.title ?? "",
			"logs" : cluster
			]
		jsonData = try? JSONSerialization.data(withJSONObject: json)
	}
	
	@IBAction private func closeView() {
		dismiss(animated: true)
	}
	
	@IBAction private func shareRecording(_ sender: UIBarButtonItem) {
		sender.isEnabled = false
		sendActivity.startAnimating()
		
		let url = URL(string: "http://127.0.0.1/api/v1/contribute/")!
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.httpBody = jsonData
		var rec = record!

		URLSession.shared.dataTask(with: request) { data, response, error in
			DispatchQueue.main.async { [weak self] in
				sender.isEnabled = true
				self?.sendActivity.stopAnimating()
				
				guard error == nil, let data = data,
					let response = response as? HTTPURLResponse else {
					self?.banner(.fail, "\(error?.localizedDescription ?? "Unkown error occurred")")
					return
				}
				let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
				let status = json?["status"] as? String
				let v = json?["v"] as? Int ?? 0
				guard v > 0, (200 ... 299) ~= response.statusCode else {
					QLog.Warning("Couldn't contribute: \(status ?? "unkown reason")")
					self?.banner(.fail, "Server couldn't parse request.\nTry again later.")
					return
				}
				// update db, mark record as shared
				sender.isEnabled = false
				rec.shared = true   // in case view was closed
				self?.record = rec  // in case view is still open
				RecordingsDB.update(rec) // rec cause self may not be available
				// notify user about results
				var autoHide = true
				if v == 1, let urlStr = json?["url"] as? String {
					let nextUpdateIn = json?["when"] as? Int
					self?.showOpenResultsAlert(urlStr, when: nextUpdateIn)
					autoHide = false
				}
				self?.banner(.ok, "Thank you for your contribution.",
							 autoHide ? { [weak self] in self?.closeView() } : nil)
			}
		}.resume()
	}
	
	private func banner(_ style: NotificationBanner.Style, _ msg: String, _ closure: (() -> Void)? = nil) {
		NotificationBanner(msg, style: style).present(in: self, onClose: closure)
	}
	
	private func showOpenResultsAlert(_ urlStr: String, when: Int?) {
		var msg = "Your contribution is being processed and will be available "
		if let when = when {
			if when < 61 {
				msg += "in approx. \(when) sec. "
			} else {
				let fmt = TimeFormat.from(Timestamp(when))
				msg += "in \(fmt) min. "
			}
		} else {
			msg += "shortly. "
		}
		msg += "Open results webpage now?"
		AskAlert(title: "Thank you", text: msg, buttonText: "Show results", cancelButton: "Not now") { _ in
			if let url = URL(string: urlStr) {
				UIApplication.shared.openURL(url)
			}
		}.presentIn(self)
	}
}