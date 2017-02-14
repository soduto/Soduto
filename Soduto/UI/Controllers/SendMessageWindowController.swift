//
//  SendMessageWindowController.swift
//  Soduto
//
//  Created by Giedrius on 2017-01-28.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa
import Contacts
import CleanroomLogger

class SendMessageWindowController: NSWindowController {
    
    // MARK: Properties
    
    @IBOutlet weak var toInput: NSComboBox!
    @IBOutlet weak var bodyInput: NSTextView!
    @IBOutlet weak var bodyInputPlaceholder: NSTextField!
    
    fileprivate var filteredContacts: [CNContact] = []
    
    
    static func loadController() -> SendMessageWindowController {
        return SendMessageWindowController(windowNibName: "SendMessageWindow")
    }
    
    override public func showWindow(_ sender: Any?) {
        // make sure window is loaded
        let _ = self.window
        
        NSApp.activate(ignoringOtherApps: true)
        
        super.showWindow(sender)
    }

    
    override public func windowDidLoad() {
        self.bodyInput.textContainerInset = NSSize(width: 15.0, height: 8.0)
        self.bodyInput.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))
    }
    
    public override func controlTextDidChange(_ notification: Notification) {
        guard let obj = notification.object else { return }
        if (obj as? NSComboBox) === self.toInput {
            self.filterContacts(self.toInput.stringValue)
            self.toInput.cell?.setAccessibilityExpanded(!self.toInput.stringValue.isEmpty)
        }
    }
    
    
    fileprivate func filterContacts(_ searchString: String) {
        if !searchString.isEmpty {
            do {
                let keysToFetch: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                   CNContactPhoneNumbersKey as CNKeyDescriptor,
                                   CNContactImageDataAvailableKey as CNKeyDescriptor,
                                   CNContactThumbnailImageDataKey as CNKeyDescriptor]
                let store = CNContactStore()
                let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                request.unifyResults = true
                var results: [CNContact] = []
                try store.enumerateContacts(with: request, usingBlock: { (contact: CNContact, result: UnsafeMutablePointer<ObjCBool>) in
                    guard contact.phoneNumbers.count > 0 else { return }
                    guard let fullName = CNContactFormatter.string(from: contact, style: .fullName) else { return }
                    guard fullName.localizedCaseInsensitiveContains(searchString) else { return }
                    results.append(contact)
                })
                self.filteredContacts = results
            }
            catch {
                Log.error?.message("Failed to fetch contacts: \(error)")
            }
        }
        else {
            self.filteredContacts = []
        }
        
        self.toInput.reloadData()
    }
}


// MARK: - NSTextDelegate

extension SendMessageWindowController: NSTextDelegate {
    
    public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        guard textView == self.bodyInput else { return }
        
        self.bodyInputPlaceholder.isHidden = self.bodyInput.string?.isEmpty != true
    }
}


// MARK: - NSComboBoxDataSource

extension SendMessageWindowController: NSComboBoxDataSource {
    
    public func numberOfItems(in comboBox: NSComboBox) -> Int {
        return self.filteredContacts.count
    }
    
    public func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        let contact = self.filteredContacts[index]
        assert(contact.isKeyAvailable(CNContactPhoneNumbersKey))
        assert(contact.phoneNumbers.count > 0)
        let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let phoneNumber = contact.phoneNumbers[0]
        let phoneNumberString = phoneNumber.value.stringValue
        return "\(phoneNumberString) - \(fullName)"
    }
    
    
//    public func comboBox(_ comboBox: NSComboBox, indexOfItemWithStringValue string: String) -> Int { return 0 }
    
//    public func comboBox(_ comboBox: NSComboBox, completedString string: String) -> String? { return nil }
    
}


// MARK: - NSComboBoxDelegate

extension SendMessageWindowController: NSComboBoxDelegate {
    
    public func comboBoxWillPopUp(_ notification: Notification) {
        guard let obj = notification.object else { return }
        if (obj as? NSComboBox) === self.toInput {
            self.filterContacts(self.toInput.stringValue)
        }
    }
    
}
