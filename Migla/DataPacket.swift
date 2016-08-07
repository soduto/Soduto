//
//  DataPacket.swift
//  Migla
//
//  Created by Admin on 2016-08-02.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public struct DataPacket: CustomStringConvertible {
    
    typealias Body = Dictionary<String, AnyObject>
    
    enum PacketType: String {
        case Identity = "kdeconnect.identity"
    }
    
    enum BodyProperty: String {
        case ProtocolVerion = "protocolVersion"
    }
    
    
    
    static let protocolVersion = 7
    
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
    
    init?( json: inout [UInt8]) {
        let data = Data(bytesNoCopy: &json, count: json.count, deallocator: .none)
        let deserializedObj = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
        guard let obj = deserializedObj,
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
            "type": self.type,
            "body": self.body
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: options)
        var bytes = [UInt8](data)
        bytes.append(UInt8(ascii: "\n"))
        return bytes
    }
    
    
    
    static func identity() -> DataPacket {
        let outgoingCapabilities: [String] = ["kdeconnect.ping"]
        let incomingCapabilities: [String] = ["kdeconnect.ping"]
        let body: Body = [
            "deviceId": "12345678901234567890",
            "deviceName": "Migla",
            "deviceType": "desktop",
            "protocolVersion": NSNumber(value: DataPacket.protocolVersion),
//            "tcpPort": ConnectionProvider.port,
            "outgoingCapabilities": outgoingCapabilities,
            "incomingCapabilities": incomingCapabilities
        ]
        let packet = DataPacket(type: PacketType.Identity.rawValue, body: body)
        return packet
    }
}
