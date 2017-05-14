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
    
    weak var delegate: FileSystemDelegate?
    
    let name: String = NSLocalizedString("Local", comment: "File system name")
    let rootUrl: URL = URL(fileURLWithPath: "/")
    let places: [Place] = []
    let fileOperationQueue = OperationQueue()
    
    init() {
        self.fileOperationQueue.maxConcurrentOperationCount = 2
        self.fileOperationQueue.qualityOfService = .userInitiated
    }
    
    func load(_ url: URL, completionHandler: @escaping (([FileItem]?, Int64?, Error?) -> Void)) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                var content: [FileItem] = []
                let fileURLs: [URL] = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
                for url in fileURLs {
                    let item = FileItem(url: url)
                    content.append(item)
                }
                let space = self?.freeSpace(at: url)
                
                DispatchQueue.main.async { completionHandler(content, space, nil) }
            }
            catch {
                DispatchQueue.main.async { completionHandler(nil, nil, error) }
            }
            
        }
    }
    
    func delete(_ url: URL) -> FileOperation {
        _ = canDelete(url, assertOnFailure: true)
        
        let operation = FileOperation(operation: .delete, source: url)
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
        
        let operation = FileOperation(operation: .copy, source: srcUrl, destination: destUrl)
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
        
        let operation = FileOperation(operation: .move, source: srcUrl, destination: destUrl)
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
        
        let operation = FileOperation(operation: .createFolder, destination: url)
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
    
    
    // MARK: Private stuff
    
    private func freeSpace(at url: URL) -> Int64? {
        assert(isUnderRoot(url) || url == self.rootUrl, "URL (\(url)) is outside root tree (\(self.rootUrl)).")
        guard let fileSystemAttrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path) else { assertionFailure("Failed to retrieve file system information for URL [\(url)]"); return nil }
        guard let freeSpace = fileSystemAttrs[FileAttributeKey.systemFreeSize] as? NSNumber else { assertionFailure("Failed to retrieve file system free space for URL [\(url)]"); return nil }
        return freeSpace.int64Value
    }
}
