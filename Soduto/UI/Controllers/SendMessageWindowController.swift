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
    
    @IBOutlet weak var toInput: NSTokenField!
    @IBOutlet weak var bodyInput: NSTextView!
    @IBOutlet weak var bodyInputPlaceholder: NSTextField!
    
    fileprivate var filteredContacts: [CNContact] = []
    fileprivate var isConatctsAccessAllowed: Bool = false
    
    
    static func loadController() -> SendMessageWindowController {
        return SendMessageWindowController(windowNibName: "SendMessageWindow")
    }
    
    
    public override func showWindow(_ sender: Any?) {
        // make sure window is loaded
        let _ = self.window
        
        NSApp.activate(ignoringOtherApps: true)
        
        super.showWindow(sender)
    }

    public override func windowDidLoad() {
        self.bodyInput.textContainerInset = NSSize(width: 15.0, height: 8.0)
        self.bodyInput.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))
    }
    
    public override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }
    
    
    fileprivate func filterContacts(_ searchString: String) -> [CNContact] {
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
        
        return self.filteredContacts
    }
    
    
    // MARK: Actions
    
    dynamic fileprivate func selectPhoneMenuAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }
        guard let addressee = menuItem.representedObject as? Addressee else { return }
        let phoneIndex = menuItem.tag
        guard phoneIndex < addressee.contact.phoneNumbers.count else { return }
        addressee.selectedPhone = addressee.contact.phoneNumbers[phoneIndex]
        
        guard let tokens = self.toInput.objectValue as? [Any] else { return }
        // To properly refresh NSTokenInput, we need to recreate the modified Addressee
        let updatedTokens: [Any] = tokens.map { token in
            if let addr = token as? Addressee, addr === addressee {
                return Addressee(addressee: addr)
            }
            else {
                return token
            }
        }
        self.toInput.objectValue = updatedTokens
    }
}


// MARK: NSTextDelegate

extension SendMessageWindowController: NSTextDelegate {
    
    public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        guard textView == self.bodyInput else { return }
        
        self.bodyInputPlaceholder.isHidden = self.bodyInput.string?.isEmpty != true
    }
}


// MARK: NSTokenFieldDelegate

extension SendMessageWindowController: NSTokenFieldDelegate {
    
    // Each element in the array should be an NSString or an array of NSStrings.
    // substring is the partial string that is being completed.  tokenIndex is the index of the token being completed.
    // selectedIndex allows you to return by reference an index specifying which of the completions should be selected initially.
    // The default behavior is not to have any completions.
    func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
        
        let matchingContacts = self.filterContacts(substring)
        let suggestions = matchingContacts.map { contact -> String in
            return Addressee(contact: contact)?.canonicalString ?? ""
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
        if let addressee = representedObject as? Addressee {
            return addressee.displayString
        }
        else if let string = representedObject as? String {
            return string
        }
        else {
            return nil
        }
    }
    
    func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
        if let addressee = representedObject as? Addressee {
            return addressee.editingString
        }
        else if let string = representedObject as? String {
            return string
        }
        else {
            return nil
        }
    }
    
    func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any {
        if let addressee = Addressee(string: editingString) {
            return addressee
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
        return pboard.readObjects(forClasses: [Addressee.self, NSString.self], options: nil)
    }
    
    
    // By default the tokens have no menu.
    func tokenField(_ tokenField: NSTokenField, menuForRepresentedObject representedObject: Any) -> NSMenu? {
        guard let addressee = representedObject as? Addressee else { return nil }
        
        let menu = NSMenu()
        for phoneNumber in addressee.contact.phoneNumbers {
            let index = menu.items.count
            let title = addressee.displayString(forPhone: phoneNumber)
            let key = index < 10 ? "\((index + 1) % 10)" : ""
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: key)
            item.tag = index
            item.representedObject = addressee
            item.target = self
            item.action = #selector(selectPhoneMenuAction(_:))
            item.state = addressee.selectedPhone === phoneNumber ? NSOnState : NSOffState
            menu.addItem(item)
        }
        return menu
    }
    
    func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
        guard let addressee = representedObject as? Addressee else { return false }
        return addressee.contact.phoneNumbers.count > 1
    }
    
    
    // This method allows you to change the style for individual tokens as well as have mixed text and tokens.
