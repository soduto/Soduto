//
//  DataPacket.swift
//  Migla
//
//  Created by Admin on 2016-08-02.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public struct DataPacket: CustomStringConvertible {
    
    public typealias Body = Dictionary<String, AnyObject>
    
    
    
    static let protocolVersion: UInt = 7
    
    var id: Int64
    var type: String
    var body: Body
    
    public var description: String {
        do {
            let bytes = try self.serialize(options: .prettyPrinted)
            let str = String(bytes: bytes, encoding: String.Encoding.utf8)
            if let str = str {
                return str
            }
            else {
                return "\(bytes)"
            }
        }
        catch {
            return "Could not serialize data packet: \(error)"
        }
        
    }
    
    
    
    init(type: String, body: Body) {
        let id = Int64(Date().timeIntervalSince1970 * 1000)
        self.init(id: id, type: type, body: body)
    }
    
    init?(json: inout [UInt8]) {
        let data = Data(bytesNoCopy: &json, count: json.count, deallocator: .none)
        self.init(data: data)
    }
    
    init?(data: Data) {
        let deserializedObj = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
        guard let obj = deserializedObj as? [String: AnyObject],
            let id = obj["id"] as? NSNumber,
            let type = obj["type"] as? String,
            let body = obj["body"] as? [String: AnyObject] else {
                return nil
        }
        self.init(id: id.int64Value, type: type, body: body)
    }
    
    private init(id: Int64, type: String, body: Body) {
        self.id = id
        self.type = type
        self.body = body
    }
    
    
    
    func serialize() throws -> [UInt8] {
        return try serialize(options: JSONSerialization.WritingOptions())
    }
    
    func serialize(options: JSONSerialization.WritingOptions) throws -> [UInt8] {
        let dict: [String: AnyObject] = [
            "id": NSNumber(value: self.id),
            "type": self.type as AnyObject,
            "body": self.body as AnyObject
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: options)
        var bytes = [UInt8](data)
        bytes.append(UInt8(ascii: "\n"))
        return bytes
    }
}



// Identity packet

extension DataPacket {
    
    public static let IdentityPacketType = "kdeconnect.identity"
    
    public enum IdentityProperty: String {
        case DeviceId = "deviceId"
        case DeviceName = "deviceName"
        case DeviceType = "deviceType"
        case IncomingCapabilities = "incomingCapabilities"
        case OutgoingCapabilities = "outgoingCapabilities"
        case ProtocolVersion = "protocolVersion"
        case TCPPort = "tcpPort"
    }
    
    public enum IdentityError: Error {
        case WrongType
        case InvalidDeviceId
        case InvalidDeviceName
        case InvalidDeviceType
        case InvalidProtocolVersion
        case InvalidTCPPort
        case InvalidIncomingCapabilities
        case InvalidOutgoingCapabilities
    }
    
    
    
    public static func identity(config: HostConfiguration) -> DataPacket {
        return identity(additionalProperties: nil, config: config)
    }
    
    public static func identity(additionalProperties:DataPacket.Body?, config: HostConfiguration) -> DataPacket {
        var body: Body = [
            IdentityProperty.DeviceId.rawValue: config.hostDeviceId as AnyObject,
            IdentityProperty.DeviceName.rawValue: config.hostDeviceName as AnyObject,
            IdentityProperty.DeviceType.rawValue: config.hostDeviceType.rawValue as AnyObject,
            IdentityProperty.ProtocolVersion.rawValue: NSNumber(value: DataPacket.protocolVersion),
            IdentityProperty.OutgoingCapabilities.rawValue: Array(config.outgoingCapabilities) as AnyObject,
            IdentityProperty.IncomingCapabilities.rawValue: Array(config.incomingCapabilities) as AnyObject
        ]
        if let properties = additionalProperties {
            for (key, value) in properties {
                body[key] = value
            }
        }
        let packet = DataPacket(type: IdentityPacketType, body: body)
        return packet
    }
    
    
    
    
    public func getDeviceId() throws -> String {
        try self.validateIdentityType()
        guard let deviceId = body[IdentityProperty.DeviceId.rawValue] as? String else { throw IdentityError.InvalidDeviceId }
        return deviceId
    }
    
    public func getDeviceName() throws -> String {
        try self.validateIdentityType()
        guard let deviceName = body[IdentityProperty.DeviceName.rawValue] as? String else { throw IdentityError.InvalidDeviceName }
        return deviceName
    }
    
    public func getDeviceType() throws -> String {
        try self.validateIdentityType()
        guard let deviceType = body[IdentityProperty.DeviceType.rawValue] as? String else { throw IdentityError.InvalidDeviceType }
        return deviceType
    }
    
    public func getProtocolVersion() throws -> UInt {
        try self.validateIdentityType()
        guard let protocolVersion = body[IdentityProperty.ProtocolVersion.rawValue] as? NSNumber else { throw IdentityError.InvalidProtocolVersion }
        return protocolVersion.uintValue
    }
    
    public func getTCPPort() throws -> UInt16 {
        try self.validateIdentityType()
        guard let tcpPort = body[IdentityProperty.TCPPort.rawValue] as? NSNumber else { throw IdentityError.InvalidTCPPort }
        return tcpPort.uint16Value
    }
    
    public func getIncomingCapabilities() throws -> Set<Service.Capability> {
        try self.validateIdentityType()
        guard let capabilities = body[IdentityProperty.IncomingCapabilities.rawValue] as? [String] else { throw IdentityError.InvalidIncomingCapabilities }
        return Set(capabilities)
    }
    
    public func getOutgoingCapabilities() throws -> Set<Service.Capability> {
        try self.validateIdentityType()
        guard let capabilities = body[IdentityProperty.OutgoingCapabilities.rawValue] as? [String] else { throw IdentityError.InvalidOutgoingCapabilities }
        return Set(capabilities)
    }
    
    public func validateIdentityType() throws {
        guard type == DataPacket.IdentityPacketType else { throw IdentityError.WrongType }
    }
}
