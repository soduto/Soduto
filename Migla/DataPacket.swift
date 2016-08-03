//
//  DataPacket.swift
//  Migla
//
//  Created by Admin on 2016-08-02.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public class DataPacket: CustomStringConvertible {
    
    typealias Body = Dictionary<String, AnyObject>
    
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
    
    
    convenience init(type: String, body: Body) {
        let id = Int64(Date().timeIntervalSince1970 * 1000)
        self.init(id: id, type: type, body: body)
    }
    
    convenience init?( json: inout [UInt8]) {
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
        return [UInt8](data)
    }
}
