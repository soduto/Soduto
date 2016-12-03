//
//  UserNotificationManager.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-11-22.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation

public struct UserNotificationContext {
    
    public let config: Configuration
    public let serviceManager: ServiceManager
    public let deviceManager: DeviceManager
    
    public init(config: Configuration, serviceManager: ServiceManager, deviceManager: DeviceManager) {
        self.config = config
        self.serviceManager = serviceManager
        self.deviceManager = deviceManager
    }
}

public protocol UserNotificationActionHandler: class {
    
    static func handleAction(for notification: NSUserNotification, context: UserNotificationContext)
    
}

public class UserNotificationManager: NSObject, NSUserNotificationCenterDelegate {
    
    // MARK: Types
    
    enum Property: String {
        case actionHandlerClass = "com.migla.usernotificationmanager.actionhandlerclass"
        case dontPresent = "com.migla.usernotificationmanager.dontPresent"
    }
    
    
    // MARK: Private properties
    
    private let context: UserNotificationContext
    
    // Notification dissmissing is not reported by the system, so we use timers to manually check and report such events
    private var fastTimer: Timer? = nil // more frequently firing timer for notifications needing faster response
    private var slowTimer: Timer? = nil // less frequently firing timer for longer standing notifications that dont need fast response
    private var fastNotifications: [String:NSUserNotification] = [:] // notifications monitored by fastTimer
    private var slowNotifications: [String:NSUserNotification] = [:] // notifications monitored by slowTimer
    
    
    // MARK: Init / Deinit
    
    public init(config: Configuration, serviceManager: ServiceManager, deviceManager: DeviceManager) {
        self.context = UserNotificationContext(config: config, serviceManager: serviceManager, deviceManager: deviceManager)
        
        super.init()
        
        NSUserNotificationCenter.default.delegate = self
    }
    
    
    // MARK: NSUserNotificationCenterDelegate
    
    public func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        // NOTE: This is not called for every notification - only for those that system thinks shouldnt be presented
        if let dontPresent = notification.userInfo?[Property.dontPresent.rawValue] as? NSNumber {
            return !dontPresent.boolValue
        }
        else {
            return true
        }
    }
    
    public func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        self.handleAction(for: notification)
        self.stopMonitoringNotification(notification)
        NSUserNotificationCenter.default.removeDeliveredNotification(notification)
    }
    
    public func userNotificationCenter(_ center: NSUserNotificationCenter, didDeliver notification: NSUserNotification) {
        if notification.isPresented {
            self.monitorFastNotification(notification)
        }
        else {
            self.monitorSlowNotification(notification)
        }
    }
    
    
    // MARK: Private methods
    
    private func handleAction(for notification: NSUserNotification) {
        guard let handlerClassName = notification.userInfo?[Property.actionHandlerClass.rawValue] as? String else { return }
        guard let handlerClass = NSClassFromString(handlerClassName) as? UserNotificationActionHandler.Type else { return }
        handlerClass.handleAction(for: notification, context: self.context)
    }
    
    private func monitorFastNotification(_ notification: NSUserNotification) {
        guard let id = notification.identifier else { return }
        
        self.fastNotifications[id] = notification
        
        if self.fastTimer == nil {
            self.fastTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
                for id in self.fastNotifications.keys {
                    if let n = NSUserNotificationCenter.default.deliveredNotifications.first(where: { n in n.identifier == id }) {
                        if !n.isPresented {
                            // if not showing - move to slow notifications
                            self.stopMonitoringNotification(n)
                            self.monitorSlowNotification(n)
                        }
                    }
                    else {
                        self.handleAction(for: notification)
                        self.stopMonitoringNotification(notification)
                    }
                }
            }
        }
    }
    
    private func monitorSlowNotification(_ notification: NSUserNotification) {
        guard let id = notification.identifier else { return }
        
        self.slowNotifications[id] = notification
        
        if self.slowTimer == nil {
            self.slowTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
                for id in self.slowNotifications.keys {
                    guard !NSUserNotificationCenter.default.deliveredNotifications.contains(where: { n in n.identifier == id }) else { continue }
                    
                    self.handleAction(for: notification)
                    self.stopMonitoringNotification(notification)
                }
            }
        }
    }
    
    private func stopMonitoringNotification(_ notification: NSUserNotification) {
        assert(notification.identifier != nil, "Only notifications with identifiers are monitored")
        
        guard let id = notification.identifier else { return }
        
        self.slowNotifications.removeValue(forKey: id)
        if self.slowNotifications.count == 0 {
            self.slowTimer?.invalidate()
            self.slowTimer = nil
        }
        
        self.fastNotifications.removeValue(forKey: id)
        if self.fastNotifications.count == 0 {
            self.fastTimer?.invalidate()
            self.fastTimer = nil
        }
    }
}

extension NSUserNotification {
    
    /// Convenience notification initializer which appropriately setups action handling information
    convenience init<C>(actionHandlerClass: C.Type) where C: UserNotificationActionHandler {
        self.init()
        
        self.userInfo = [
            UserNotificationManager.Property.actionHandlerClass.rawValue: NSStringFromClass(actionHandlerClass)
        ]
    }
    
}
