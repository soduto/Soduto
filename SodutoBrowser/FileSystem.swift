//
//  FileSystem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

enum FileSystemError: Error {
    case invalidUrl(url: URL)
    case loadFailed(url: URL, reason: String)
    case deleteFailed(url: URL, reason: String)
    case copyFailed(url: URL, reason: String)
    case moveFailed(url: URL, reason: String)
    case fileExists(url: URL)
    case fileDoesNotExist(url: URL)
    case fileSystemUnreachable(url: URL)
    case internalFailure
}

struct Place {
    let name: String
    let url: URL
    init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

class FileOperation: BlockOperation {
    
    enum FileState {
        case unchanged
        case present
        case inProgress
        case deleted
    }
    
    let source: URL?
    let destination: URL?
    var sourceState: FileState = .unchanged
    var destinationState: FileState = .unchanged
    var error: Error?
    
    init(source: URL? = nil, destination: URL? = nil) {
        self.source = source
        self.destination = destination
    }
    
    init(source: URL? = nil, destination: URL? = nil, error: Error) {
        self.source = source
        self.destination = destination
        self.error = error
    }
}

protocol FileSystem: class {
    
    var name: String { get }
    var rootUrl: URL { get }
    var places: [Place] { get }
    
    /// Basic check if url can be deleted by this file system. It does not guarantee that operation will succeed, however.
    func canDelete(_ url: URL) -> Bool
    /// Basic check if copy is supported by this file system. It does not guarantee that operation will succeed, however.
    func canCopy(_ srcUrl: URL, to destUrl: URL) -> Bool
    /// Basic check if move is supported by this file system. It does not guarantee that operation will succeed, however.
    func canMove(_ srcUrl: URL, to destUrl: URL) -> Bool
    /// Basic check if creating folder at provided URL is supported by this file system. It does not guarantee that operation will succeed, however.
    func canCreateFolder(_ url: URL) -> Bool
    
    /// Read file list for provided URL. URL must reside under rootUrl.
    /// Completion handler is called with retrieved file itemArray, free disk space and error paraneters.
    func load(_ url: URL, completionHandler: @escaping ([FileItem]?, Int64?, Error?)->Void)
    
    /// Delete file at provided URL. URL must reside under rootUrl
    func delete(_ url: URL) -> FileOperation
    
    /// Copy file from one place to another. At least one URL must reside under rootUrl. destUrl must indicate the
    /// final copied file name, not the directory containing it.
    func copy(_ srcUrl: URL, to destUrl: URL) -> FileOperation
    
    /// Move file from one place to another. Both URLs must reside under rootUrl
    func move(_ srcUrl: URL, to destUrl: URL) -> FileOperation
    
    /// Create folder at specified url, which must be under file system root
    func createFolder(_ url: URL) -> FileOperation
}

extension FileSystem {
    
    var defaultPlace: Place {
        if self.places.count > 0 {
            return self.places[0]
        }
        else {
            return Place(name: NSLocalizedString("Root", comment: "directory"), url: self.rootUrl)
        }
    }
    
    var tempDownloadsDirectory: URL {
        if #available(OSX 10.12, *) {
            return FileManager.default.temporaryDirectory
        } else {
            return (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
    }
    
    func isUnderRoot(_ url: URL) -> Bool {
        return url.isUnder(self.rootUrl)
    }
    
    func isValid(_ url: URL) -> Bool {
        return url.isUnder(self.rootUrl) || url == self.rootUrl
    }
    
    func canDelete(_ fileItem: FileItem) -> Bool {
        return fileItem.canModify && canDelete(fileItem.url)
    }
    
    func canDelete(_ urls: [URL]) -> Bool {
        return urls.every { return canDelete($0) }
    }
    
    func canDelete(_ fileItems: [FileItem]) -> Bool {
        return fileItems.every { return canDelete($0) }
    }
    
    func canCopy(_ fileItem: FileItem, to destURL: URL) -> Bool {
        return canCopy(fileItem.url, to: destURL)
    }
    
    func canCopy(_ srcFileItem: FileItem, to destFileItem: FileItem) -> Bool {
        return destFileItem.canModify && canCopy(srcFileItem, to: destFileItem.url)
    }
    
    func canCopy(_ urls: [URL], to destURL: URL) -> Bool {
        return urls.every { return canCopy($0, to: destURL) }
    }
    
    func canCopy(_ fileItems: [FileItem], to destURL: URL) -> Bool {
        return fileItems.every { return canCopy($0, to: destURL) }
    }
    
    func canCopy(_ fileItems: [FileItem], to destFileItem: FileItem) -> Bool {
        return destFileItem.canModify && fileItems.every { return canCopy($0, to: destFileItem.url) }
    }
    
    func canMove(_ fileItem: FileItem, to destURL: URL) -> Bool {
        return fileItem.canModify && canMove(fileItem.url, to: destURL)
    }
    
    func canMove(_ srcFileItem: FileItem, to destFileItem: FileItem) -> Bool {
        return destFileItem.canModify && canMove(srcFileItem, to: destFileItem.url)
    }
    
    func canMove(_ urls: [URL], to destURL: URL) -> Bool {
        return urls.every { return canMove($0, to: destURL) }
    }
    
    func canMove(_ fileItems: [FileItem], to destURL: URL) -> Bool {
        return fileItems.every { return canMove($0, to: destURL) }
    }
    
    func canMove(_ fileItems: [FileItem], to destFileItem: FileItem) -> Bool {
        return destFileItem.canModify && fileItems.every { return canMove($0, to: destFileItem.url) }
    }
    
    func canOpenFile(_ fileItem: FileItem) -> Bool {
        return canOpenFile(fileItem.url)
    }
    
    func canOpenFile(_ url: URL) -> Bool {
        return !url.hasDirectoryPath && canCopy([url], to: tempDownloadsDirectory)
    }
}
