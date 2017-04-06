//
//  ClipboardService.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-11-30.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import Cocoa

/// Service providing clipboard content sharing between devices
///
/// When the clipboard changes, it sends a package with type kdeconnect.clipboard
/// and the field "content" (string) containing the new clipboard content.
///
/// When it receivest a package of the same kind, it should update the system
/// clipboard with the received content, so the clipboard in both devices always
/// have the same content.
///
/// This plugin is symmetric to its counterpart in the other device: both have the
/// same behaviour.
public class ClipboardService: Service {
    
    // MARK: Properties
    
    private static let monitoringInterval: TimeInterval = 0.5
    
    private var monitoringTimer: Timer? = nil
    private var lastChangeCount: Int = NSPasteboard.general().changeCount
    private var lastExternalChangeCount: Int = -1
    private var lastExternalChangeDevice: Device? = nil
    private var devices: [Device] = []
    
    
    // MARK: Service
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.clipboardPacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.clipboardPacketType ])
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isClipboardPacket else { return false }
        guard let contents = try? dataPacket.getContent() else { return true }
        
        self.lastExternalChangeDevice = device
        self.lastExternalChangeCount = NSPasteboard.general().clearContents()
        NSPasteboard.general().writeObjects([ contents as NSString ])
        
        return true
    }
    
    public func setup(for device: Device) {
        guard !self.devices.contains(where: { $0.id == device.id }) else { return }
        
        self.devices.append(device)
        
        if self.monitoringTimer == nil {
            self.startMonitoring()
        }
    }
    
    public func cleanup(for device: Device) {
        guard let index = self.devices.index(where: { $0.id == device.id }) else { return }
        
        self.devices.remove(at: index)
        
        if self.devices.count == 0 {
            self.stopMonitoring()
        }
    }
    
    public func actions(for device: Device) -> [ServiceAction] {
        // No supported actions
        return []
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        // No supported actions
    }
    
    
    // MARK: Private methods
    
    private func startMonitoring() {
        let interval = ClipboardService.monitoringInterval
        self.monitoringTimer = Timer.compatScheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }
    
    private func stopMonitoring() {
        self.monitoringTimer?.invalidate()
        self.monitoringTimer = nil
    }
    
    private func checkPasteboard() {
        guard NSPasteboard.general().changeCount != self.lastChangeCount else { return }
        guard let items = NSPasteboard.general().readObjects(forClasses: [ NSString.self ], options: nil) else { return }
        guard items.count > 0 else { return }
        guard let content = items[0] as? String else { return }
        
        self.lastChangeCount = NSPasteboard.general().changeCount
        
        for device in self.devices {
            guard !(self.lastChangeCount == self.lastExternalChangeCount && self.lastExternalChangeDevice === device) else { continue }
            device.send(DataPacket.clipboardPacket(withContent: content))
        }
        
    }
}


// MARK: DataPacket (Clipboard)

/// Clipboard service data packet utilities
fileprivate extension DataPacket {
    
    // MARK: Types
    
    enum ClipboardError: Error {
        case wrongType
        case invalidContent
    }
    
    enum ClipboardProperty: String {
        case content = "content"
    }
    
    
    // MARK: Properties
    
    static let clipboardPacketType = "kdeconnect.clipboard"
    
    var isClipboardPacket: Bool { return self.type == DataPacket.clipboardPacketType }
    
    
    // MARK: Public static methods
    
    static func clipboardPacket(withContent content: String) -> DataPacket {
        return DataPacket(type: clipboardPacketType, body: [
            ClipboardProperty.content.rawValue: content as AnyObject
        ])
    }
    
    
    // MARK: Public methods
    
    func getContent() throws -> String {
        try self.validateClipboardType()
        guard body.keys.contains(ClipboardProperty.content.rawValue) else { throw ClipboardError.invalidContent }
        guard let value = body[ClipboardProperty.content.rawValue] as? String else { throw ClipboardError.invalidContent }
        return value
    }
    
    func validateClipboardType() throws {
        guard self.isClipboardPacket else { throw ClipboardError.wrongType }
    }
}

