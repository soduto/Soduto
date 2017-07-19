//
//  File.swift
//  Soduto
//
//  Created by Giedrius on 2017-07-18.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

extension NSPasteboard {
    public typealias PasteboardType = String
    public typealias ReadingOptions = NSPasteboardReadingOptions
}

extension NSCollectionViewItem {
    public typealias HighlightState = NSCollectionViewItemHighlightState
}

extension NSCollectionView {
    public typealias DropOperation = NSCollectionViewDropOperation
}

extension String {
    public var rawValue: String { return self }
    public init(rawValue: String) { self.init(rawValue)! }
}

extension NSNib {
    public typealias Name = String
}

extension NSSound {
    public static func beep() { NSBeep() }
}

extension NSTextCheckingResult {
    public func range(at index: Int) -> NSRange {
        return rangeAt(index)
    }
}

extension NSWindow {
    public typealias FrameAutosaveName = String
    public typealias StyleMask = NSWindowStyleMask
    public typealias BackingStoreType = NSBackingStoreType
    public typealias OrderingMode = NSWindowOrderingMode
    
    public static let didBecomeKeyNotification = Notification.Name.NSWindowDidBecomeKey
    public static let didResignKeyNotification = Notification.Name.NSWindowDidResignKey
    public static let willCloseNotification = Notification.Name.NSWindowWillClose
}

public typealias NSUserInterfaceItemIdentifier = String

extension NSImage {
    public struct Name {
        public static let network = NSImageNameNetwork
        public static let folder = NSImageNameFolder
    }
}

extension NSControl {
    public struct StateValue {
        public static let onState = NSOnState
        public static let offState = NSOffState
    }
}

extension NSEvent {
    public struct EventType {
        public static let keyDown: NSEventType = .keyDown
    }
}

extension NSRect {
    public func fill() { NSRectFill(self) }
}

public typealias NSAttributedStringKey = String
extension NSAttributedStringKey {
    public static let font: String = NSFontAttributeName
    public static let paragraphStyle: String = NSParagraphStyleAttributeName
    public static let link: String = NSLinkAttributeName
    public static let foregroundColor: String = NSForegroundColorAttributeName
}

extension NSRange {
    public func contains(_ loc: Int) -> Bool {
        return NSLocationInRange(loc, self)
    }
}

extension NSStoryboard {
    public typealias Name = String
}

extension NSStatusItem {
    public static var squareLength: CGFloat { return NSSquareStatusItemLength }
}

extension NSWorkspace {
    public typealias LaunchOptions = NSWorkspaceLaunchOptions
}

extension NSApplication {
    public static let didBecomeActiveNotification = Notification.Name.NSApplicationDidBecomeActive
    public static let didResignActiveNotification = Notification.Name.NSApplicationDidResignActive
    
    public struct ModalResponse {
        public static let OK = NSModalResponseOK
    }
}
