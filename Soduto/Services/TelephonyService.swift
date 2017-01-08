//
//  TelephonyService.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-12-05.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import Cocoa
import CleanroomLogger

/// Show notifications for phone call or SMS events. Also allows to send SMS
///
/// This service will display a notification each time a package with type
/// "kdeconnect.telephony" is received. The type of notification will change
/// depending on the contents of the field "event" (string).
///
/// Valid contents for "event" are: "ringing", "talking", "missedCall" and "sms".
/// Note that "talking" is just ignored in this implementation, while the others
/// will display a system notification.
///
/// If the incoming package contains a "phoneNumber" string field, the notification
/// will also display it. Note that "phoneNumber" can be a contact name instead
/// of an actual phone number.
///
/// If the incoming package contains "isCancel" set to true, the package is ignored.
public class TelephonyService: Service, UserNotificationActionHandler {
    
    // MARK: Types
    
    enum NotificationProperty: String {
        case deviceId = "com.soduto.TelephonyService.notification.deviceId"
        case event = "com.soduto.TelephonyService.notification.event"
        case phoneNumber = "com.soduto.TelephonyService.notification.phoneNumber"
        case contactName = "com.soduto.TelephonyService.notification.contactName"
        case originalMessage = "com.soduto.TelephonyService.notification.originalMessage"
    }
    
    
    // MARK: Service properties
    
    public let incomingCapabilities = Set<Service.Capability>([ DataPacket.telephonyPacketType ])
    public let outgoingCapabilities = Set<Service.Capability>([ DataPacket.telephonyRequestPacketType, DataPacket.smsRequestPacketType ])
    
    
    // MARK: Service methods
    
    public func handleDataPacket(_ dataPacket: DataPacket, fromDevice device: Device, onConnection connection: Connection) -> Bool {
        
        guard dataPacket.isTelephonyPacket else { return false }
        
        Log.debug?.message("handleDataPacket(<\(dataPacket)> fromDevice:<\(device)> onConnection:<\(connection)>)")
        
        do {
            if try dataPacket.getCancelFlag() {
                self.hideNotification(for: dataPacket, from: device)
            }
            else if let event = try dataPacket.getEvent() ?? nil {
                switch event {
                case DataPacket.TelephonyEvent.ringing.rawValue:
                    self.showRingingNotification(for: dataPacket, from: device)
                    break
                case DataPacket.TelephonyEvent.missedCall.rawValue:
                    self.showMissedCallNotification(for: dataPacket, from: device)
                    break
                case DataPacket.TelephonyEvent.talking.rawValue:
                    self.hideNotification(for: dataPacket, from: device)
                    break
                case DataPacket.TelephonyEvent.sms.rawValue:
                    self.showSmsNotification(for: dataPacket, from: device)
                    break
                default:
                    Log.error?.message("Unknown telephony event type: \(event)")
                    break
                }
            }
        }
        catch {
            Log.error?.message("Error while handling telephony packet: \(error)")
        }
        
        return true
    }
    
    public func setup(for device: Device) {}
    
    public func cleanup(for device: Device) {}
    
    public func actions(for device: Device) -> [ServiceAction] {
        // no actions supported
        return []
    }
    
    public func performAction(_ id: ServiceAction.Id, forDevice device: Device) {
        // no actions supported
    }
    
    
    // MARK: UserNotificationActionHandler
    
    public static func handleAction(for notification: NSUserNotification, context: UserNotificationContext) {
        guard let userInfo = notification.userInfo else { return }
        guard let deviceId = userInfo[NotificationProperty.deviceId.rawValue] as? String else { return }
        guard let device = context.deviceManager.device(withId: deviceId) else { return }
        guard device.pairingStatus == .Paired else { return }
        guard let event = userInfo[NotificationProperty.event.rawValue] as? String else { return }
        
        switch event {
        case DataPacket.TelephonyEvent.ringing.rawValue:
            guard notification.activationType == .actionButtonClicked else { break }
            device.send(DataPacket.mutePhonePacket())
            break
        case DataPacket.TelephonyEvent.sms.rawValue:
            guard notification.activationType == .replied else { break }
            guard let response = notification.response?.string else { break }
            guard let phoneNumber = userInfo[NotificationProperty.phoneNumber.rawValue] as? String else { break }
            device.send(DataPacket.smsRequestPacket(phoneNumber: phoneNumber, message: response))
            break
        default:
            break
        }
    }
    
    
    // MARK: Private methods
    
