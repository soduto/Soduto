//
//  SFTPService.swift
//  Soduto
//
//  Created by Giedrius on 2017-02-20.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

import Foundation
import Cocoa
import CleanroomLogger

/// This service receives packages with type "kdeconnect.sftp" and reads the
/// following fields:
///
/// - ip (string): ip of the curretly active network on device
/// - port (string): port where sftp server starts
/// - user (string): username to connect to sftp server
/// - password (string): one session password to access sftp server
/// - path (string): root directory to access device filesystem
///
/// This service sends packages with type "kdeconnect.sftp" and fills the
/// following fields:
///
/// startBrowsing (boolean): tell device to start sftp server and notify desktop
public class SftpService: NSObject, Service, NSWindowDelegate {
    
    // MARK: Types
    
    enum ActionId: ServiceAction.Id {
        case browseFiles
    }
    
    
    // MARK: Properties
    
    public static let requestTimeoutInterval: TimeInterval = 20.0
    
    private var requestTimers: [Device.Id:Timer] = [:]
    private var loadingWindowControllers: [Device.Id:LoadingWindowController] = [:]
    
    
    // MARK: Service
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.sftpPacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.sftpRequestPacketType ])
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isSftpPacket else { return false }
        handleSftpPacket(dataPacket, from: device)
        return true
    }
    
    public func setup(for device: Device) {}
    
    public func cleanup(for device: Device) {
        hideLoadingMessage(for: device)
        if let timer = self.requestTimers.removeValue(forKey: device.id) {
            timer.invalidate()
            failedToActivateSftp(for: device)
        }
    }
    
    public func actions(for device: Device) -> [ServiceAction] {
        guard device.incomingCapabilities.contains(DataPacket.sftpRequestPacketType) else { return [] }
        
        return [
            ServiceAction(id: ActionId.browseFiles.rawValue, title: "Browse files", description: "Browse device files in Finder", service: self, device: device)
        ]
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        guard let actionId = ActionId(rawValue: id) else { return }
        
        switch actionId {
        case .browseFiles:
            self.startBrowsing(for: device)
            break
        }
    }
    
    
    // MARK: Private methods
    
    private func startBrowsing(for device: Device) {
        activatingSftp(for: device)
        device.send(DataPacket.sftpStartBrowsingPacket())
    }
    
    private func activatingSftp(for device: Device) {
        discardRequestTimer(for: device)
        showLoadingMessage(for: device)
        self.requestTimers[device.id] = Timer.compatScheduledTimer(withTimeInterval: type(of: self).requestTimeoutInterval, repeats: false) { [weak self] _ in
            self?.failedToActivateSftp(for: device)
        }
    }
    
    private func failedToActivateSftp(for device: Device) {
        discardRequestTimer(for: device)
        hideLoadingMessage(for: device)
        
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Browse failed", comment: "")
        alert.informativeText = NSString(format: NSLocalizedString("Failed to initialize browse session for %@.", comment: "") as NSString, device.name) as String
        alert.runModal()
    }
    
    private func succeededToActivateSftp(for device: Device, withEndPoint url: URL) {
        discardRequestTimer(for: device)
        hideLoadingMessage(for: device)
        launchBrowser(for: url)
    }
    
    private func handleSftpPacket(_ dataPacket: DataPacket, from device: Device) {
        guard dataPacket.isSftpPacket else { assertionFailure("Expected Sftp data packet"); return }
        guard self.requestTimers[device.id] != nil else { return } // Not waiting or maybe too late
        
        discardRequestTimer(for: device)
        
        do {
            let stop = try dataPacket.getStopFlag()
            if stop {
                // SFTP service has stopped on device. Currently dont have anything to do in such situation.
                // Maybe we should inform Browser about this?
            }
            else {
                guard let ip = try dataPacket.getIp() else { return }
                guard let port = try dataPacket.getPort() else { return }
                guard let user = try dataPacket.getUser() else { return }
                guard let password = try dataPacket.getPassword() else { return }
                guard let path = try dataPacket.getPath() else { return }
                
                let urlComponents = NSURLComponents()
                urlComponents.scheme = "sftp"
                urlComponents.host = ip
                urlComponents.port = port as NSNumber
                urlComponents.user = user
                urlComponents.password = password
                urlComponents.path = path
                urlComponents.fragment = device.name
                guard let url = urlComponents.url else { return }
                
                succeededToActivateSftp(for: device, withEndPoint: url)
            }
        }
        catch {
            Log.error?.message("Failed to handle SFTP data packet: \(error)")
            failedToActivateSftp(for: device)
        }
    }
    
    private func discardRequestTimer(for device: Device) {
        discardRequestTimer(forDeviceWithId: device.id)
    }
    
    private func discardRequestTimer(forDeviceWithId deviceId: Device.Id) {
        let timer = self.requestTimers.removeValue(forKey: deviceId)
        timer?.invalidate()
    }
    
    private func showLoadingMessage(for device: Device) {
        if loadingWindowControllers[device.id] != nil {
            loadingWindowControllers[device.id]?.showWindow(self)
            return
        }
        
        let controller = LoadingWindowController.loadController()
        controller.titleLabel.stringValue = String(format: NSLocalizedString("Initializing browse session for %@...", comment: ""), device.name)
        controller.hintLabel.stringValue = NSLocalizedString("Stop initializing", comment: "Browse session initialization")
        controller.dismissHandler = { [weak self] controller in
            guard let entry = self?.loadingWindowControllers.first(where: { $0.value === controller }) else { return }
            self?.discardRequestTimer(forDeviceWithId: entry.key)
            _ = self?.loadingWindowControllers.removeValue(forKey: entry.key)
        }
        self.loadingWindowControllers[device.id] = controller
        
        controller.showWindow(self)
    }
    
    private func hideLoadingMessage(for device: Device) {
        self.loadingWindowControllers[device.id]?.dismissController(self)
    }
    
    private func launchBrowser(for url: URL) {
        do {
            let appUrl = Bundle.main.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Helpers")
                .appendingPathComponent("SodutoBrowser.app", isDirectory: false)
            let files: [URL] = [url]
            let options: NSWorkspaceLaunchOptions = NSWorkspaceLaunchOptions.default
            _ = try NSWorkspace.shared().open(files, withApplicationAt: appUrl, options: options, configuration: [:])
        }
        catch {
            Log.error?.message("Could not launch SodutoBrowser: \(error)")
        }
    }
}


// MARK: - DataPacket (SFTP)

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
