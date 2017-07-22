//
//  ShareService.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-12-02.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import Cocoa
import CleanroomLogger

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
public class ShareService: NSObject, Service, DownloadTaskDelegate, UserNotificationActionHandler, NSDraggingDestination {
    
    // MARK: Types
    
    private enum ShareError: Error {
        case partFileRenameFailed
    }
    
    private enum ActionId: ServiceAction.Id {
        case shareFiles
    }
    
    private enum NotificationProperty: String {
        case downloadedFileUrl = "com.soduto.ShareService.download.url"
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
    
    private struct DragDestination {
        let dataPackets: [DataPacket]
        let device: Device
    }
    
    
    // MARK: Service properties
    
    public let id: Service.Id = "com.soduto.services.share"
    
    private static let dragTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType(rawValue: kUTTypeFileURL as String),
        NSPasteboard.PasteboardType(rawValue: kUTTypeURL as String),
        NSPasteboard.PasteboardType(rawValue: kUTTypeText as String) ]
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.sharePacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.sharePacketType ])
    
    private var downloadInfos: [DownloadInfo] = []
    private var devices: [Device.Id:Device] = [:]
    private var validDevices: [Device] { return self.devices.values.filter { $0.isReachable && $0.pairingStatus == .Paired } }
    
    
    // MARK: Service methods
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isSharePacket else { return false }
        
        Log.debug?.message("handleDataPacket(<\(dataPacket)> fromDevice:<\(device)> onConnection:<\(connection)>)");
        
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
                Log.error?.message("Unknown shared content")
            }
        }
        catch {
            Log.error?.message("Error while handling share packet: \(error)")
        }
        
        return true
    }
    
    public func setup(for device: Device) {
        self.devices[device.id] = device
    }
    
    public func cleanup(for device: Device) {
        _ = self.devices.removeValue(forKey: device.id)
    }
    
    public func actions(for device: Device) -> [ServiceAction] {
        guard device.incomingCapabilities.contains(DataPacket.sharePacketType) else { return [] }
        guard device.pairingStatus == .Paired else { return [] }
        
        return [
            ServiceAction(id: ActionId.shareFiles.rawValue, title: "Send Files", description: "Upload files to the peer device.", service: self, device: device)
        ]
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        guard let actionId = ActionId(rawValue: id) else { return }
        guard device.pairingStatus == .Paired else { return }
        
        switch actionId {
        case .shareFiles:
            NSApp.activate(ignoringOtherApps: true)
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.allowsMultipleSelection = true
            openPanel.begin { result in
                guard result == NSApplication.ModalResponse.OK else { return }
                for url in openPanel.urls {
                    self.uploadFile(url: url, to: device)
                }
            }
            break
        }
        
    }
    
    
    // MARK: DownloadTaskDelegate
    
    public func downloadTask(_ task: DownloadTask, finishedWithSuccess success: Bool) {
        Log.debug?.message("downloadTask(<\(task)> finishedWithSuccess:<\(success)>)")
        
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
    
    
    // MARK: UserNotificationsActionHandler
    
    public static func handleAction(for notification: NSUserNotification, context: UserNotificationContext) {
        guard let urlString = notification.userInfo?[NotificationProperty.downloadedFileUrl.rawValue] as? String else { return }
        guard let url = URL(string: urlString) else { return }
        guard notification.activationType == .actionButtonClicked || notification.activationType == .contentsClicked else { return }
        
        NSWorkspace.shared().open(url)
    }
    
    
    // MARK: NSDraggingDestination
    
    public dynamic func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingUpdated(sender)
    }
    
    public dynamic func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard self.validDevices.count > 0 else { return [] }
        
        let types: [String] = type(of: self).dragTypes.map { $0.rawValue }
        let canRead: Bool = sender.draggingPasteboard().canReadItem(withDataConformingToTypes: types)
        return canRead ? [.copy] : []
    }
    
    public dynamic func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard self.validDevices.count > 0 else { return false }
        
        var filePackets: [DataPacket] = []
        var urlPackets: [DataPacket] = []
        var textPackets: [DataPacket] = []
        
        let types = type(of: self).dragTypes
        let items: [NSPasteboardItem] = sender.draggingPasteboard().pasteboardItems ?? []
        for item in items {
            guard let type = item.availableType(from: types) else { continue }
            switch type.rawValue {
                
            case String(kUTTypeFileURL):
                guard let urlString = item.string(forType: type) else { break }
                guard let url = URL(string: urlString) else { break }
                guard let dataPacket = self.dataPacket(forFileUrl: url) else { break }
                filePackets.append(dataPacket)
                break
                
            case String(kUTTypeURL):
                guard let urlString = item.string(forType: type) else { break }
                guard let url = URL(string: urlString) else { break }
                let dataPacket = self.dataPacket(forUrl: url)
                urlPackets.append(dataPacket)
                break
                
            case type.rawValue where UTTypeConformsTo(type.rawValue as CFString, kUTTypeText):
                guard let text = item.string(forType: type) else { break }
                let dataPacket = self.dataPacket(forText: text)
                textPackets.append(dataPacket)
                break
                
            default:
                break
            }
        }
        
        guard filePackets.count > 0 || urlPackets.count > 0 || textPackets.count > 0 else { return false }
        
        return self.popUpDragDestinationMenu(forFilePackets: filePackets, urlPackets: urlPackets, textPackets: textPackets, sender: sender)
    }
    
    
    // MARK: Actions
    
    @objc private dynamic func dragDestinationMenuItemAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }
        
        if let obj = menuItem.representedObject as? DragDestination {
            guard obj.device.isReachable && obj.device.pairingStatus == .Paired else { return }
            for packet in obj.dataPackets {
                obj.device.send(packet)
            }
        }
    }
    
    
    // MARK: Private methods
    
    private func fileSize(path: String) -> Int64? {
        var fileSize : Int64? = nil
        
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: path)
            fileSize = attr[FileAttributeKey.size] as? Int64
        } catch {
            Log.error?.message("Failed to get file information: \(error)")
        }
        
        return fileSize
    }
    
    private func uploadFile(url: URL, to device: Device) {
        guard let dataPacket = self.dataPacket(forFileUrl: url) else { return }
        device.send(dataPacket)
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
        notification.identifier = "\(self.id).download.\(task.id)"
        NSUserNotificationCenter.default.scheduleNotification(notification)
        
        if !succeeded {
            _ = Timer.compatScheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                NSUserNotificationCenter.default.removeDeliveredNotification(notification)
            }
        }
    }
    
    private func popUpDragDestinationMenu(forFilePackets filePackets: [DataPacket], urlPackets: [DataPacket], textPackets: [DataPacket], sender: NSDraggingInfo) -> Bool {
        
        let packets: [DataPacket]
        let title: String
        if filePackets.count > 0 {
            packets = filePackets
            title = packets.count == 1 ?
                String(format: NSLocalizedString("Upload file to:", comment: "Drag destinations menu title"), packets.count) :
                String(format: NSLocalizedString("Upload %d file(s) to:", comment: "Drag destinations menu title"), packets.count)
        }
        else if urlPackets.count > 0 {
            packets = urlPackets
            title = packets.count == 1 ?
                String(format: NSLocalizedString("Open link on:", comment: "Drag destinations menu title"), packets.count) :
                String(format: NSLocalizedString("Open %d link(s) on:", comment: "Drag destinations menu title"), packets.count)
        }
        else if textPackets.count > 0 {
            packets = textPackets
            title = packets.count == 1 ?
                String(format: NSLocalizedString("Send text snippet to:", comment: "Drag destinations menu title"), packets.count) :
                String(format: NSLocalizedString("Send %d text snippet(s) to:", comment: "Drag destinations menu title"), packets.count)
        }
        else {
            return false
        }
        
        
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        for device in self.validDevices {
            let keyEquivalent: String = menu.items.count <= 10 ? "\(menu.items.count % 10)" : ""
            let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: keyEquivalent)
            item.target = self
            item.action = #selector(dragDestinationMenuItemAction(_:))
            item.representedObject = DragDestination(dataPackets: packets, device: device)
            menu.addItem(item)
        }
        
        let position: NSPoint = sender.draggingDestinationWindow()?.frame.origin ?? NSEvent.mouseLocation()
        return menu.popUp(positioning: nil, at: position, in: nil)
    }
    
    private func dataPacket(forFileName fileName: String) -> DataPacket? {
        let url = URL(fileURLWithPath: fileName)
        let dataPacket = self.dataPacket(forFileUrl: url)
        return dataPacket
    }
    
    private func dataPacket(forFileUrl url: URL) -> DataPacket? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        guard !isDirectory.boolValue else { return nil }
        guard let filename = url.pathComponents.last else { return nil }
        guard let stream = InputStream(url: url) else { return nil }
        
        let fileSize = self.fileSize(path: url.path)
        let dataPacket = DataPacket.sharePacket(fileStream: stream, fileSize: fileSize, fileName: filename)
        return dataPacket
    }
    
    private func dataPacket(forUrl url: URL) -> DataPacket {
        return DataPacket.sharePacket(url: url)
    }
    
    private func dataPacket(forText text: String) -> DataPacket {
        return DataPacket.sharePacket(text: text)
    }
}


