//
//  StatusBarMenuController.swift
//  Soduto
//
//  Created by Giedrius Stanevicius on 2016-07-26.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import AppKit

public class StatusBarMenuController: NSObject, NSMenuDelegate {
    
    @IBOutlet weak var statusBarMenu: NSMenu!
    @IBOutlet weak var availableDevicesItem: NSMenuItem!
    @IBOutlet weak var launchOnLoginItem: NSMenuItem!
    
    public var deviceDataSource: DeviceDataSource?
    public var serviceManager: ServiceManager?
    public var config: Configuration?
    
    let statusBarItem = NSStatusBar.system().statusItem(withLength: NSSquareStatusItemLength)
    
    var preferencesWindowController: PreferencesWindowController?
    
    override public func awakeFromNib() {
        let statusBarIcon = #imageLiteral(resourceName: "statusBarIcon")
        statusBarIcon.isTemplate = true
        
        self.statusBarItem.image = statusBarIcon
        self.statusBarItem.menu = statusBarMenu
    }
    
    
    // MARK: Actions
    
    @IBAction func quit(_ sender: AnyObject?) {
        NSApp.terminate(sender)
    }
    
    @IBAction func toggleLaunchOnLogin(_ sender: AnyObject?) {
        self.config?.launchOnLogin = !(self.config?.launchOnLogin ?? false)
    }
    
    @IBAction func openPreferences(_ sender: AnyObject?) {
        if self.preferencesWindowController == nil {
            self.preferencesWindowController = PreferencesWindowController.loadController()
            self.preferencesWindowController!.deviceDataSource = self.deviceDataSource
            self.preferencesWindowController!.config = self.config
        }
        self.preferencesWindowController?.showWindow(nil)
    }
    
    
    // MARK: NSMenuDelegate
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        NotificationCenter.default.post(name: ConnectionProvider.broadcastAnnouncementNotification, object: nil)
        
        if menu == self.statusBarMenu {
            self.refreshMenuDeviceList()
            self.launchOnLoginItem.state = (self.config?.launchOnLogin ?? false) ? NSOnState : NSOffState
        }
    }
    
    
    
    func refreshDeviceLists() {
        self.preferencesWindowController?.refreshDeviceList()
    }
    
    private func refreshMenuDeviceList() {
        // remove old device items
        
        var item = self.statusBarMenu.item(withTag: InterfaceElementTags.availableDeviceMenuItem.rawValue)
        while item != nil {
            self.statusBarMenu.removeItem(item!)
            item = self.statusBarMenu.item(withTag: InterfaceElementTags.availableDeviceMenuItem.rawValue)
        }
        
        // add new device items
        
        let devices = self.deviceDataSource?.pairedDevices ?? []
        guard devices.count > 0 else { return }
        
        var index = self.statusBarMenu.index(of: self.availableDevicesItem)
        assert(index != -1, "availableDevicesItem expected to be item of statusBarMenu")
        for device in devices {
            let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
            item.tag = InterfaceElementTags.availableDeviceMenuItem.rawValue
            item.submenu = DeviceMenu(device: device)
            item.image = batteryImage(for: device)
            index += 1
            self.statusBarMenu.insertItem(item, at: index)
        }
    }
    
    private func batteryImage(for device: Device) -> NSImage? {
        assert(self.serviceManager != nil, "serviceManager property is not setup correctly")
        guard let serviceManager = self.serviceManager else { return nil }
        guard let service = serviceManager.services.first(where: { $0 is BatteryService }) as? BatteryService else { return nil }
        guard let batteryStatus = service.statuses.first(where: { $0.key == device.id })?.value else { return nil }
        
        var rect = NSRect(x: 0, y: 0, width: 24, height: 13)
        let image = NSImage(size: rect.size, flipped: false) { _ in
            let mainIcon = #imageLiteral(resourceName: "batteryStatusIcon")
            assert(mainIcon.size == rect.size)
            mainIcon.draw(in: rect)
            
            let fullWidth: CGFloat = 16
            let chargedWidth = fullWidth * CGFloat(batteryStatus.currentCharge) / 100.0
            NSColor.black.set()
            NSRectFill(NSRect(x: 2, y: 2, width: chargedWidth, height: 8))
            
            if batteryStatus.isCharging {
                let chargingIcon = #imageLiteral(resourceName: "batteryStatusChargingIcon")
                let mask = NSImage(size: chargingIcon.size, flipped: false) { _ in
                    NSColor.white.setFill()
                    NSRectFill(rect)
                    chargingIcon.draw(in: rect)
                    return true
                }
                if let context = NSGraphicsContext.current(),
                    let cgMask = mask.cgImage(forProposedRect: &rect, context: context, hints: nil),
                    let cgMask2 = CGImage(maskWidth: cgMask.width, height: cgMask.height, bitsPerComponent: cgMask.bitsPerComponent, bitsPerPixel: cgMask.bitsPerPixel, bytesPerRow: cgMask.bytesPerRow, provider: cgMask.dataProvider!, decode: nil, shouldInterpolate: false) {
                    
                    chargingIcon.draw(in: rect, from: rect, operation: NSCompositingOperation.destinationOut, fraction: 1.0)
                    
                    context.cgContext.clip(to: rect, mask: cgMask2)
                    NSColor.black.setFill()
                    NSRectFill(rect)
                }
            }
            
            return true
        }
        
        image.isTemplate = true
        return image
    }
}