    private func notificationId(for dataPacket: DataPacket, from device: Device) -> NSUserNotification.Id? {
        assert(dataPacket.isTelephonyPacket, "Expected telephony data packet")
        assert(try! dataPacket.getEvent() != nil, "Expected telephony event property")
        
        guard let deviceId = device.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        guard let event = (try? dataPacket.getEvent() ?? nil) else { return nil }
        
        if event == DataPacket.TelephonyEvent.sms.rawValue {
            // For SMS notifications we want them to be uniqueue per contact 
            // TODO: or should it be unique per message?
            let phoneNumber = (try? dataPacket.getPhoneNumber())??.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "unknownPhoneNumber"
            return "com.soduto.TelephonyService.\(deviceId).sms.\(phoneNumber)"
        }
        else {
            // For calling notifications we use ids unique per device
            return "com.soduto.TelephonyService.\(deviceId).call"
        }
    }
    
    private func showRingingNotification(for dataPacket: DataPacket, from device: Device) {
        assert(dataPacket.isTelephonyPacket, "Expected telephony data packet")
        assert(try! dataPacket.getEvent() == DataPacket.TelephonyEvent.ringing.rawValue, "Expected 'ringing' event type")
        
        do {
            guard let notificationId = self.notificationId(for: dataPacket, from: device) else { return }
            let phoneNumber = try dataPacket.getPhoneNumber() ?? "unknown number"
            let contactName = try dataPacket.getContactName() ?? phoneNumber
            let thumbnail = (try? dataPacket.getPhoneThumbnail() ?? nil) ?? nil
            
            let notification = NSUserNotification(actionHandlerClass: type(of: self))
            var userInfo = notification.userInfo
            userInfo?[NotificationProperty.deviceId.rawValue] = device.id as AnyObject
            userInfo?[NotificationProperty.event.rawValue] = DataPacket.TelephonyEvent.ringing.rawValue as AnyObject
            notification.userInfo = userInfo
            notification.title = "Incoming call from \(contactName)"
            notification.subtitle = device.name
            notification.contentImage = thumbnail
            notification.soundName = NSUserNotificationDefaultSoundName
            notification.hasActionButton = true
            notification.actionButtonTitle = "Mute call"
            notification.identifier = notificationId
            NSUserNotificationCenter.default.scheduleNotification(notification)
            
            Log.debug?.message("Ringing notification shown: \(notification.identifier)")
        }
        catch {
            Log.error?.message("Error while showing ringing notification: \(error)")
        }
    }
    
    private func showMissedCallNotification(for dataPacket: DataPacket, from device: Device) {
        assert(dataPacket.isTelephonyPacket, "Expected telephony data packet")
        assert(try! dataPacket.getEvent() == DataPacket.TelephonyEvent.missedCall.rawValue, "Expected 'missedCall' event type")
        
        do {
            guard let notificationId = self.notificationId(for: dataPacket, from: device) else { return }
            let phoneNumber = try dataPacket.getPhoneNumber() ?? "unknown number"
            let contactName = try dataPacket.getContactName() ?? phoneNumber
            let thumbnail = (try? dataPacket.getPhoneThumbnail() ?? nil) ?? nil
            
            let notification = NSUserNotification()
            notification.title = "Missed a call from \(contactName)"
            notification.subtitle = device.name
            notification.contentImage = thumbnail
            notification.soundName = NSUserNotificationDefaultSoundName
            notification.hasActionButton = false
            notification.identifier = notificationId
            NSUserNotificationCenter.default.scheduleNotification(notification)
            
            Log.debug?.message("Missed call notification shown: \(notification.identifier)")
        }
        catch {
            Log.error?.message("Error while showing missed call notification: \(error)")
        }
    }
    