// MARK: DataPacket (Share)

/// Ping service data packet utilities
fileprivate extension DataPacket {
    
    // MARK: Types
    
    enum ShareError: Error {
        case wrongType
        case invalidFilename
        case invalidText
        case invalidUrl
    }
    
    struct ShareProperty {
        static let filename = "filename"
        static let text = "text"
        static let url = "url"
    }
    
    
    // MARK: Properties
    
    static let sharePacketType = "kdeconnect.share.request"
    
    var isSharePacket: Bool { return self.type == DataPacket.sharePacketType }
    
    
    // MARK: Public methods
    
    static func sharePacket(fileStream: InputStream, fileSize: Int64?, fileName: String?) -> DataPacket {
        var body: Body = [:]
        if let filename = fileName {
            body[ShareProperty.filename] = filename as AnyObject
        }
        var packet = DataPacket(type: sharePacketType, body: body)
        packet.payload = fileStream
        packet.payloadSize = fileSize
        return packet
    }
    
    static func sharePacket(url: URL) -> DataPacket {
        let body: Body = [
            ShareProperty.url: url.absoluteString as AnyObject
        ]
        let packet = DataPacket(type: sharePacketType, body: body)
        return packet
    }
    
    static func sharePacket(text: String) -> DataPacket {
        let body: Body = [
            ShareProperty.text: text as AnyObject
        ]
        let packet = DataPacket(type: sharePacketType, body: body)
        return packet
    }
    
    func getFilename() throws -> String? {
        try self.validateShareType()
        guard body.keys.contains(ShareProperty.filename) else { return nil }
        guard let value = body[ShareProperty.filename] as? String else { throw ShareError.invalidFilename }
        return value
    }
    
    func getText() throws -> String? {
        try self.validateShareType()
        guard body.keys.contains(ShareProperty.text) else { return nil }
        guard let value = body[ShareProperty.text] as? String else { throw ShareError.invalidText }
        return value
    }
    
    func getUrl() throws -> String? {
        try self.validateShareType()
        guard body.keys.contains(ShareProperty.url) else { return nil }
        guard let value = body[ShareProperty.url] as? String else { throw ShareError.invalidUrl }
        return value
    }
    
    func validateShareType() throws {
        guard self.isSharePacket else { throw ShareError.wrongType }
    }
}
