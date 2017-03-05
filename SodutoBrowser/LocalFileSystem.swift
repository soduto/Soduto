//
//  LocalFileSystem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import AppKit

class LocalFileSystem: FileSystem {
    
    let name: String = NSLocalizedString("Local", comment: "File system name")
    let rootUrl: URL = URL(fileURLWithPath: "/")
    let places: [Place] = [
        Place(name: "Home", url: FileManager.default.homeDirectoryForCurrentUser)
    ]
    
    func load(_ url: URL, completionHandler: @escaping (([FileItem]?, Error?) -> Void)) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var content: [FileItem] = []
                let fileURLs: [URL] = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
                for element in fileURLs {
                    let elementIcon = NSWorkspace.shared().icon(forFile: element.path)
                    
                    // only allow visible objects
                    let resourceValues = try element.resourceValues(forKeys: [URLResourceKey.isHiddenKey, URLResourceKey.localizedNameKey, URLResourceKey.isDirectoryKey])
                    guard resourceValues.isHidden == false else { continue }
                    let name = resourceValues.localizedName ?? url.lastPathComponent
                    let isDirectory = resourceValues.isDirectory ?? false
                    let item = FileItem(url: element, name: name, icon: elementIcon, isDirectory: isDirectory)
                    content.append(item)
                }
                
                DispatchQueue.main.async {
                    completionHandler(content, nil)
                }
            }
            catch {
                completionHandler(nil, error)
            }
            
        }
    }
}
