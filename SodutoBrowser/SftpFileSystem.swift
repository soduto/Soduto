//
//  SftpFileSystem.swift
//  Soduto
//
//  Created by Giedrius on 2017-04-22.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import CleanroomLogger
import Cocoa

class SftpFileSystem: NSObject, FileSystem, NMSSHSessionDelegate {
    
    // MARK: Types
    
    enum SftpError: Error {
        case connectionFailed
        case authenticationFailed
        case sftpInitializationFailed
        case invalidDirectoryContent(at: URL)
        case deletingFileFailed(at: URL)
        case copyingFileFailed(from: URL, to: URL)
        case movingFileFailed(from: URL, to: URL)
        case regularFileInsteadOfDirectory(at: URL)
        case downloadingFileFailed(at: URL)
        case creatingDirectoryFailed(at: URL)
    }
    
    
    // MARK: Properties
    
    let name: String
    let rootUrl: URL
    let places: [Place] = []
    
    private let fileOperationQueue = OperationQueue()
    private let session: NMSSHSession
    private let sftp: NMSFTP
    
    
    // MARK: Setup / Cleanup
    
    init(name: String, host: String, user: String, password: String, path: String) throws {
        self.name = name
        
        self.session = NMSSHSession.connect(toHost: host, withUsername: user)
        guard self.session.isConnected else { throw SftpError.connectionFailed }
        
        self.session.authenticate(byPassword: password)
        guard self.session.isAuthorized else { throw SftpError.authenticationFailed }
        
        self.sftp = NMSFTP.connect(with: self.session)
        guard self.sftp.isConnected else { throw SftpError.sftpInitializationFailed }
        
        self.rootUrl = URL(string: "sftp://\(host)\(path)")!
        
        self.fileOperationQueue.maxConcurrentOperationCount = 1
        self.fileOperationQueue.qualityOfService = .userInitiated
    }
    
    
    // MARK: FileSystem
    
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
            assert(srcUrl.absoluteURL != destUrl.absoluteURL, "Copy source and destination is the same (\(srcUrl)).")
            assert(isSupportedUrl(srcUrl), "Unsupported source url (\(srcUrl)).")
            assert(isSupportedUrl(destUrl), "Unsupported destination url (\(srcUrl)).")
            assert(isUnderRoot(srcUrl) || isUnderRoot(destUrl), "Copy source (\(srcUrl)) or destination (\(destUrl)) must be under root (\(self.rootUrl))")
            assert(!destUrl.isUnder(srcUrl), "Can not copy source (\(srcUrl) to its own subfolder (\(destUrl)).")
        }
        return (srcUrl.absoluteURL != destUrl.absoluteURL) && isSupportedUrl(srcUrl) && isSupportedUrl(destUrl) && (isUnderRoot(srcUrl) || isUnderRoot(destUrl)) && !destUrl.isUnder(srcUrl)
    }
    
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
    
    func canCreateFolder(_ url: URL) -> Bool { return canDelete(url, assertOnFailure: false) }
    func canCreateFolder(_ url: URL, assertOnFailure: Bool) -> Bool {
        if assertOnFailure {
            assert(isUnderRoot(url), "Folder to be created (\(url)) bust be under root (\(rootUrl)).")
        }
        return isUnderRoot(url)
    }
    
    func load(_ url: URL, completionHandler: @escaping (([FileItem]?, Int64?, Error?) -> Void)) {
        assert(isUnderRoot(url) || url == self.rootUrl, "URL (\(url)) is outside root tree (\(self.rootUrl)).")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let `self` = self else { return }
            do {
                guard let contents = self.sftp.contentsOfDirectory(atPath: url.path) as? [NMSFTPFile] else { throw SftpError.invalidDirectoryContent(at: url) }
                let fileItems = contents.flatMap { return FileItem(sftpFile: $0, parentUrl: url, user: self.session.username ?? "") }
                let freeSpace = self.remoteFreeSpace(at: url)
                DispatchQueue.main.async { completionHandler(fileItems, freeSpace, nil) }
            }
            catch {
                DispatchQueue.main.async { completionHandler(nil, nil, error) }
            }
            
        }
    }
    
    func delete(_ url: URL) -> FileOperation {
        _ = canDelete(url, assertOnFailure: true)
        
        let operation = FileOperation(source: url)
        operation.sourceState = .inProgress
        operation.addExecutionBlock { [weak self] in
            guard let `self` = self else { return }
            do {
                try self.deleteRemote(at: url)
                operation.sourceState = .deleted
            }
            catch {
                operation.error = error
                operation.sourceState = .present
            }
        }
        self.fileOperationQueue.addOperation(operation)
        return operation
    }
    
    func copy(_ srcUrl: URL, to destUrl: URL) -> FileOperation {
        _ = canCopy(srcUrl, to: destUrl, assertOnFailure: true)
        
        let operation = FileOperation(source: srcUrl, destination: destUrl)
        operation.destinationState = .inProgress
        operation.addExecutionBlock { [weak self] in
            guard let `self` = self else { return }
            do {
                if self.isUnderRoot(srcUrl) && self.isUnderRoot(destUrl) {
                    guard self.sftp.copyContents(ofPath: srcUrl.path, toFileAtPath: destUrl.path, progress: nil) else {
                        throw SftpError.copyingFileFailed(from: srcUrl, to: destUrl)
                    }
                }
                else if self.isUnderRoot(srcUrl) {
                    try self.download(from: srcUrl, to: destUrl)
                }
                else if self.isUnderRoot(destUrl) {
                    try self.upload(from: srcUrl, to: destUrl)
                }
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
        operation.sourceState = .inProgress
        operation.destinationState = .inProgress
        operation.addExecutionBlock {[weak self] in
            guard let `self` = self else { return }
            do {
                guard self.sftp.moveItem(atPath: srcUrl.path, toPath: destUrl.path) else { throw SftpError.movingFileFailed(from: srcUrl, to: destUrl) }
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
                guard self.sftp.createDirectory(atPath: url.path) else { throw SftpError.creatingDirectoryFailed(at: url) }
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
    
    /// Chack if given url is understood by the file system.
    private func isSupportedUrl(_ url: URL) -> Bool {
        return isUnderRoot(url) || url.isFileURL
    }
    
    /// Make sure there is required directory on local file system
    private func ensureLocalDirectory(at url: URL) throws {
        var existsDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &existsDirectory) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        else if !existsDirectory.boolValue {
            throw SftpError.regularFileInsteadOfDirectory(at: url)
        }

    }
    
    /// Synchronously download remote file or directory to local destination.
    private func download(from srcUrl: URL, to destUrl: URL) throws {
        assert(isUnderRoot(srcUrl), "Source URL (\(srcUrl)) expected to be under root (\(self.rootUrl)).")
        assert(destUrl.isFileURL, "Destination URL (\(destUrl)) expected to be local directory URL.")
        
        if srcUrl.hasDirectoryPath {
            try downloadDirectory(from: srcUrl, to: destUrl)
        }
        else {
            self.session.channel.downloadFile(srcUrl.path, to: destUrl.path)
        }
    }
    
    /// Synchromously donwload remote directory to local destination.
    private func downloadDirectory(from srcUrl: URL, to destUrl: URL) throws {
        assert(isUnderRoot(srcUrl), "Source URL (\(srcUrl)) expected to be under root (\(self.rootUrl)).")
        assert(srcUrl.hasDirectoryPath, "Source URL (\(srcUrl)) expected to be a directory.")
        assert(destUrl.isFileURL, "Destination URL (\(destUrl)) expected to be local directory URL.")
        
        guard let files = self.sftp.contentsOfDirectory(atPath: srcUrl.path) as? [NMSFTPFile] else { throw SftpError.invalidDirectoryContent(at: srcUrl) }
        
        try ensureLocalDirectory(at: destUrl)
        
        for file in files {
            guard let filename = file.filename else { assertionFailure("File name expected to be non-nil."); continue }
            let fileSrcUrl = srcUrl.appendingPathComponent(filename, isDirectory: file.isDirectory)
            let fileDestUrl = destUrl.appendingPathComponent(filename, isDirectory: file.isDirectory)
            try download(from: fileSrcUrl, to: fileDestUrl)
        }
    }
    
    /// Make sure there is required directory on remote file system
    private func ensureRemoteDirectory(at url: URL) throws {
        assert(isUnderRoot(url), "URL (\(url)) expected to be under root (\(self.rootUrl)).")
        
        guard !self.sftp.fileExists(atPath: url.path) else { throw SftpError.regularFileInsteadOfDirectory(at: url) }
        guard !self.sftp.directoryExists(atPath: url.path) else { return }
        guard self.sftp.createDirectory(atPath: url.path) else { throw SftpError.creatingDirectoryFailed(at: url) }
    }
    
    /// Synchronously upload local file or directory to remote destination.
    private func upload(from srcUrl: URL, to destUrl: URL) throws {
        assert(srcUrl.isFileURL, "Source URL (\(srcUrl)) expected to be local directory URL.")
        assert(isUnderRoot(destUrl), "Destination URL (\(destUrl)) expected to be under root (\(self.rootUrl)).")
        
        if srcUrl.hasDirectoryPath {
            try uploadDirectory(from: srcUrl, to: destUrl)
        }
        else {
            self.session.channel.uploadFile(srcUrl.path, to: destUrl.path)
        }
    }
    
    /// Synchromously upload local directory to remote destination.
    private func uploadDirectory(from srcUrl: URL, to destUrl: URL) throws {
        assert(srcUrl.isFileURL, "Source URL (\(srcUrl)) expected to be local directory URL.")
        assert(srcUrl.hasDirectoryPath, "Source URL (\(srcUrl)) expected to be a directory.")
        assert(isUnderRoot(destUrl), "Destination URL (\(destUrl)) expected to be under root (\(self.rootUrl)).")
        
        let files = try FileManager.default.contentsOfDirectory(at: srcUrl, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants, .skipsSubdirectoryDescendants])
        
        try ensureRemoteDirectory(at: destUrl)
        
        for fileSrcUrl in files {
            let fileDestUrl = fileSrcUrl.movedTo(destUrl)
            try upload(from: fileSrcUrl, to: fileDestUrl)
        }
    }
    
    /// Synchromously delete remote item, be it a file or a possibly non-empty directory
    private func deleteRemote(at url: URL) throws {
        assert(isUnderRoot(url), "URL being deleted (\(url)) expected to be under root (\(self.rootUrl)).")
        
        if url.hasDirectoryPath {
            try deleteRemoteDirectory(at: url)
        }
        else {
            guard self.sftp.removeFile(atPath: url.path) else { throw SftpError.deletingFileFailed(at: url) }
        }
    }
    
    /// Synchronously delete possibly non-empty remote directory
    private func deleteRemoteDirectory(at url: URL) throws {
        assert(isUnderRoot(url), "URL being deleted (\(url)) expected to be under root (\(self.rootUrl)).")
        assert(url.hasDirectoryPath, "URL being deleted (\(url)) expected to be a directory.")
        
        // first try delete directly
        if self.sftp.removeDirectory(atPath: url.path) { return }
        
        // However direct delete may fail on non-empty directory with SFTP error 4 (Failure). In such case try deleteing children manually.
        
        switch self.session.lastError {
        case let err as NSError: guard Int32(err.code) == LIBSSH2_ERROR_SFTP_PROTOCOL else { throw self.session.lastError }
        default: throw self.session.lastError
        }
        
        switch self.sftp.lastError {
        case let err as NSError: guard Int32(err.code) == LIBSSH2_FX_FAILURE else { throw self.sftp.lastError }
        default: throw self.sftp.lastError
        }
        
        // Delete children
        guard let files = self.sftp.contentsOfDirectory(atPath: url.path) as? [NMSFTPFile] else { throw SftpError.invalidDirectoryContent(at: url) }
        for file in files {
            guard let filename = file.filename else { assertionFailure("File name expected to be non-nil."); continue }
            let fileUrl = url.appendingPathComponent(filename, isDirectory: file.isDirectory)
            try deleteRemote(at: fileUrl)
        }
        
        // Try again to delete directory
        guard self.sftp.removeDirectory(atPath: url.path) else { throw SftpError.deletingFileFailed(at: url) }
    }
    
    /// Synchromously retrieve remote free space
    private func remoteFreeSpace(at url: URL) -> Int64? {
        assert(isUnderRoot(url) || url == self.rootUrl, "URL (\(url)) is outside root tree (\(self.rootUrl)).")
        do {
            let output = try self.session.channel.execute("df -k \(url.path.replacingOccurrences(of: " ", with: "\\ ")) | tail -1 | awk '{ print $4 }' ")
            let outputLines = output.components(separatedBy: "\n")
            guard outputLines.count > 0 else { assertionFailure("Expected non-empty response"); return nil }
            guard let freeKb = Int64(outputLines[0]) else { assertionFailure("Failed to retrieve free space for URL [\(url)], got response: \(output)"); return nil }
            return freeKb * 1024
        }
        catch {
            Log.error?.message("Failed to retrieve free disk space for URL [\(url)].")
            return nil
        }
    }
}


// MARK: -

extension FileItem {
    
    fileprivate convenience init?(sftpFile: NMSFTPFile, parentUrl: URL, user: String) {
        guard var name = sftpFile.filename else { return nil }
        if name.hasSuffix("/") { name = name.substring(to: name.index(before: name.endIndex)) }
        
        let url = parentUrl.appendingPathComponent(name, isDirectory: sftpFile.isDirectory)
        
        var flags: Flags = []
        if sftpFile.isWritable(by: user) { flags.insert(.isWritable) }
        if sftpFile.isReadable(by: user) { flags.insert(.isReadable) }
        if sftpFile.isDirectory { flags.insert(.isDirectory) }
        if name.hasPrefix(".") { flags.insert(.isHidden) }
        
        let fileType: String = flags.contains(.isDirectory) ? String(kUTTypeDirectory) : url.pathExtension
        let icon = NSWorkspace.shared().icon(forFileType: fileType)
        
        self.init(url: url, name: name, icon: icon, flags: flags)
    }
    
}


// MARK: -

extension NMSFTPFile {
    
    fileprivate func isReadable(by user: String) -> Bool {
        return true
    }
    
    fileprivate func isWritable(by user: String) -> Bool {
        return true
    }
    
}
