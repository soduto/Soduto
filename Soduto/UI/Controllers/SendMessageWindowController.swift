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
    
    public var sendActionHandler: ((SendMessageWindowController) -> Void)? = nil
    
    public var phoneNumbers: [String] {
        guard let tokens = toInput.objectValue as? [Any] else { return [] }
        let numbers: [String] = tokens.map { token in
            if let contactPhoneNumber = token as? ContactPhoneNumber {
                return contactPhoneNumber.selectedPhone.value.stringValue
            }
            else if let tokenString = token as? String {
                return tokenString
            }
            else {
                return ""
            }
        }
        return numbers.filter({ !$0.isEmpty })
    }
    public var messageBody: String? { return self.bodyInput.string }
    public var isReadyToSend: Bool { return self.messageBody?.isEmpty == false && self.phoneNumbers.count > 0 }
    
    @IBOutlet weak var sendButton: NSButton!
    @IBOutlet weak var toInput: NSTokenField!
    @IBOutlet weak var bodyInput: NSTextView!
    @IBOutlet weak var bodyInputPlaceholder: NSTextField!
    
    fileprivate var isContactsAccessAllowed: Bool { return CNContactStore.authorizationStatus(for: .contacts) == .authorized }
    
    
    static func loadController() -> SendMessageWindowController {
        let controller = SendMessageWindowController(windowNibName: NSNib.Name(rawValue: "SendMessageWindow"))
        
        // make sure window is loaded
        let _ = controller.window
        
        return controller
    }
    
    
    public override func showWindow(_ sender: Any?) {
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            CNContactStore().requestAccess(for: .contacts) { _,_ in
                NSApp.activate(ignoringOtherApps: true)
                super.showWindow(sender)
            }
        }
        else {
            NSApp.activate(ignoringOtherApps: true)
            super.showWindow(sender)
        }
    }

    public override func windowDidLoad() {
        self.bodyInput.textContainerInset = NSSize(width: 15.0, height: 8.0)
        self.bodyInput.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))
        
        if let screenSize = NSScreen.main()?.frame.size, let windowSize = self.window?.frame.size {
            let pos = NSPoint(x: (screenSize.width - windowSize.width) * 0.5, y: (screenSize.height - windowSize.height) * 0.5)
            self.window?.setFrameOrigin(pos)
        }
    }
    
    public override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }
    
    public override func controlTextDidChange(_ notification: Notification) {
        guard let view = notification.object as? NSView else { return }
        
        // To input
        if view === self.toInput {
            self.sendButton.isEnabled = self.isReadyToSend
        }
    }
    
    public func clear() {
        self.toInput.stringValue = ""
        self.bodyInput.string = ""
        self.sendButton.isEnabled = isReadyToSend
        self.window?.makeFirstResponder(self.toInput)
    }
    
    
    // MARK: Actions
    
    @objc dynamic fileprivate func selectPhoneMenuAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }
        guard let contactPhoneNumber = menuItem.representedObject as? ContactPhoneNumber else { return }
        let phoneIndex = menuItem.tag
        guard phoneIndex < contactPhoneNumber.contact.phoneNumbers.count else { return }
        contactPhoneNumber.selectedPhone = contactPhoneNumber.contact.phoneNumbers[phoneIndex]
        
        guard let tokens = self.toInput.objectValue as? [Any] else { return }
        // To properly refresh NSTokenInput, we need to recreate the modified ContactPhoneNumber
        let updatedTokens: [Any] = tokens.map { token in
            if let phone = token as? ContactPhoneNumber, phone === contactPhoneNumber {
                return ContactPhoneNumber(contactPhoneNumber: phone)
            }
            else {
                return token
            }
        }
        self.toInput.objectValue = updatedTokens
    }
    
    @IBAction func send(_ sender: Any) {
        guard self.isReadyToSend else { return }
        self.sendActionHandler?(self)
    }
}


// MARK: NSTextDelegate

extension SendMessageWindowController: NSTextDelegate {
    
    public func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? NSView else { return }
        
        // Message body
        if view === self.bodyInput {
            self.bodyInputPlaceholder.isHidden = self.bodyInput.string?.isEmpty != true
            self.sendButton.isEnabled = self.isReadyToSend
        }
        
    }
}


// MARK: NSTokenFieldDelegate

extension SendMessageWindowController: NSTokenFieldDelegate {
    
    // Each element in the array should be an NSString or an array of NSStrings.
    // substring is the partial string that is being completed.  tokenIndex is the index of the token being completed.
    // selectedIndex allows you to return by reference an index specifying which of the completions should be selected initially.
    // The default behavior is not to have any completions.
    func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
        
        guard self.isContactsAccessAllowed else { return nil }
        