    private func showSmsNotification(for dataPacket: DataPacket, from device: Device) {
        assert(dataPacket.isTelephonyPacket, "Expected telephony data packet")
        assert(try! dataPacket.getEvent() == DataPacket.TelephonyEvent.sms.rawValue, "Expected 'sms' event type")
        
        do {
            guard let notificationId = self.notificationId(for: dataPacket, from: device) else { return }
            
            // One SMS might come in chunks - try concating them together. 
            // However if time from last notification is big enough - add a new line when concatening - they probably are
            // separate messages
            let lastNotification = NSUserNotificationCenter.default.deliveredNotifications.first { notification in
                return notification.identifier == notificationId
            }
            let lastNotificationIsOld = (lastNotification?.deliveryDate ?? Date()).timeIntervalSinceNow < -10.0
            let lastMessageBody = (lastNotification?.informativeText ?? "") + (lastNotificationIsOld ? "\n" : "")
            if let notification = lastNotification {
                NSUserNotificationCenter.default.removeDeliveredNotification(notification)
            }
            
            let hasPhoneNumber = try dataPacket.getPhoneNumber() != nil
            let phoneNumber = try dataPacket.getPhoneNumber() ?? "unknown number"
            let contactName = try dataPacket.getContactName() ?? phoneNumber
            let messageBody = lastMessageBody + (try dataPacket.getMessageBody() ?? "")
            let thumbnail = (try? dataPacket.getPhoneThumbnail() ?? nil) ?? nil
            
            let notification = NSUserNotification(actionHandlerClass: type(of: self))
            var userInfo = notification.userInfo
            userInfo?[NotificationProperty.deviceId.rawValue] = device.id as AnyObject
            userInfo?[NotificationProperty.event.rawValue] = DataPacket.TelephonyEvent.sms.rawValue as AnyObject
            userInfo?[NotificationProperty.phoneNumber.rawValue] = phoneNumber as AnyObject
            notification.userInfo = userInfo
            notification.title = "SMS from  \(contactName) | \(device.name)"
            notification.informativeText = messageBody
            notification.contentImage = thumbnail
            notification.soundName = NSUserNotificationDefaultSoundName
            notification.hasActionButton = hasPhoneNumber
            notification.hasReplyButton = hasPhoneNumber
            notification.responsePlaceholder = "Write reply message"
            notification.identifier = notificationId
            NSUserNotificationCenter.default.deliver(notification)
            
            Log.debug?.message("SMS notification shown: \(notification.identifier)")
        }
        catch {
            Log.error?.message("Error while showing sms notification: \(error)")
        }
    }
    
    private func hideNotification(for dataPacket: DataPacket, from device: Device) {
        assert(dataPacket.isTelephonyPacket, "Expected telephony data packet")
        
        guard let id = self.notificationId(for: dataPacket, from: device) else { return }
        
        for notification in NSUserNotificationCenter.default.deliveredNotifications {
            if notification.identifier == id {
                NSUserNotificationCenter.default.removeDeliveredNotification(notification)
                break
            }
        }
        
        for notification in NSUserNotificationCenter.default.scheduledNotifications {
            if notification.identifier == id {
                NSUserNotificationCenter.default.removeScheduledNotification(notification)
                break
            }
        }
        
        Log.debug?.message("Notification hidden: \(id)")
    }
}


// MARK: - DataPacket (Telephony)

