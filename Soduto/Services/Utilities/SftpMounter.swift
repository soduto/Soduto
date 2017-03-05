//
//  SftpMounter.swift
//  Soduto
//
//  Created by Giedrius on 2017-02-21.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import CleanroomLogger
import AppKit

protocol SftpMounterDelegate: class {
    func sftpMounterDidMount(_ mounter: SftpMounter)
    func sftpMounterDidUnmount(_ mounter: SftpMounter)
    func sftpMounterDidFailToMount(_ mounter: SftpMounter)
}

class SftpMounter {
    
    // MARK: Static properties
    
    public static let requestTimeoutInterval: TimeInterval = 10.0
    
    public static var mountLocation: URL {
        return URL(fileURLWithPath: "Volumes", isDirectory: true, relativeTo: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    }
    
    
    // MARK: Instance properties
    
    public var mountPoint: URL {
        return URL(fileURLWithPath: self.device.id, isDirectory: true, relativeTo: type(of: self).mountLocation)
    }
    
    public private(set) var isMounted: Bool = false
    public weak var delegate: SftpMounterDelegate?
    public let device: Device
    private var requestTimer: Timer?
    private var fs: GMUserFileSystem?
    private var sftpFS: SftpFS?
    
    
    // MARK: Init / Deinit
    
    init(device: Device) {
        self.device = device
        NotificationCenter.default.addObserver(self, selector: #selector(didMount(_:)), name: NSNotification.Name(rawValue: kGMUserFileSystemDidMount), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didUnmount(_:)), name: NSNotification.Name(rawValue: kGMUserFileSystemDidUnmount), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didFailToMount(_:)), name: NSNotification.Name(rawValue: kGMUserFileSystemMountFailed), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    // MARK: Public methods
    
    public func mount() {
        guard !self.isMounted else { return }
        
        // cleanup whatever we were doing
        self.unmount()
        self.requestTimer?.invalidate()
        
        self.device.send(DataPacket.sftpStartBrowsingPacket())
        self.requestTimer = Timer.scheduledTimer(withTimeInterval: type(of: self).requestTimeoutInterval, repeats: false) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.requestTimer = nil
            strongSelf.delegate?.sftpMounterDidFailToMount(strongSelf)
        }
    }
    
    public func unmount() {
        let isMounted = self.isMounted
        self.fs?.unmount()
        self.fs = nil
        self.sftpFS = nil
        self.requestTimer?.invalidate()
        self.requestTimer = nil
        if isMounted {
            self.delegate?.sftpMounterDidUnmount(self)
        }
    }
    
    public func handleDataPacket(_ dataPacket: DataPacket) -> Bool {
        guard dataPacket.isSftpPacket else { return false }
        guard self.requestTimer != nil else { return false } // Not waiting or maybe too late
        
        self.requestTimer?.invalidate()
        self.requestTimer = nil
        
        do {
            let stop = try dataPacket.getStopFlag()
            if stop {
                self.unmount()
            }
            else {
                guard let ip = try dataPacket.getIp() else { return true }
                guard let port = try dataPacket.getPort() else { return true }
                guard let user = try dataPacket.getUser() else { return true }
                guard let password = try dataPacket.getPassword() else { return true }
                guard let path = try dataPacket.getPath() else { return true }
                
                try FileManager.default.createDirectory(at: self.mountPoint, withIntermediateDirectories: true, attributes: nil)
                
                self.sftpFS = try SftpFS(host: "\(ip):\(port)", user: user, password: password, path: path)
                self.fs = GMUserFileSystem(delegate: self.sftpFS, isThreadSafe: true)
                let options: [String] = ["volname=\(self.device.name)", "rdonly", "debug"]
                self.fs?.mount(atPath: self.mountPoint.path, withOptions: options)
            }
        }
        catch {
            Log.error?.message("Failed to handle SFTP data packet: \(error)")
        }
        
        return true
    }
    
    
    // MARK: Notification handlers
    
    @objc private func didMount(_ notification: Notification) {
        self.isMounted = true
        self.delegate?.sftpMounterDidMount(self)
    }
    
    @objc private func didUnmount(_ notification: Notification) {
        self.isMounted = false
        self.delegate?.sftpMounterDidUnmount(self)
    }
    
    @objc private func didFailToMount(_ notification: Notification) {
        self.isMounted = false
        self.delegate?.sftpMounterDidFailToMount(self)
    }
    
}


// MARK: DataPacket (SFTP)

/// SFTP service data packet utilities (public)
public extension DataPacket {
    
    // MARK: Properties
    
    static let sftpPacketType = "kdeconnect.sftp"
    static let sftpRequestPacketType = "kdeconnect.sftp.request"
    
    var isSftpPacket: Bool { return self.type == DataPacket.sftpPacketType }
    var isSftpRequestPacket: Bool { return self.type == DataPacket.sftpRequestPacketType }
    
}

/// SFTP service data packet utilities (local)
fileprivate extension DataPacket {
    
    // MARK: Types
    
    enum SftpError: Error {
        case wrongType
        case invalidIp
        case invalidPort
        case invalidUser
        case invalidPassword
        case invalidPath
        case invalidStopFlag
    }
    
    struct SftpProperty {
        static let ip = "ip"
        static let port = "port"
        static let user = "user"
        static let password = "password"
        static let path = "path"
        static let startBrowsing = "startBrowsing"
        static let stop = "stop"
    }
    
    
    // MARK: Public static methods
    
    static func sftpStartBrowsingPacket() -> DataPacket {
        return DataPacket(type: sftpRequestPacketType, body: [
            SftpProperty.startBrowsing: true as AnyObject
        ])
    }
    
    
    // MARK: Public methods
    
    func getIp() throws -> String? {
        try self.validateSftpType()
        guard body.keys.contains(SftpProperty.ip) else { return nil }
        guard let value = body[SftpProperty.ip] as? String else { throw SftpError.invalidIp }
        return value
    }
    
    func getPort() throws -> UInt16? {
        try self.validateSftpType()
        guard body.keys.contains(SftpProperty.port) else { return nil }
        guard let value = body[SftpProperty.port] as? NSNumber else { throw SftpError.invalidPort }
        return value.uint16Value
    }
    
    func getUser() throws -> String? {
        try self.validateSftpType()
        guard body.keys.contains(SftpProperty.user) else { return nil }
        guard let value = body[SftpProperty.user] as? String else { throw SftpError.invalidUser }
        return value
    }
    
    func getPassword() throws -> String? {
        try self.validateSftpType()
        guard body.keys.contains(SftpProperty.password) else { return nil }
        guard let value = body[SftpProperty.password] as? String else { throw SftpError.invalidPassword }
        return value
    }
    
    func getPath() throws -> String? {
        try self.validateSftpType()
        guard body.keys.contains(SftpProperty.path) else { return nil }
        guard let value = body[SftpProperty.path] as? String else { throw SftpError.invalidPath }
        return value
    }
    
    func getStopFlag() throws -> Bool {
        try self.validateSftpType()
        guard body.keys.contains(SftpProperty.stop) else { return false }
        guard let value = body[SftpProperty.stop] as? NSNumber else { throw SftpError.invalidStopFlag }
        return value.boolValue
    }
    
    func validateSftpType() throws {
        guard self.isSftpPacket else { throw SftpError.wrongType }
    }
}


// MARK: -

class SftpFS: NSObject, NMSSHSessionDelegate {
    
    // MARK: Types
    
    enum SftpFSError: Error {
        case connectionFailed
        case authenticationFailed
    }
    
    
    // MARK: Properties
    
    let session: NMSSHSession
    
    
    // MARK: Init / Deinit
    
    init(host: String, user: String, password: String, path: String) throws {
        session = NMSSHSession.connect(toHost: host, withUsername: user)
        guard session.isConnected else { throw SftpFSError.connectionFailed }
        
        session.authenticate(byPassword: password)
        guard session.isAuthorized else { throw SftpFSError.authenticationFailed }
    }
    
    
    // MARK: Directory Contents
    
    public override func contentsOfDirectory(atPath path: String!) throws -> [Any] {
        if path == "/" {
            return []
        }
        else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT), userInfo: nil)
        }
    }
    
    
    // MARK: Getting Attributes
    