        let matches = ContactPhoneNumber.queryList(withString: substring)
        let suggestions = matches.map { contactPhoneNumber -> String in
            return contactPhoneNumber.canonicalString
        }
        
        selectedIndex?.pointee = -1
        return suggestions
    }
    
    
    // return an array of represented objects you want to add.
    // If you want to reject the add, return an empty array.
    // returning nil will cause an error.
    func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
        return tokens
    }
    
    
    // If you return nil or don't implement these delegate methods, we will assume
    // editing string = display string = represented object
    func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
        if let contactPhoneNumber = representedObject as? ContactPhoneNumber {
            return contactPhoneNumber.displayString
        }
        else if let string = representedObject as? String {
            return string
        }
        else {
            return nil
        }
    }
    
    func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
        if let contactPhoneNumber = representedObject as? ContactPhoneNumber {
            return contactPhoneNumber.editingString
        }
        else if let string = representedObject as? String {
            return string
        }
        else {
            return nil
        }
    }
    
    func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any {
        if self.isContactsAccessAllowed, let contactPhoneNumber = ContactPhoneNumber(string: editingString) {
            return contactPhoneNumber
        }
        else {
            return editingString
        }
    }
    
    
    // We put the string on the pasteboard before calling this delegate method.
    // By default, we write the NSStringPboardType as well as an array of NSStrings.
    func tokenField(_ tokenField: NSTokenField, writeRepresentedObjects objects: [Any], to pboard: NSPasteboard) -> Bool {
        pboard.clearContents()
        for obj in objects {
            guard let writableObj = obj as? NSPasteboardWriting else { break }
            pboard.writeObjects([writableObj])
        }
        return true
    }
    
    
    // Return an array of represented objects to add to the token field.
    func tokenField(_ tokenField: NSTokenField, readFrom pboard: NSPasteboard) -> [Any]? {
        let classes: [AnyClass]
        if self.isContactsAccessAllowed {
            classes = [ContactPhoneNumber.self, NSString.self]
        }
        else {
            classes = [NSString.self]
        }
        return pboard.readObjects(forClasses: classes, options: nil)
    }
    
    
    // By default the tokens have no menu.
    func tokenField(_ tokenField: NSTokenField, menuForRepresentedObject representedObject: Any) -> NSMenu? {
        guard let contactPhoneNumber = representedObject as? ContactPhoneNumber else { return nil }
        
        let menu = NSMenu()
        for phoneNumber in contactPhoneNumber.contact.phoneNumbers {
            let index = menu.items.count
            let title = contactPhoneNumber.displayString(forPhone: phoneNumber)
            let key = index < 10 ? "\((index + 1) % 10)" : ""
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: key)
            item.tag = index
            item.representedObject = contactPhoneNumber
            item.target = self
            item.action = #selector(selectPhoneMenuAction(_:))
            item.state = contactPhoneNumber.selectedPhone === phoneNumber ? NSControl.StateValue.onState : NSControl.StateValue.offState
            menu.addItem(item)
        }
        return menu
    }
    
    func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
        guard let contactPhoneNumber = representedObject as? ContactPhoneNumber else { return false }
        return contactPhoneNumber.contact.phoneNumbers.count > 1
    }
    
    
    // This method allows you to change the style for individual tokens as well as have mixed text and tokens.
//    func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenStyle {}
    
}


// MARK: - 

/// Represents a phone number from contacts
final class ContactPhoneNumber: NSObject {
    
    // MARK: Properties
    
    fileprivate static let delimiter = " — "
    fileprivate static let pboardType = NSPasteboard.PasteboardType(rawValue: "com.soduto.contactphonenumber")
    
    let contact: CNContact
    var selectedPhone: CNLabeledValue<CNPhoneNumber> {
        didSet {
            _displayString = nil
        }
    }
    
