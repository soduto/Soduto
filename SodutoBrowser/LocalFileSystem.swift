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
    let fileOperationQueue = OperationQueue()
    
    init() {
        self.fileOperationQueue.maxConcurrentOperationCount = 2
        self.fileOperationQueue.qualityOfService = .userInitiated
    }
    
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
    
    func delete(_ url: URL) -> FileOperation {
        assert(isUnderRoot(url), "Deleted file (\(url)) must reside under root (\(self.rootUrl))")
        
        let operation = FileOperation(source: url)
        operation.sourceState = .inProgress
        operation.addExecutionBlock { 
            do {
                sleep(10)
                if self.isUnderRoot(url) {
                    try FileManager.default.removeItem(at: url)
                }
                else {
                    operation.error = FileSystemError.invalidUrl(url: url)
                }
            }
            catch {
                operation.error = error
            }
        }
        self.fileOperationQueue.addOperation(operation)
        return operation
    }
    
    func copy(_ srcUrl: URL, to destUrl: URL) -> FileOperation {
        assert(srcUrl.isFileURL && destUrl.isFileURL, "Copy source (\(srcUrl)) and destination (\(destUrl)) must be local file urls.")
        assert(isUnderRoot(destUrl), "Copy destination (\(destUrl)) must be under root (\(self.rootUrl))")
        
        let operation = FileOperation(source: srcUrl, destination: destUrl)
        operation.destinationState = .inProgress
        operation.addExecutionBlock {
            do {
                sleep(10)
                if !srcUrl.isFileURL {
                    operation.error = FileSystemError.invalidUrl(url: srcUrl)
                }
                else if !destUrl.isFileURL  {
                    operation.error = FileSystemError.invalidUrl(url: destUrl)
                }
                else {
                    try FileManager.default.copyItem(at: srcUrl, to: destUrl)
                }
            }
            catch {
                operation.error = error
            }
        }
        self.fileOperationQueue.addOperation(operation)
        return operation
    }
    
    func move(_ srcUrl: URL, to destUrl: URL) -> FileOperation {
        assert(srcUrl.isFileURL && destUrl.isFileURL, "Move source (\(srcUrl)) and destination (\(destUrl)) must be local file urls.")
        assert(isUnderRoot(destUrl), "Move destination (\(destUrl)) must be under root (\(self.rootUrl))")
        
        let operation = FileOperation(source: srcUrl, destination: destUrl)
        operation.destinationState = .inProgress
        operation.addExecutionBlock {
            do {
                sleep(10)
                if !srcUrl.isFileURL {
                    operation.error = FileSystemError.invalidUrl(url: srcUrl)
                }
                else if !destUrl.isFileURL  {
                    operation.error = FileSystemError.invalidUrl(url: destUrl)
                }
                else {
                    try FileManager.default.moveItem(at: srcUrl, to: destUrl)
                }
            }
            catch {
                operation.error = error
            }
        }
        self.fileOperationQueue.addOperation(operation)
        return operation
    }
}
