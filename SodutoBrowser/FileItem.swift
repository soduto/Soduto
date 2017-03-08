//
//  FileItem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import AppKit

class FileItem: NSObject {
    
    let url: URL
    let name: String
    let icon: NSImage
    let isDirectory: Bool
    
    init(url: URL, name: String, icon: NSImage, isDirectory: Bool) {
        self.url = url
        self.name = name
        self.icon = icon
        self.isDirectory = isDirectory
    }
    
}

extension FileItem: NSPasteboardWriting {
    
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
    
}