    private var _displayString: String? = nil
    var displayString: String {
        if self._displayString == nil {
            if let fullName = CNContactFormatter.string(from: self.contact, style: .fullName) {
                if self.contact.phoneNumbers.count > 1, let label = self.selectedPhone.label {
                    let localizedLabel = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: label)
                    self._displayString = "\(fullName) (\(localizedLabel))"
                }
                else {
                    self._displayString = fullName
                }
            }
            else {
                self._displayString = self.phoneDisplayString
            }
        }
        return self._displayString!
    }
    var phoneDisplayString: String {
        return displayString(forPhone: self.selectedPhone)
    }
    var editingString: String {
        return self.selectedPhone.value.stringValue
    }
    var canonicalString: String {
        let phoneNumber = self.selectedPhone.value.stringValue
        if let fullName =  CNContactFormatter.string(from: self.contact, style: .fullName) {
            return "\(fullName)\(ContactPhoneNumber.delimiter)\(phoneNumber)"
        }
        else {
            return phoneNumber
        }
    }
    
    
    // MARK: Init / Deinit
    
    init(contactPhoneNumber: ContactPhoneNumber) {
        self.contact = contactPhoneNumber.contact
        self.selectedPhone = contactPhoneNumber.selectedPhone
    }
    
    init?(contact: CNContact) {
        guard contact.phoneNumbers.count > 0 else { return nil }
        self.contact = contact
        self.selectedPhone = contact.phoneNumbers[0]
    }
    
    required init?(string: String) {
        let components = string.components(separatedBy: ContactPhoneNumber.delimiter)
        guard components.count >= 2 else { return nil }
        let phoneNumber = components.last!
        let fullName = components.prefix(upTo: components.count-1).joined(separator: ContactPhoneNumber.delimiter)
        
        let keysToFetch: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                              CNContactPhoneNumbersKey as CNKeyDescriptor,
                                              CNContactThumbnailImageDataKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.unifyResults = true
        
        var contactMatch: CNContact? = nil
        var phoneMatch: CNLabeledValue<CNPhoneNumber>? = nil
        do {
            try CNContactStore().enumerateContacts(with: request, usingBlock: { (contact: CNContact, result: UnsafeMutablePointer<ObjCBool>) in
                guard contact.phoneNumbers.count > 0 else { return }
                guard let contactFullName = CNContactFormatter.string(from: contact, style: .fullName) else { return }
                guard contactFullName == fullName else { return }
                guard let phoneIndex = contact.phoneNumbers.index(where: { (number: CNLabeledValue) -> Bool in
                    return number.value.stringValue == phoneNumber
                }) else { return }
                contactMatch = contact
                phoneMatch = contact.phoneNumbers[phoneIndex]
                result.pointee = true
            })
        }
        catch {
            Log.error?.message("Failed to fetch contacts: \(error)")
            return nil
        }
        
        guard let matchedContact = contactMatch else { return nil }
        guard let matchedPhone = phoneMatch else { return nil }
        
        self.contact = matchedContact
        self.selectedPhone = matchedPhone
    }
    
    
    // MARK: Public methods
    
    func displayString(forPhone phoneNumber: CNLabeledValue<CNPhoneNumber>) -> String {
        if self.contact.phoneNumbers.count > 1, let label = phoneNumber.label {
            let localizedLabel = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: label)
            return "\(phoneNumber.value.stringValue) (\(localizedLabel))"
        }
        else {
            return phoneNumber.value.stringValue
        }
    }
}


// MARK: NSPasteboardReading

extension ContactPhoneNumber: NSPasteboardReading {
    
    static func readableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return [ContactPhoneNumber.pboardType]
    }
    
    static func readingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.ReadingOptions {
        return NSPasteboard.ReadingOptions.asString
    }
    
    convenience init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        guard type == ContactPhoneNumber.pboardType else { return nil }
        guard let str = propertyList as? String else { return nil }
        self.init(string: str)
    }
    
}


// MARK: NSPasteboardWriting

extension ContactPhoneNumber: NSPasteboardWriting {
    
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return [
            ContactPhoneNumber.pboardType,
            NSPasteboard.PasteboardType(rawValue: kUTTypeText as String) ]
    }
    
    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == ContactPhoneNumber.pboardType {
            return self.canonicalString
        }
        else if type.rawValue == kUTTypeText as String {
            return self.canonicalString
        }
        else {
            return nil
        }
    }
    
}


// MARK: CNContacts querying

extension ContactPhoneNumber {
    
    fileprivate static func queryList(withString string: String) -> [ContactPhoneNumber] {
        let string = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return [] }
        
        var results: [ContactPhoneNumber] = []
        do {
            let keysToFetch: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                                  CNContactPhoneNumbersKey as CNKeyDescriptor,
                                                  CNContactThumbnailImageDataKey as CNKeyDescriptor]
            let store = CNContactStore()
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            request.unifyResults = true
            try store.enumerateContacts(with: request, usingBlock: { (contact: CNContact, result: UnsafeMutablePointer<ObjCBool>) in
                guard contact.phoneNumbers.count > 0 else { return }
                guard let fullName = CNContactFormatter.string(from: contact, style: .fullName) else { return }
                guard fullName.localizedCaseInsensitiveContains(string) else { return }
                guard let contactPhoneNumber = ContactPhoneNumber(contact: contact) else { return }
                results.append(contactPhoneNumber)
            })
        }
        catch {
            Log.error?.message("Failed to fetch contacts: \(error)")
        }
        
        results.sort { (c1, c2) in c1.displayString.compare(c2.displayString) == .orderedAscending }
        
        return results
    }
    
}
