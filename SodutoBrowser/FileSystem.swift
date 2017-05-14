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
    
    enum Operation: Int {
        case delete
        case copy
        case move
        case createFolder
    }
    
    let operation: Operation
    let source: URL?
    var destination: URL?
    var sourceState: FileState = .unchanged
    var destinationState: FileState = .unchanged
    var error: Error?
    
    init(operation: Operation, source: URL? = nil, destination: URL? = nil) {
        self.operation = operation
        self.source = source
        self.destination = destination
    }
    
    init(operation: Operation, source: URL? = nil, destination: URL? = nil, error: Error) {
        self.operation = operation
        self.source = source
        self.destination = destination
        self.error = error
    }
}

protocol FileSystemDelegate: class {
    
    func fileSystem(_ fileSystem: FileSystem, willAddFileAt url: URL, from fileOperation: FileOperation)
    func fileSystem(_ fileSystem: FileSystem, didAddFileAt url: URL, from fileOperation: FileOperation)
    func fileSystem(_ fileSystem: FileSystem, didRemoveFileAt url: URL, from fileOperation: FileOperation)
    
}

protocol FileSystem: class {
    
    weak var delegate: FileSystemDelegate? { get set }
    
    var name: String { get }
    var rootUrl: URL { get }
    var places: [Place] { get }
    
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
    
    /// Basic check if given URL belongs to file system
    func isOwn(_ url: URL) -> Bool {
        return url.isUnder(self.rootUrl) || url == self.rootUrl
    }
    
    /// Basic check if given url is understood by the file system.
    func isSupportedUrl(_ url: URL) -> Bool {
        return isUnderRoot(url) || url.isFileURL
    }
    
    
    // MARK: Deleting
    
    func canDelete(_ url: URL) -> Bool { return canDelete(url, assertOnFailure: false) }
    func canDelete(_ url: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(isUnderRoot(url), "Deleted file (\(url)) must reside under root (\(self.rootUrl))")
        }
        return isUnderRoot(url)
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
    
    
    // MARK: Copying
    
    func canCopy(_ srcUrl: URL, to destUrl: URL) -> Bool { return canCopy(srcUrl, to: destUrl, assertOnFailure: false) }
    func canCopy(_ srcUrl: URL, to destUrl: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(srcUrl.absoluteURL != destUrl.absoluteURL, "Copy source and destination is the same (\(srcUrl)).")
            assert(isSupportedUrl(srcUrl), "Unsupported source url (\(srcUrl)).")
            assert(isSupportedUrl(destUrl), "Unsupported destination url (\(srcUrl)).")
            assert(isUnderRoot(srcUrl) || isUnderRoot(destUrl), "Copy source (\(srcUrl)) or destination (\(destUrl)) must be under root (\(self.rootUrl))")
            assert(!destUrl.isUnder(srcUrl), "Can not copy source (\(srcUrl) to its own subfolder (\(destUrl)).")
        }
        return (srcUrl.absoluteURL != destUrl.absoluteURL) && isSupportedUrl(srcUrl) && isSupportedUrl(destUrl) && (isUnderRoot(srcUrl) || isUnderRoot(destUrl)) && !destUrl.isUnder(srcUrl)
    }
    
    func canCopy(_ srcFileItem: FileItem, to destFileItem: FileItem) -> Bool {
        return destFileItem.canModify && canCopy(srcFileItem, to: destFileItem.url)
    }
    
    func canCopy(_ fileItem: FileItem, to destURL: URL) -> Bool {
        return fileItem.canRead && canCopy(fileItem.url, to: destURL)
    }
    
    func canCopy(_ urls: [URL], to destURL: URL) -> Bool {
        return urls.every { return canCopy($0, to: destURL) }
    }
    
    func canCopy(_ fileItems: [FileItem], to destURL: URL) -> Bool {
        return fileItems.every { return canCopy($0, to: destURL) }
    }
    
    func canCopy(_ fileItems: [FileItem], to destFileItem: FileItem) -> Bool {
        return fileItems.every { return canCopy($0, to: destFileItem) }
    }
    
    
    // MARK: Moving
    
    func canMove(_ srcUrl: URL, to destUrl: URL) -> Bool { return canMove(srcUrl, to: destUrl, assertOnFailure: false) }
    func canMove(_ srcUrl: URL, to destUrl: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(srcUrl.absoluteURL != destUrl.absoluteURL, "Move source and destination is the same (\(srcUrl)).")
            assert(isSupportedUrl(srcUrl), "Unsupported source url (\(srcUrl)).")
            assert(isSupportedUrl(destUrl), "Unsupported destination url (\(srcUrl)).")
            assert(isUnderRoot(srcUrl), "Move source (\(srcUrl)) must be under root (\(self.rootUrl))")
            assert(isUnderRoot(destUrl), "Move destination (\(destUrl)) must be under root (\(self.rootUrl))")
            assert(!destUrl.isUnder(srcUrl), "Can not move source (\(srcUrl) to its own subfolder (\(destUrl)).")
        }
        return (srcUrl.absoluteURL != destUrl.absoluteURL) && isSupportedUrl(srcUrl) && isSupportedUrl(destUrl) && isUnderRoot(srcUrl) && isUnderRoot(destUrl) && !destUrl.isUnder(srcUrl)
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
    
    
    // MARK: Folder creating
    
    func canCreateFolder(_ url: URL) -> Bool { return canDelete(url, assertOnFailure: false) }
    func canCreateFolder(_ url: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(isUnderRoot(url), "Folder to be created (\(url)) bust be under root (\(rootUrl)).")
            assert(url.hasDirectoryPath, "URL [\(url)] expected to have directory path.")
        }
        return isUnderRoot(url) && url.hasDirectoryPath
    }
    
    
    // MARK: Opening
    
    func canOpenFile(_ fileItem: FileItem) -> Bool {
        return fileItem.canRead && canOpenFile(fileItem.url)
    }
    
    func canOpenFile(_ url: URL) -> Bool {
        return !url.hasDirectoryPath && canCopy([url], to: tempDownloadsDirectory)
    }
    
    
    // MARK: Info
    
    func description(for url: URL) -> String {
        if isOwn(url) {
            return "'\(url.path)' (\(name))"
        }
        else if url.isFileURL {
            return "'\(url.path)' (\(NSLocalizedString("local", comment: "Local file description")))"
        }
        else {
            return "'\(url.absoluteString)'"
        }
    }
}
