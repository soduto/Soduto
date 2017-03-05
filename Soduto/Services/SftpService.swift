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
public class SftpService: Service, SftpMounterDelegate {
    
    // MARK: Types
    
    enum ActionId: ServiceAction.Id {
        case browseFiles
    }
    
    
    // MARK: Properties
    
    private var mounters: [Device.Id:SftpMounter] = [:]
    
    
    // MARK: Service
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.sftpPacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.sftpRequestPacketType ])
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        guard let mounter = mounters[device.id] else { return false }
        return mounter.handleDataPacket(dataPacket)
    }
    
    public func setup(for device: Device) {}
    
    public func cleanup(for device: Device) {
        if let mounter = self.mounters.removeValue(forKey: device.id) {
            mounter.unmount()
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
    
    
    // MARK: SftpMounterDelegate
    
    func sftpMounterDidMount(_ mounter: SftpMounter) {
        Log.debug?.message("Did mount SFTP volume for device \(mounter.device.id)")
        NSWorkspace.shared().open(mounter.mountPoint)
    }
    
    func sftpMounterDidUnmount(_ mounter: SftpMounter) {
        Log.debug?.message("Did unmount SFTP volume for device \(mounter.device.id)")
    }
    
    func sftpMounterDidFailToMount(_ mounter: SftpMounter) {
        Log.debug?.message("Did fail to mount SFTP volume for device \(mounter.device.id)")
    }
    
    
    // MARK: Private methods
    
    private func startBrowsing(for device: Device) {
        _ = self.mount(for: device)
    }
    
    private func mount(for device: Device) -> SftpMounter {
        let mounter = mounters[device.id] ?? SftpMounter(device: device)
        
        guard !mounter.isMounted else { return mounter }
        
        mounter.delegate = self
        mounters[device.id] = mounter
        mounter.mount()
        return mounter
    }
}