//    func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenStyle {}
    
}


// MARK: - 

final class Addressee: NSObject {
    
    // MARK: Properties
    
    fileprivate static let delimiter = " — "
    fileprivate static let pboardType = "com.soduto.contactphone"
    
    let contact: CNContact
    var selectedPhone: CNLabeledValue<CNPhoneNumber>
    
    var displayString: String {
        if let fullName = CNContactFormatter.string(from: self.contact, style: .fullName) {
            if contact.phoneNumbers.count > 1, let label = self.selectedPhone.label {
                let localizedLabel = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: label)
                return "\(fullName) (\(localizedLabel))"
            }
            else {
                return fullName
            }
        }
        else {
            return phoneDisplayString
        }
    }
    var phoneDisplayString: String {
        return displayString(forPhone: self.selectedPhone)
    }
    var editingString: String {
        return selectedPhone.value.stringValue
    }
    var canonicalString: String {
        let phoneNumber = selectedPhone.value.stringValue
        if let fullName =  CNContactFormatter.string(from: contact, style: .fullName) {
            return "\(fullName)\(Addressee.delimiter)\(phoneNumber)"
        }
        else {
            return phoneNumber
        }
    }
    
    
    // MARK: Init / Deinit
    
    init(addressee: Addressee) {
        self.contact = addressee.contact
        self.selectedPhone = addressee.selectedPhone
    }
    
    init?(contact: CNContact) {
        guard contact.phoneNumbers.count > 0 else { return nil }
        self.contact = contact
        self.selectedPhone = contact.phoneNumbers[0]
    }
    
    required init?(string: String) {
        let components = string.components(separatedBy: Addressee.delimiter)
        guard components.count >= 2 else { return nil }
        let phoneNumber = components.last!
        let fullName = components.prefix(upTo: components.count-1).joined(separator: Addressee.delimiter)
        
        let keysToFetch: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                              CNContactPhoneNumbersKey as CNKeyDescriptor,
                                              CNContactImageDataAvailableKey as CNKeyDescriptor,
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
        
        contact = matchedContact
        selectedPhone = matchedPhone
    }
    
    
    // MARK: Public methods
    
    func displayString(forPhone phoneNumber: CNLabeledValue<CNPhoneNumber>) -> String {
        if contact.phoneNumbers.count > 1, let label = phoneNumber.label {
            let localizedLabel = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: label)
            return "\(phoneNumber.value.stringValue) (\(localizedLabel))"
        }
        else {
            return phoneNumber.value.stringValue
        }
    }
}


// MARK: NSPasteboardReading

extension Addressee: NSPasteboardReading {
    
    static func readableTypes(for pasteboard: NSPasteboard) -> [String] {
        return [Addressee.pboardType]
    }
    
    static func readingOptions(forType type: String, pasteboard: NSPasteboard) -> NSPasteboardReadingOptions {
        return NSPasteboardReadingOptions.asString
    }
    
    convenience init?(pasteboardPropertyList propertyList: Any, ofType type: String) {
        guard type == Addressee.pboardType else { return nil }
        guard let str = propertyList as? String else { return nil }
        self.init(string: str)
    }
    
}


// MARK: NSPasteboardWriting

extension Addressee: NSPasteboardWriting {
    
    func writableTypes(for pasteboard: NSPasteboard) -> [String] {
        return [Addressee.pboardType, kUTTypeText as String]
    }
    
    func pasteboardPropertyList(forType type: String) -> Any? {
        if type == Addressee.pboardType {
            return canonicalString
        }
        else if type == kUTTypeText as String {
            return canonicalString
        }
        else {
            return nil
        }
    }
    
}
