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
//        Place(name: "Home", url: FileManager.default.url(for: .userDirectory, in: FileManager.SearchPathDomainMask.userDomainMask, appropriateFor: nil, create: false))
    ]
    let fileOperationQueue = OperationQueue()
    
    init() {
        self.fileOperationQueue.maxConcurrentOperationCount = 2
        self.fileOperationQueue.qualityOfService = .userInitiated
    }
    
    func canDelete(_ url: URL) -> Bool { return canDelete(url, assertOnFailure: false) }
    func canDelete(_ url: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(isUnderRoot(url), "Deleted file (\(url)) must reside under root (\(self.rootUrl))")
        }
        return isUnderRoot(url)
    }
    
    func canCopy(_ srcUrl: URL, to destUrl: URL) -> Bool { return canCopy(srcUrl, to: destUrl, assertOnFailure: false) }
    func canCopy(_ srcUrl: URL, to destUrl: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(srcUrl.isFileURL && destUrl.isFileURL, "Copy source (\(srcUrl)) and destination (\(destUrl)) must be local file urls.")
            assert(isUnderRoot(srcUrl) || isUnderRoot(destUrl), "Copy source (\(srcUrl)) or destination (\(destUrl)) must be under root (\(self.rootUrl))")
            assert(!destUrl.isUnder(srcUrl), "Can not copy source (\(srcUrl) to its own subfolder (\(destUrl)).")
        }
        return srcUrl.isFileURL && destUrl.isFileURL && (isUnderRoot(srcUrl) || isUnderRoot(destUrl)) && !destUrl.isUnder(srcUrl)
    }
    
    func canMove(_ srcUrl: URL, to destUrl: URL) -> Bool { return canMove(srcUrl, to: destUrl, assertOnFailure: false) }
    func canMove(_ srcUrl: URL, to destUrl: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(srcUrl.isFileURL && destUrl.isFileURL, "Move source (\(srcUrl)) and destination (\(destUrl)) must be local file urls.")
            assert(isUnderRoot(destUrl), "Move destination (\(destUrl)) must be under root (\(self.rootUrl))")
            assert(!destUrl.isUnder(srcUrl), "Can not move source (\(srcUrl) to its own subfolder (\(destUrl)).")
        }
        return srcUrl.isFileURL && destUrl.isFileURL && isUnderRoot(destUrl) && !destUrl.isUnder(srcUrl)
    }
    
    func canCreateFolder(_ url: URL) -> Bool { return canDelete(url, assertOnFailure: false) }
    func canCreateFolder(_ url: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(isUnderRoot(url), "Folder to be created (\(url)) bust be under root (\(rootUrl)).")
        }
        return isUnderRoot(url)
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
        _ = canDelete(url, assertOnFailure: true)
        
        let operation = FileOperation(source: url)
        operation.sourceState = .inProgress
        operation.addExecutionBlock { 
            do {
                sleep(10)
                try FileManager.default.removeItem(at: url)
                operation.sourceState = .deleted
            }
            catch {
                operation.error = error
                operation.sourceState = .unchanged
            }
        }
        self.fileOperationQueue.addOperation(operation)
        return operation
    }
    
    func copy(_ srcUrl: URL, to destUrl: URL) -> FileOperation {
        _ = canCopy(srcUrl, to: destUrl, assertOnFailure: true)
        
        let operation = FileOperation(source: srcUrl, destination: destUrl)
        operation.destinationState = .inProgress
        operation.addExecutionBlock {
            do {
                sleep(10)
                try FileManager.default.copyItem(at: srcUrl, to: destUrl)
                operation.destinationState = .present
            }
            catch {
                operation.error = error
                operation.destinationState = .deleted
            }
        }
        self.fileOperationQueue.addOperation(operation)
        return operation
    }
    
    func move(_ srcUrl: URL, to destUrl: URL) -> FileOperation {
        _ = canMove(srcUrl, to: destUrl, assertOnFailure: true)
        
        let operation = FileOperation(source: srcUrl, destination: destUrl)
        operation.destinationState = .inProgress
        operation.addExecutionBlock {
            do {
                sleep(10)
                try FileManager.default.moveItem(at: srcUrl, to: destUrl)
                operation.sourceState = .deleted
                operation.destinationState = .present
            }
            catch {
                operation.error = error
                operation.sourceState = .present
                operation.destinationState = .deleted
            }
        }
        self.fileOperationQueue.addOperation(operation)
        return operation
    }
    
    func createFolder(_ url: URL) -> FileOperation {
        _ = canCreateFolder(url, assertOnFailure: true)
        
        let operation = FileOperation(destination: url)
        operation.destinationState = .inProgress
        operation.addExecutionBlock {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                operation.destinationState = .present
            }
            catch {
                operation.error = error
                operation.destinationState = .deleted
            }
        }
        self.fileOperationQueue.addOperation(operation)
        return operation
    }
}
