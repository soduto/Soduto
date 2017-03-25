//
//  FileItem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import AppKit
import CleanroomLogger

class FileItem: NSObject, NSPasteboardReading, NSPasteboardWriting {
    
    public struct Flags: OptionSet {
        let rawValue: Int
        
        static let isDirectory = Flags(rawValue: 1 << 0)
        static let isHidden = Flags(rawValue: 1 << 1)
        static let isReadable = Flags(rawValue: 1 << 2)
        static let isWritable = Flags(rawValue: 1 << 3)
        static let isBusy = Flags(rawValue: 1 << 4)    // Indicates, that there is pending operation on the item
        static let isDeleted = Flags(rawValue: 1 << 5) // Indicates that item is already deleted and this is just a placeholder
    }

    
    let url: URL
    let name: String
    let icon: NSImage
    let staticFlags: Flags
    var dynamicFlags: Flags = []
    
    var flags: Flags { return self.staticFlags.union(self.dynamicFlags) }
    var isDirectory: Bool { return self.flags.contains(.isDirectory) }
    var isHidden: Bool { return self.flags.contains(.isHidden) }
    var canModify: Bool { return self.flags.contains(.isWritable) && !self.flags.contains(.isBusy) }
    
    init(url: URL, name: String, icon: NSImage, flags: Flags) {
        self.url = url
        self.name = name
        self.icon = icon
        self.staticFlags = flags
    }
    
    convenience init(url: URL) {
        if url.isFileURL {
            let icon = NSWorkspace.shared().icon(forFile: url.path)
            do {
                let resourceValues = try url.resourceValues(forKeys: [URLResourceKey.isHiddenKey, URLResourceKey.localizedNameKey, URLResourceKey.isDirectoryKey])
                let name = resourceValues.localizedName ?? url.lastPathComponent
                var flags: Flags = []
                if resourceValues.isDirectory == true { flags.insert(.isDirectory) }
                if resourceValues.isHidden == true { flags.insert(.isHidden) }
                self.init(url: url, name: name, icon: icon, flags: flags)
            }
            catch {
                Log.error?.message("Failed retrieving file resource information for url [\(url)]: \(error)")
                let name = url.lastPathComponent
                var flags: Flags = []
                if url.hasDirectoryPath { flags.insert(.isDirectory) }
                if url.lastPathComponent.hasPrefix(".") { flags.insert(.isHidden) }
                self.init(url: url, name: name, icon: icon, flags: flags)
            }
        }
        else {
            let name = url.lastPathComponent
            var flags: Flags = []
            if url.hasDirectoryPath { flags.insert(.isDirectory) }
            if url.lastPathComponent.hasPrefix(".") { flags.insert(.isHidden) }
            let fileType: String = flags.contains(.isDirectory) ? String(kUTTypeDirectory) : url.pathExtension
            let icon = NSWorkspace.shared().icon(forFileType: fileType)
            self.init(url: url, name: name, icon: icon, flags: flags)

        }
    }

    
    // MARK: NSPasteboardWriting
    
    public func writableTypes(for pasteboard: NSPasteboard) -> [String] {
        if self.url.isFileURL {
            if self.isDirectory {
                return [ kUTTypeDirectory as String, kUTTypeFileURL as String, kUTTypeURL as String ]
            }
            else {
                return [ kUTTypeFileURL as String, kUTTypeURL as String ]
            }
        }
        else {
            return [ kUTTypeURL as String ]
        }
    }
    
    public func pasteboardPropertyList(forType type: String) -> Any? {
        switch type {
        case String(kUTTypeDirectory):
            guard self.url.isFileURL && self.isDirectory else { return nil }
            return self.url.path
        case String(kUTTypeFileURL):
            guard self.url.isFileURL else { return nil }
            return (self.url as NSURL).pasteboardPropertyList(forType: type)
        case String(kUTTypeURL):
            return (self.url as NSURL).pasteboardPropertyList(forType: type)
        default:
            return nil
        }
    }
    

    // MARK: NSPasteboardReading
    
    public static func readableTypes(for pasteboard: NSPasteboard) -> [String] {
        return [ kUTTypeURL as String ]
    }
    
    public static func readingOptions(forType type: String, pasteboard: NSPasteboard) -> NSPasteboardReadingOptions {
        switch type {
        case String(kUTTypeURL): return .asString
        default:
            return .asData
        }
    }
    
    public required convenience init?(pasteboardPropertyList propertyList: Any, ofType type: String) {
        switch type {
        
        case String(kUTTypeURL):
            guard let url = NSURL(pasteboardPropertyList: propertyList, ofType: type) as? URL else { return nil }
            self.init(url: url)
            
        default: return nil
            
        }
    }
    
}
