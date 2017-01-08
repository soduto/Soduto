//
//  DataPacket.swift
//  Soduto
//
//  Created by Admin on 2016-08-02.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation

public struct DataPacket: CustomStringConvertible {
    
    // MARK: Types
    
    public typealias Body = Dictionary<String, AnyObject>
    public typealias PayloadInfo = Dictionary<String, AnyObject>
    
    public enum Property: String {
        case id = "id"
        case type = "type"
        case body = "body"
        case payloadSize = "payloadSize"
        case payloadInfo = "payloadTransferInfo"
    }
    
    
    // MARK: Properties
    
    static let protocolVersion: UInt = 7
    
    var id: Int64
    var type: String
    var body: Body
    var payload: InputStream?
    var payloadSize: Int64? = nil
    var payloadInfo: PayloadInfo?
    var downloadTask: DownloadTask? = nil
    
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
    
    
    // MARK: Init / Deinit
    
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
        guard let obj = deserializedObj as? [String: AnyObject] else { return nil }
        let idString = obj[Property.id.rawValue] as? String
        let idNumber: Int64? = (idString != nil) ? Int64.init(idString!) : (obj[Property.id.rawValue] as? NSNumber)?.int64Value
        guard let id = idNumber else { return nil }
        guard let type = obj[Property.type.rawValue] as? String else { return nil }
        guard let body = obj[Property.body.rawValue] as? Body else { return nil }
        
        self.init(id: id, type: type, body: body)
        
        if let payloadInfo = obj[Property.payloadInfo.rawValue] as? PayloadInfo {
            self.payloadInfo = payloadInfo
            if let payloadSize = obj[Property.payloadSize.rawValue] as? NSNumber {
                self.payloadSize = payloadSize.int64Value > 0 ? payloadSize.int64Value : nil
            }
        }
    }
    
    private init(id: Int64, type: String, body: Body) {
        self.id = id
        self.type = type
        self.body = body
    }
    
    
    // MARK: Public methods
    
    func serialize() throws -> [UInt8] {
        return try serialize(options: JSONSerialization.WritingOptions())
    }
    
    func serialize(options: JSONSerialization.WritingOptions) throws -> [UInt8] {
        var dict: [String: AnyObject] = [
            Property.id.rawValue: NSNumber(value: self.id),
            Property.type.rawValue: self.type as AnyObject,
            Property.body.rawValue: self.body as AnyObject
        ]
        if self.hasPayload() {
            dict[Property.payloadSize.rawValue] = NSNumber(value: self.payloadSize ?? -1)
            dict[Property.payloadInfo.rawValue] = self.payloadInfo as AnyObject
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: options)
        var bytes = [UInt8](data)
        bytes.append(UInt8(ascii: "\n"))
        return bytes
    }
    
    public func hasPayload() -> Bool {
        return self.payload != nil || self.downloadTask != nil
    }
}



// MARK: - Identity packet

extension DataPacket {
    
    // MARK: Types
    
    public enum IdentityProperty: String {
        case deviceId = "deviceId"
        case deviceName = "deviceName"
        case deviceType = "deviceType"
        case incomingCapabilities = "incomingCapabilities"
        case outgoingCapabilities = "outgoingCapabilities"
        case protocolVersion = "protocolVersion"
        case tcpPort = "tcpPort"
    }
    
    public enum IdentityError: Error {
        case wrongType
        case invalidDeviceId
        case invalidDeviceName
        case invalidDeviceType
        case invalidProtocolVersion
        case invalidTCPPort
        case invalidIncomingCapabilities
        case invalidOutgoingCapabilities
    }
    
    
    // MARK: Properties
    
    public static let identityPacketType = "kdeconnect.identity"
    
    
    // MARK: Public static methods
    
    public static func identityPacket(config: HostConfiguration) -> DataPacket {
        return identityPacket(additionalProperties: nil, config: config)
    }
    
    public static func identityPacket(additionalProperties:DataPacket.Body?, config: HostConfiguration) -> DataPacket {
        assert(!config.incomingCapabilities.isEmpty || !config.outgoingCapabilities.isEmpty, "Empty capabilities for identity packet, probably something is wrong")
        
        var body: Body = [
            IdentityProperty.deviceId.rawValue: config.hostDeviceId as AnyObject,
            IdentityProperty.deviceName.rawValue: config.hostDeviceName as AnyObject,
            IdentityProperty.deviceType.rawValue: config.hostDeviceType.rawValue as AnyObject,
            IdentityProperty.protocolVersion.rawValue: NSNumber(value: DataPacket.protocolVersion),
            IdentityProperty.outgoingCapabilities.rawValue: Array(config.outgoingCapabilities) as AnyObject,
            IdentityProperty.incomingCapabilities.rawValue: Array(config.incomingCapabilities) as AnyObject
        ]
        if let properties = additionalProperties {
            for (key, value) in properties {
                body[key] = value
            }
        }
        let packet = DataPacket(type: identityPacketType, body: body)
        return packet
    }
    
    
    // MARK: Public methods
    
    public func getDeviceId() throws -> String {
        try self.validateIdentityType()
        guard let deviceId = body[IdentityProperty.deviceId.rawValue] as? String else { throw IdentityError.invalidDeviceId }
        return deviceId
    }
    
    public func getDeviceName() throws -> String {
        try self.validateIdentityType()
        guard let deviceName = body[IdentityProperty.deviceName.rawValue] as? String else { throw IdentityError.invalidDeviceName }
        return deviceName
    }
    
    public func getDeviceType() throws -> String {
        try self.validateIdentityType()
        guard let deviceType = body[IdentityProperty.deviceType.rawValue] as? String else { throw IdentityError.invalidDeviceType }
        return deviceType
    }
    
    public func getProtocolVersion() throws -> UInt {
        try self.validateIdentityType()
        guard let protocolVersion = body[IdentityProperty.protocolVersion.rawValue] as? NSNumber else { throw IdentityError.invalidProtocolVersion }
        return protocolVersion.uintValue
    }
    
    public func getTCPPort() throws -> UInt16 {
        try self.validateIdentityType()
        guard let tcpPort = body[IdentityProperty.tcpPort.rawValue] as? NSNumber else { throw IdentityError.invalidTCPPort }
        return tcpPort.uint16Value
    }
    
    public func getIncomingCapabilities() throws -> Set<Service.Capability> {
        try self.validateIdentityType()
        guard let capabilities = body[IdentityProperty.incomingCapabilities.rawValue] as? [String] else { throw IdentityError.invalidIncomingCapabilities }
        return Set(capabilities)
    }
    
    public func getOutgoingCapabilities() throws -> Set<Service.Capability> {
        try self.validateIdentityType()
        guard let capabilities = body[IdentityProperty.outgoingCapabilities.rawValue] as? [String] else { throw IdentityError.invalidOutgoingCapabilities }
        return Set(capabilities)
    }
    
    public func validateIdentityType() throws {
        guard type == DataPacket.identityPacketType else { throw IdentityError.wrongType }
    }
}
