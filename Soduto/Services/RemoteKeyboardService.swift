//
//  RemoteKeyboardService.swift
//  Soduto
//
//  Created by Giedrius on 2017-05-21.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa
import CleanroomLogger

public class RemoteKeyboardService: Service {
    
    // MARK: Service
    
    public static let serviceId: Service.Id = "com.soduto.services.remotekeyboard"
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.remoteKeyboardRequestPacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.remoteKeyboardEchoPacketType ])
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
    
        guard dataPacket.isRemoteKeyboardRequestPacket else { return false }
        
        do {
            if !(try dataPacket.getSendAckFlag()) {
                let body: DataPacket.Body = [
                    DataPacket.RemoteKeyboardProperty.key: "a" as AnyObject,
                    DataPacket.RemoteKeyboardProperty.sendAck: true as AnyObject
                ]
                let keyPacket = DataPacket(type: DataPacket.remoteKeyboardRequestPacketType, body: body)
                device.send(keyPacket)
            }
            
            guard try dataPacket.getSendAckFlag() else { return true }
            
            device.send(try DataPacket.remoteKeyboardEchoPacket(for: dataPacket))
        }
        catch {
            Log.error?.message("Failed handling remote keyboard data packet: \(error).")
        }
        
        return true
    }
    
    public func setup(for device: Device) {}
    
    public func cleanup(for device: Device) {}
    
    public func actions(for device: Device) -> [ServiceAction] {
        // No supported actions
        return []
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        // No supported actions
    }
}


// MARK: DataPacket (Remote keyboard)

/// Remote keyboard service data packet utilities
fileprivate extension DataPacket {
    
    // MARK: Types
    
    enum RemoteKeyboardError: Error {
        case wrongType
        case invalidSendAckFlag
        case invalidIsAckFlag
        case invalidKey
        case invalidSpecialKey
        case invalidShiftFlag
        case invalidCtrlFlag
        case invalidAltFlag
    }
    
    struct RemoteKeyboardProperty {
        public static let sendAck = "sendAck"
        public static let isAck = "isAck"
        public static let key = "key"
        public static let specialKey = "specialKey"
        public static let shift = "shift"
        public static let ctrl = "ctrl"
        public static let alt = "alt"
    }
    
    
    // MARK: Properties
    
    static let remoteKeyboardRequestPacketType = "kdeconnect.mousepad.request"
    static let remoteKeyboardEchoPacketType = "kdeconnect.mousepad.echo"
    
    var isRemoteKeyboardRequestPacket: Bool { return self.type == DataPacket.remoteKeyboardRequestPacketType }
    var isRemoteKeyboardEchoPacket: Bool { return self.type == DataPacket.remoteKeyboardEchoPacketType }
    
    
    // MARK: Public static methods
    
    static func remoteKeyboardEchoPacket(for dataPacket: DataPacket) throws -> DataPacket {
        assert(dataPacket.isRemoteKeyboardRequestPacket, "Expected packet type \(remoteKeyboardEchoPacketType), but got \(dataPacket.type)")
        var body: Body = [
            RemoteKeyboardProperty.isAck: true as AnyObject,
            RemoteKeyboardProperty.key: try dataPacket.getKey() as AnyObject
        ]
        if let specialKey = try dataPacket.getSpecialKey() { body[RemoteKeyboardProperty.specialKey] = specialKey as AnyObject }
        if let shift = try dataPacket.getShiftFlag() { body[RemoteKeyboardProperty.shift] = shift as AnyObject }
        if let ctrl = try dataPacket.getCtrlFlag() { body[RemoteKeyboardProperty.ctrl] = ctrl as AnyObject }
        if let alt = try dataPacket.getAltFlag() { body[RemoteKeyboardProperty.alt] = alt as AnyObject }
        return DataPacket(type: remoteKeyboardEchoPacketType, body: body)
    }
    
    
    // MARK: Public methods
    
    func getSendAckFlag() throws -> Bool {
        try self.validateRemoteKeyboardRequestType()
        guard body.keys.contains(RemoteKeyboardProperty.sendAck) else { return false }
        guard let value = body[RemoteKeyboardProperty.sendAck] as? NSNumber else { throw RemoteKeyboardError.invalidSendAckFlag }
        return value.boolValue
    }
    
    func getKey() throws -> String {
        try self.validateRemoteKeyboardType()
        guard body.keys.contains(RemoteKeyboardProperty.key) else { throw RemoteKeyboardError.invalidKey }
        guard let value = body[RemoteKeyboardProperty.key] as? String else { throw RemoteKeyboardError.invalidKey }
        return value
    }
    
    func getSpecialKey() throws -> Int? {
        try self.validateRemoteKeyboardType()
        guard body.keys.contains(RemoteKeyboardProperty.specialKey) else { return nil }
        guard let value = body[RemoteKeyboardProperty.specialKey] as? NSNumber else { throw RemoteKeyboardError.invalidSpecialKey }
        return value.intValue
    }
    
    func getShiftFlag() throws -> Bool? {
        try self.validateRemoteKeyboardType()
        guard body.keys.contains(RemoteKeyboardProperty.shift) else { return nil }
        guard let value = body[RemoteKeyboardProperty.shift] as? NSNumber else { throw RemoteKeyboardError.invalidShiftFlag }
        return value.boolValue
    }
    
    func getCtrlFlag() throws -> Bool? {
        try self.validateRemoteKeyboardType()
        guard body.keys.contains(RemoteKeyboardProperty.ctrl) else { return nil }
        guard let value = body[RemoteKeyboardProperty.ctrl] as? NSNumber else { throw RemoteKeyboardError.invalidCtrlFlag }
        return value.boolValue
    }
    
    func getAltFlag() throws -> Bool? {
        try self.validateRemoteKeyboardType()
        guard body.keys.contains(RemoteKeyboardProperty.alt) else { return nil }
        guard let value = body[RemoteKeyboardProperty.alt] as? NSNumber else { throw RemoteKeyboardError.invalidAltFlag }
        return value.boolValue
    }
    
    func validateRemoteKeyboardRequestType() throws {
        guard self.isRemoteKeyboardRequestPacket else { throw RemoteKeyboardError.wrongType }
    }
    
    func validateRemoteKeyboardEchoType() throws {
        guard self.isRemoteKeyboardEchoPacket else { throw RemoteKeyboardError.wrongType }
    }
    
    func validateRemoteKeyboardType() throws {
        guard self.isRemoteKeyboardRequestPacket || self.isRemoteKeyboardEchoPacket else { throw RemoteKeyboardError.wrongType }
    }
}

