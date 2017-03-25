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
                for url in fileURLs {
                    let item = FileItem(url: url)
                    content.append(item)
                }
                
                DispatchQueue.main.async { completionHandler(content, nil) }
            }
            catch {
                DispatchQueue.main.async { completionHandler(nil, error) }
            }
            
        }
    }
    
    func delete(_ url: URL, completionHandler: @escaping (Error?) -> Void) {
        assert(isUnderRoot(url), "Deleted file (\(url)) must reside under root (\(self.rootUrl))")
            
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                sleep(10)
                if self.isUnderRoot(url) {
                    try FileManager.default.removeItem(at: url)
                    DispatchQueue.main.async { completionHandler(nil) }
                }
                else {
                    DispatchQueue.main.async { completionHandler(FileSystemError.invalidUrl(url: url)) }
                }
            }
            catch {
                DispatchQueue.main.async { completionHandler(error) }
            }
        }
    }
    
    func copy(_ srcUrl: URL, to destUrl: URL, completionHandler: @escaping (Error?) -> Void) {
        assert(srcUrl.isFileURL && destUrl.isFileURL, "Copy source (\(srcUrl)) and destination (\(destUrl)) must be local file urls.")
        assert(isUnderRoot(srcUrl) || isUnderRoot(destUrl), "Copy source (\(srcUrl)) or destination (\(destUrl)) msut be under root (\(self.rootUrl))")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if !srcUrl.isFileURL {
                    DispatchQueue.main.async { completionHandler(FileSystemError.invalidUrl(url: srcUrl)) }
                }
                else if !destUrl.isFileURL  {
                    DispatchQueue.main.async { completionHandler(FileSystemError.invalidUrl(url: destUrl)) }
                }
                else {
                    try FileManager.default.copyItem(at: srcUrl, to: destUrl)
                    DispatchQueue.main.async { completionHandler(nil) }
                }
            }
            catch {
                DispatchQueue.main.async { completionHandler(error) }
            }
        }
    }
    
    func move(_ srcUrl: URL, to destUrl: URL, completionHandler: @escaping (Error?) -> Void) {
        assert(srcUrl.isFileURL && destUrl.isFileURL, "Move source (\(srcUrl)) and destination (\(destUrl)) must be local file urls.")
        assert(isUnderRoot(srcUrl) || isUnderRoot(destUrl), "Move source (\(srcUrl)) or destination (\(destUrl)) msut be under root (\(self.rootUrl))")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if !srcUrl.isFileURL {
                    DispatchQueue.main.async { completionHandler(FileSystemError.invalidUrl(url: srcUrl)) }
                }
                else if !destUrl.isFileURL  {
                    DispatchQueue.main.async { completionHandler(FileSystemError.invalidUrl(url: destUrl)) }
                }
                else {
                    try FileManager.default.moveItem(at: srcUrl, to: destUrl)
                    DispatchQueue.main.async { completionHandler(nil) }
                }
            }
            catch {
                DispatchQueue.main.async { completionHandler(error) }
            }
        }
    }
}
