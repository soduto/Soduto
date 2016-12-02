//
//  ShareService.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-12-02.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import Cocoa

/// Service providing capability to send end receive files, links, etc
///
/// It receives a packages with type kdeconnect.share.request. If they have a payload
/// attached, it will download it as a file with the filename set in the field
/// "filename" (string). If that field is not set it should generate a filename.
///
/// If the content transferred is text, it can be sent in a field "text" (string)
/// instead of an attached payload. In that case, this plugin opens a text editor
/// with the content instead of saving it as a file.
///
/// If the content transferred is a url, it can be sent in a field "url" (string).
/// In that case, this plugin opens that url in the default browser.
public class ShareService: Service {
    
    // MARK: Types
    
    enum ActionId: ServiceAction.Id {
        case shareFile
    }
    
    
    // MARK: Service properties
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.sharePacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.sharePacketType ])
    
    
    // MARK: Service methods
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isSharePacket else { return false }
        
        // TODO: implement proper handling of incoming packets
        Swift.print("handleDataPacket:fromDevice:onConnection: \(dataPacket.description) \(device) \(connection)");
        
        return true
    }
    
    public func setup(for device: Device) {}
    
    public func cleanup(for device: Device) {}
    
    public func actions(for device: Device) -> [ServiceAction] {
        guard device.incomingCapabilities.contains(DataPacket.sharePacketType) else { return [] }
        guard device.state == .paired else { return [] }
        
        return [
            ServiceAction(id: ActionId.shareFile.rawValue, title: "Share a file", description: "Send a file with remote device", service: self, device: device)
        ]
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        guard let actionId = ActionId(rawValue: id) else { return }
        guard device.state == .paired else { return }
        
        switch actionId {
        case .shareFile:
            NSApp.activate(ignoringOtherApps: true)
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.allowsMultipleSelection = false
            openPanel.begin { result in
                guard result == NSFileHandlingPanelOKButton else { return }
                guard let url = openPanel.url else { return }
                guard let filename = url.pathComponents.last else { return }
                guard let stream = InputStream(url: url) else { return }
                
                stream.open()
                
                let fileSize = self.fileSize(path: url.path)
                device.send(DataPacket.sharePacket(fileStream: stream, fileSize: fileSize, fileName: filename))
            }
            break
        }
        
    }
    
    
    // MARK: Private methods
    
    private func fileSize(path: String) -> Int64? {
        var fileSize : Int64? = nil
        
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: path)
            fileSize = attr[FileAttributeKey.size] as? Int64
        } catch {
            print("Error: \(error)")
        }
        
        return fileSize
    }
}


// MARK: DataPacket (Share)

/// Ping service data packet utilities
public extension DataPacket {
    
    // MARK: Types
    
    enum ShareError: Error {
        case wrongType
        case invalidFilename
        case invalidText
        case invalidUrl
    }
    
    enum ShareProperty: String {
        case filename = "filename"
        case text = "text"
        case url = "url"
    }
    
    
    // MARK: Properties
    
    public static let sharePacketType = "kdeconnect.share.request"
    
    public var isSharePacket: Bool { return self.type == DataPacket.sharePacketType }
    
    
    // MARK: Public methods
    
    public static func sharePacket(fileStream: InputStream, fileSize: Int64?, fileName: String?) -> DataPacket {
        var body: Body = [:]
        if let filename = fileName {
            body[ShareProperty.filename.rawValue] = filename as AnyObject
        }
        var packet = DataPacket(type: sharePacketType, body: body)
        packet.payload = fileStream
        packet.payloadSize = fileSize
        return packet
    }
    
    public func getFilename() throws -> String? {
        try self.validateShareType()
        guard body.keys.contains(ShareProperty.filename.rawValue) else { return nil }
        guard let value = body[ShareProperty.filename.rawValue] as? String else { throw ShareError.invalidFilename }
        return value
    }
    
    public func getText() throws -> String? {
        try self.validateShareType()
        guard body.keys.contains(ShareProperty.text.rawValue) else { return nil }
        guard let value = body[ShareProperty.text.rawValue] as? String else { throw ShareError.invalidText }
        return value
    }
    
    public func getUrl() throws -> String? {
        try self.validateShareType()
        guard body.keys.contains(ShareProperty.url.rawValue) else { return nil }
        guard let value = body[ShareProperty.url.rawValue] as? String else { throw ShareError.invalidUrl }
        return value
    }
    
    public func validateShareType() throws {
        guard self.isSharePacket else { throw ShareError.wrongType }
    }
}
