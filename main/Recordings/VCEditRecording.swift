import UIKit

class VCEditRecording: UIViewController, UITextFieldDelegate, UITextViewDelegate {
	var record: Recording!
	var deleteOnCancel: Bool = false
	
	@IBOutlet private var buttonCancel: UIBarButtonItem!
	@IBOutlet private var buttonSave: UIBarButtonItem!
	@IBOutlet private var inputTitle: UITextField!
	@IBOutlet private var inputNotes: UITextView!
	@IBOutlet private var inputDetails: UITextView!
	@IBOutlet private var noteBottom: NSLayoutConstraint!
	
	override func viewDidLoad() {
		inputTitle.placeholder = record.fallbackTitle
		inputTitle.text = record.title
		inputNotes.text = record.notes
		inputDetails.text = """
			Start:		\(record.start.asDateTime())
			End:		\(record.stop?.asDateTime() ?? "?")
			Duration:	\(record.durationString ?? "?")
			"""
		validateSaveButton()
		if deleteOnCancel { // mark as destructive
			buttonCancel.tintColor = .systemRed
		}
		UIResponder.keyboardWillShowNotification.observe(call: #selector(keyboardWillShow), on: self)
		UIResponder.keyboardWillHideNotification.observe(call: #selector(keyboardWillHide), on: self)
	}
	
	
	// MARK: Save & Cancel Buttons
	
	@IBAction func didTapSave(_ sender: UIBarButtonItem) {
		if deleteOnCancel { // aka newly created
			// if remains true, `viewDidDisappear` will delete the record
			deleteOnCancel = false
			// TODO: copy db entries in new table for editing
		}
		QLog.Debug("updating record \(record.start)")
		record.title = (inputTitle.text == "") ? nil : inputTitle.text
		record.notes = (inputNotes.text == "") ? nil : inputNotes.text
		dismiss(animated: true) {
			DBWrp.recordingUpdate(self.record)
		}
	}
	
	@IBAction func didTapCancel(_ sender: UIBarButtonItem) {
		QLog.Debug("discard edit of record \(record.start)")
		dismiss(animated: true)
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		if deleteOnCancel {
			QLog.Debug("deleting record \(record.start)")
			DBWrp.recordingDelete(record)
			deleteOnCancel = false
		}
	}
	
	
	// MARK: Handle Keyboard & Notes Frame
	
	private var isEditingNotes: Bool = false
	private var keyboardHeight: CGFloat = 0
	
	@IBAction func hideKeyboard() { view.endEditing(false) }
	
	func textViewDidBeginEditing(_ textView: UITextView) {
		if textView == inputNotes {
			isEditingNotes = true
			updateKeyboard()
		}
	}
	
	func textViewDidEndEditing(_ textView: UITextView) {
		if textView == inputNotes {
			isEditingNotes = false
			updateKeyboard()
		}
	}
	
	@objc func keyboardWillShow(_ notification: NSNotification) {
		keyboardHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height ?? 0
		updateKeyboard()
	}
	
	@objc func keyboardWillHide(_ notification: NSNotification) {
		keyboardHeight = 0
		updateKeyboard()
	}
	
	private func updateKeyboard() {
		guard let parent = inputNotes.superview, let stack = parent.superview else {
			return
		}
		let adjust = (isEditingNotes && keyboardHeight > 0)
		stack.subviews.forEach{ $0.isHidden = (adjust && $0 != parent) }
		
		let title = parent.subviews.first as! UILabel
		title.font = .preferredFont(forTextStyle: adjust ? .subheadline : .title2)
		title.sizeToFit()
		title.frame.size.width = parent.frame.width
		
		noteBottom.constant = adjust ? view.frame.height - stack.frame.maxY - keyboardHeight : 0
	}
	
	
	// MARK: TextField & TextView Delegate
	
	func textFieldDidChangeSelection(_ _: UITextField) { validateSaveButton() }
	func textViewDidChange(_ _: UITextView) { validateSaveButton() }
	
	private func validateSaveButton() {
		let changed = (inputTitle.text != record.title ?? "" || inputNotes.text != record.notes ?? "")
		buttonSave.isEnabled = changed || deleteOnCancel // always allow save for new recordings
	}
	
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		textField == inputTitle ? inputNotes.becomeFirstResponder() : true
	}
}