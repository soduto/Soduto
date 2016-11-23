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
    
    // MARK: Constants
    
    public static let actionHandlerClassProperty = "com.migla.usernotificationmanager.actionhandlerclass"
    
    
    // MARK: Private properties
    
    private let context: UserNotificationContext
    private var dismissCheckTimers: [String:Timer] = [:]
    
    
    // MARK: Init / Deinit
    
    public init(config: Configuration, serviceManager: ServiceManager, deviceManager: DeviceManager) {
        self.context = UserNotificationContext(config: config, serviceManager: serviceManager, deviceManager: deviceManager)
        
        super.init()
        
        NSUserNotificationCenter.default.delegate = self
    }
    
    
    // MARK: NSUserNotificationCenterDelegate
    
    public func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    public func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        self.handleAction(for: notification)
        self.invalidateDismissCheckTimer(for: notification)
        NSUserNotificationCenter.default.removeDeliveredNotification(notification)
    }
    
    public func userNotificationCenter(_ center: NSUserNotificationCenter, didDeliver notification: NSUserNotification) {
        // A hack to detect notification dismissing by clicking on close (otherButton) button. In such case didActivate 
        // delegate method does not get called. Notification needs to have identifier set for hack to work
        self.invalidateDismissCheckTimer(for: notification)
        if let identifier = notification.identifier {
            self.dismissCheckTimers[identifier] = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
                guard !center.deliveredNotifications.contains(where: { n in n.identifier == identifier }) else { return }
                if notification.activationType == .none {
                    self.handleAction(for: notification)
                }
                timer.invalidate()
            }
        }
    }
    
    
    // MARK: Private methods
    
    private func handleAction(for notification: NSUserNotification) {
        guard let handlerClassName = notification.userInfo?[UserNotificationManager.actionHandlerClassProperty] as? String else { return }
        guard let handlerClass = NSClassFromString(handlerClassName) as? UserNotificationActionHandler.Type else { return }
        handlerClass.handleAction(for: notification, context: self.context)
    }
    
    private func invalidateDismissCheckTimer(for notification: NSUserNotification) {
        guard let identifier = notification.identifier else { return }
        
        if let timer = self.dismissCheckTimers.removeValue(forKey: identifier) {
            timer.invalidate()
        }
    }
    
}

extension NSUserNotification {
    
    /// Convenience notification initializer which appropriately setups action handling information
    convenience init<C>(actionHandlerClass: C.Type) where C: UserNotificationActionHandler {
        self.init()
        
        self.userInfo = [
            UserNotificationManager.actionHandlerClassProperty: NSStringFromClass(actionHandlerClass)
        ]
    }
    
}
