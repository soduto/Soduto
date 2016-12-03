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
public class ShareService: Service, DownloadTaskDelegate {
    
    // MARK: Types
    
    private enum ActionId: ServiceAction.Id {
        case shareFile
    }
    
    private struct DownloadInfo {
        let task: DownloadTask
        let url: URL
        init(task: DownloadTask, url: URL) {
            self.task = task
            self.url = url
        }
    }
    
    
    // MARK: Service properties
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.sharePacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.sharePacketType ])
    
    private var downloadInfos: [DownloadInfo] = []
    
    
    // MARK: Service methods
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isSharePacket else { return false }
        
        Swift.print("ShareService.handleDataPacket:fromDevice:onConnection: \(dataPacket.description) \(device) \(connection)");
        
        do {
            if let downloadTask = dataPacket.downloadTask {
                let fileName = try dataPacket.getFilename()
                try self.downloadFile(downloadTask: downloadTask, fileName: fileName)
            }
            else if let text = try dataPacket.getText() {
                let directory = NSTemporaryDirectory()
                let fileName = try dataPacket.getFilename() ?? "\(UUID().uuidString).txt"
                let fullURL = URL(fileURLWithPath: fileName, relativeTo: URL(fileURLWithPath: directory, isDirectory: true))
                try text.write(to: fullURL, atomically: true, encoding: .utf8)
                NSWorkspace.shared().open(fullURL)
            }
            else if let urlString = try dataPacket.getUrl(), let url = URL(string: urlString) {
                NSWorkspace.shared().open(url)
            }
            else {
                Swift.print("Unknown shared content")
            }
        }
        catch {
            Swift.print("Error while handling share packet: \(error)")
        }
        
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
                self.uploadFile(url: url, to: device)
            }
            break
        }
        
    }
    
    
    // MARK: DownloadTaskDelegate
    
    public func downloadTask(_ task: DownloadTask, finishedWithSuccess success: Bool) {
        Swift.print("ShareService.downloadTask:finishedWithSuccess: \(task) \(success)")
        
        guard let info = self.downloadInfos.first(where: { $0.task === task }) else { return }
        Swift.print("File downloaded: \(info.url.absoluteString)")
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
    
    private func uploadFile(url: URL, to device: Device) {
        guard let filename = url.pathComponents.last else { return }
        guard let stream = InputStream(url: url) else { return }
        
        let fileSize = self.fileSize(path: url.path)
        device.send(DataPacket.sharePacket(fileStream: stream, fileSize: fileSize, fileName: filename))
    }
    
    private func downloadFile(downloadTask: DownloadTask, fileName: String?) throws {
        let url = try self.destinationFileUrl(fileName: fileName)
        
        guard let stream = OutputStream(url: url, append: false) else { return }
        
        self.downloadInfos.append(DownloadInfo(task: downloadTask, url: url))
        downloadTask.delegate = self
        downloadTask.start(withStream: stream)
    }
    
    private func destinationFileUrl(fileName: String?) throws -> URL {
        let manager = FileManager()
        let fileUrl = URL(fileURLWithPath: "").appendingPathComponent(fileName ?? "\(UUID().uuidString)", isDirectory: false).appendingPathExtension("part")
        let dirUrl = try manager.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: fileUrl, create: true)
        return URL(fileURLWithPath: fileUrl.relativeString, relativeTo: dirUrl)
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
