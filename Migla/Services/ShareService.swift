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
public class ShareService: Service, DownloadTaskDelegate, UserNotificationActionHandler {
    
    // MARK: Types
    
    private enum ShareError: Error {
        case partFileRenameFailed
    }
    
    private enum ActionId: ServiceAction.Id {
        case shareFile
    }
    
    private enum NotificationProperty: String {
        case downloadedFileUrl = "com.migla.ShareService.download.url"
    }
    
    private struct DownloadInfo {
        let task: DownloadTask
        let fileName: String
        let url: URL
        init(task: DownloadTask, fileName: String, url: URL) {
            self.task = task
            self.fileName = fileName
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
                self.downloadFile(fileName, usingTask: downloadTask, from: device)
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
        
        guard let index = self.downloadInfos.index(where: { $0.task === task }) else { return }
        let info = self.downloadInfos.remove(at: index)
        
        do {
            if success {
                let finalUrl = try self.renamePartFile(url: info.url, to: info.fileName)
                self.showDownloadFinishNotification(fileName: info.fileName, downloadTask: task, succeeded: success, finalUrl: finalUrl)
            }
            else {
                self.showDownloadFinishNotification(fileName: info.fileName, downloadTask: task, succeeded: success)
            }
        }
        catch {
            self.showDownloadFinishNotification(fileName: info.fileName, downloadTask: task, succeeded: false)
        }
    }
    
    
    // MARK: USerNotificationsActionHandler
    
    public static func handleAction(for notification: NSUserNotification, context: UserNotificationContext) {
        guard let urlString = notification.userInfo?[NotificationProperty.downloadedFileUrl.rawValue] as? String else { return }
        guard let url = URL(string: urlString) else { return }
        
        NSWorkspace.shared().open(url)
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
    
    private func downloadFile(_ fileName: String?, usingTask task: DownloadTask, from device: Device) {
        // FIXME: handle nil fileName correctly. The commented approach is wrong because download easily 
        // expires - needs to start downloading in background while asking for file name
        
//        let askFileLocation = {
//            NSApp.activate(ignoringOtherApps: true)
//            let panel = NSSavePanel()
//            panel.message = "Select save location for download received form device \"\(device.name)\""
//            panel.nameFieldStringValue = fileName ?? ""
//            panel.begin { result in
//                guard result == NSFileHandlingPanelOKButton else { return }
//                guard let url = panel.url else { return }
//                self.downloadFile(downloadTask: task, fileName: url.lastPathComponent, destUrl: url)
//            }
//        }
        
        do {
            if let fileName = fileName {
                let url = try URL(forDownloadedFile: fileName)
                self.downloadFile(downloadTask: task, fileName: fileName, destUrl: url)
            }
            else {
//                askFileLocation()
                self.showDownloadFinishNotification(fileName: fileName, downloadTask: task, succeeded: false)
            }
        }
        catch {
            // Failed to retrieve appropriate download destination - ask user to select
//            askFileLocation()
            self.showDownloadFinishNotification(fileName: fileName, downloadTask: task, succeeded: false)
        }
    }
    
    private func downloadFile(downloadTask task: DownloadTask, fileName: String, destUrl: URL) {
        if let (readyStream, partUrl) = self.streamForTempDownload(finalUrl: destUrl) {
            self.downloadInfos.append(DownloadInfo(task: task, fileName: fileName, url: partUrl))
            task.delegate = self
            task.start(withStream: readyStream)
        }
        else {
            self.showDownloadFinishNotification(fileName: fileName, downloadTask: task, succeeded: false)
        }
    }
    
    private func streamForTempDownload(finalUrl: URL) -> (OutputStream, URL)? {
        // Try open stream for new file. Try alternative names on fail
        var partUrl = finalUrl.appendingPathExtension("part")
        var stream: OutputStream? = nil
        for _ in 1...10000 {
            if !FileManager.default.fileExists(atPath: partUrl.path) {
                stream = OutputStream(url: partUrl, append: false)
                stream?.open()
                if stream?.hasSpaceAvailable ?? false {
                    break
                }
            }
            
            partUrl = partUrl.alternativeForDuplicate()
        }
        
        // Last attempt with completely random extension
        if stream == nil {
            partUrl = finalUrl.appendingPathExtension("part-\(UUID().uuidString)")
            if !FileManager.default.fileExists(atPath: partUrl.path) {
                stream = OutputStream(url: partUrl, append: false)
                stream?.open()
            }
        }
        
        if let readyStream = stream, (stream?.hasSpaceAvailable ?? false) {
            return (readyStream, partUrl)
        }
        else {
            stream?.close()
            return nil
        }
    }
    
    private func renamePartFile(url partUrl: URL, to fileName: String) throws -> URL {
        
        // Try rename file from temporary *.part name to final path based on original file name
        // NOTE: *.part name might not necesarily be equal to filename with appended .part suffix
        var finalUrl = partUrl.deletingLastPathComponent().appendingPathComponent(fileName)
        for _ in 1...10000 {
            if !FileManager.default.fileExists(atPath: finalUrl.path) {
                do {
                    try FileManager.default.moveItem(at: partUrl, to: finalUrl)
                    return finalUrl
                }
                catch {}
            }
            finalUrl = finalUrl.alternativeForDuplicate()
        }

        throw ShareError.partFileRenameFailed
    }
    
    private func showDownloadFinishNotification(fileName: String?, downloadTask task: DownloadTask, succeeded: Bool, finalUrl: URL? = nil) {
        assert((try? task.connection.identity?.getDeviceName()) != nil, "Download task expected to have assigned a connection with proper identity info")
        
        let deviceName: String? = (try? task.connection.identity?.getDeviceName() ?? nil) ?? nil
        let title = succeeded ? "Finished downloading file" : "File download failed"
        let info: String
        if let fileName = finalUrl?.lastPathComponent ?? fileName {
            info = deviceName != nil ? "File '\(fileName)' sent from device '\(deviceName!)'" : "File: '\(fileName)'"
        }
        else {
            info = deviceName != nil ? "File sent from device '\(deviceName!)'" : ""
        }
        
        let notification = NSUserNotification(actionHandlerClass: ShareService.self)
        if let url = finalUrl {
            var userInfo = notification.userInfo
            userInfo?[NotificationProperty.downloadedFileUrl.rawValue] = url.absoluteString as AnyObject
            notification.userInfo = userInfo
        }
        notification.title = title
        notification.informativeText = info
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.hasActionButton = succeeded && finalUrl != nil
        notification.actionButtonTitle = "Open"
        notification.identifier = "com.migla.ShareService.download.\(task.id)"
        NSUserNotificationCenter.default.scheduleNotification(notification)
        
        if !succeeded {
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                NSUserNotificationCenter.default.removeDeliveredNotification(notification)
            }
        }
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