/// Telephony service data packet utilities
fileprivate extension DataPacket {
    
    // MARK: Types
    
    enum TelephonyError: Error {
        case wrongType
        case invalidEvent
        case invalidPhoneNumber
        case invalidContactName
        case invalidMessageBody
        case invalidPhoneThumbnail
        case invalidCancelFlag
    }
    
    enum TelephonyEvent: String {
        case sms = "sms"
        case ringing = "ringing"
        case missedCall = "missedCall"
        case talking = "talking"
    }
    
    enum TelephonyAction: String {
        case mute = "mute"
    }
    
    enum TelephonyProperty: String {
        case event = "event"                    // (string): can be one of TelephonyEvent values
        case phoneNumber = "phoneNumber"        // (string)
        case contactName = "contactName"        // (string)
        case messageBody = "messageBody"        // (string)
        case phoneThumbnail = "phoneThumbnail"  // (bytes)
        case action = "action"                  // (string): 'mute' for muting the phone
        case sendSms = "sendSms"                // (boolean): true to send sms
        case isCancel = "isCancel"              // (boolean): cancel previous event
    }
    
    
    // MARK: Properties
    
    static let telephonyPacketType = "kdeconnect.telephony"
    static let telephonyRequestPacketType = "kdeconnect.telephony.request"
    static let smsRequestPacketType = "kdeconnect.sms.request"
    
    var isTelephonyPacket: Bool { return self.type == DataPacket.telephonyPacketType }
    
    var isTelephonyRequestPacket: Bool { return self.type == DataPacket.telephonyRequestPacketType }
    
    var isSmsRequestPacket: Bool { return self.type == DataPacket.smsRequestPacketType }
    
    
    // MARK: Public static methods
    
    static func smsRequestPacket(phoneNumber: String, message: String) -> DataPacket {
        return DataPacket(type: smsRequestPacketType, body: [
            TelephonyProperty.sendSms.rawValue: NSNumber(value: true),
            TelephonyProperty.phoneNumber.rawValue: phoneNumber as AnyObject,
            TelephonyProperty.messageBody.rawValue: message as AnyObject
        ])
    }
    
    static func mutePhonePacket() -> DataPacket {
        return DataPacket(type: telephonyRequestPacketType, body: [
            TelephonyProperty.action.rawValue: TelephonyAction.mute.rawValue as AnyObject
        ])
    }
    
    
    // MARK: Public methods
    
    func getEvent() throws -> String? {
        try self.validateTelephonyType()
        guard body.keys.contains(TelephonyProperty.event.rawValue) else { return nil }
        guard let value = body[TelephonyProperty.event.rawValue] as? String else { throw TelephonyError.invalidEvent }
        return value
    }
    
    func getPhoneNumber() throws -> String? {
        try self.validateTelephonyOrSmsRequestType()
        guard body.keys.contains(TelephonyProperty.phoneNumber.rawValue) else { return nil }
        guard let value = body[TelephonyProperty.phoneNumber.rawValue] as? String else { throw TelephonyError.invalidPhoneNumber }
        return value
    }
    
    func getContactName() throws -> String? {
        try self.validateTelephonyType()
        guard body.keys.contains(TelephonyProperty.contactName.rawValue) else { return nil }
        guard let value = body[TelephonyProperty.contactName.rawValue] as? String else { throw TelephonyError.invalidContactName }
        return value
    }
    
    func getMessageBody() throws -> String? {
        try self.validateTelephonyOrSmsRequestType()
        guard body.keys.contains(TelephonyProperty.messageBody.rawValue) else { return nil }
        guard let value = body[TelephonyProperty.messageBody.rawValue] as? String else { throw TelephonyError.invalidMessageBody }
        return value
    }
    
    func getPhoneThumbnail() throws -> NSImage? {
        try self.validateTelephonyType()
        guard body.keys.contains(TelephonyProperty.phoneThumbnail.rawValue) else { return nil }
        guard let data = body[TelephonyProperty.phoneThumbnail.rawValue] as? Data else { throw TelephonyError.invalidEvent }
        guard let image = NSImage(data: data) else { throw TelephonyError.invalidEvent }
        return image
    }
    
    func getCancelFlag() throws -> Bool {
        // Cancel flag might be (and actually is!) string instead of bool - handling both cases
        try self.validateTelephonyType()
        guard body.keys.contains(TelephonyProperty.isCancel.rawValue) else { return false }
        let stringValue = body[TelephonyProperty.isCancel.rawValue] as? String
        let boolValue: Bool? = (stringValue != nil) ? Bool(stringValue!) : (body[TelephonyProperty.isCancel.rawValue] as? NSNumber)?.boolValue
        guard let value = boolValue else { throw TelephonyError.invalidCancelFlag }
        return value
    }
    
    func validateTelephonyType() throws {
        guard self.isTelephonyPacket else { throw TelephonyError.wrongType }
    }
    
    func validateTelephonyOrSmsRequestType() throws {
        guard self.isTelephonyPacket || self.isSmsRequestPacket else { throw TelephonyError.wrongType }
    }
}