//    - (NSDictionary *)attributesOfItemAtPath:(NSString *)path userData:(id)userData error:(NSError **)error {
//        if ([self videoAtPath:path]) {
//        return [NSDictionary dictionary];
//        }
//        return nil;
//    }
//    
//    #pragma mark File Contents
//    
//    - (NSData *)contentsAtPath:(NSString *)path {
//    YTVideo* video = [self videoAtPath:path];
//    if (video) {
//    return [video xmlData];
//    }
//    return nil;
//    }
//    
//    #pragma mark FinderInfo and ResourceFork (Optional)
//    
//    - (NSDictionary *)finderAttributesAtPath:(NSString *)path
//    error:(NSError **)error {
//    NSDictionary* attribs = nil;
//    if ([self videoAtPath:path]) {
//    NSNumber* finderFlags = [NSNumber numberWithLong:kHasCustomIcon];
//    attribs = [NSDictionary dictionaryWithObject:finderFlags
//    forKey:kGMUserFileSystemFinderFlagsKey];
//    }
//    return attribs;
//    }
//    
//    - (NSDictionary *)resourceAttributesAtPath:(NSString *)path
//    error:(NSError **)error {
//    NSMutableDictionary* attribs = nil;
//    YTVideo* video = [self videoAtPath:path];
//    if (video) {
//    attribs = [NSMutableDictionary dictionary];
//    NSURL* url = [video playerURL];
//    if (url) {
//    [attribs setObject:url forKey:kGMUserFileSystemWeblocURLKey];
//    }
//    url = [video thumbnailURL];
//    if (url) {
//    NSImage* image = [[[NSImage alloc] initWithContentsOfURL:url] autorelease];
//    NSData* icnsData = [image icnsDataWithWidth:256];
//    [attribs setObject:icnsData forKey:kGMUserFileSystemCustomIconDataKey];
//    }
//    }
//    return attribs;
//    }
//    
//    #pragma mark Init and Dealloc
//    
//    - (id)initWithVideos:(NSDictionary *)videos {
//    if ((self = [super init])) {
//    videos_ = [videos retain];
//    }
//    return self;
//    }
//    - (void)dealloc {
//    [videos_ release];
//    [super dealloc];
//    }
//    
//    - (YTVideo *)videoAtPath:(NSString *)path {
//    NSArray* components = [path pathComponents];
//    if ([components count] != 2) {
//    return nil;
//    }
//    YTVideo* video = [videos_ objectForKey:[components objectAtIndex:1]];
//    return video;
//    }
    
}
