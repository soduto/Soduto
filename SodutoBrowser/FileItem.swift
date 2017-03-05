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
