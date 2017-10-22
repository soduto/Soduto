//
//  StatusBarMenuController.swift
//  Soduto
//
//  Created by Giedrius Stanevicius on 2016-07-26.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import AppKit

public class StatusBarMenuController: NSObject, NSWindowDelegate, NSMenuDelegate, NSDraggingDestination {
    
    @IBOutlet weak var statusBarMenu: NSMenu!
    @IBOutlet weak var availableDevicesItem: NSMenuItem!
    @IBOutlet weak var launchOnLoginItem: NSMenuItem!
    
    public var deviceDataSource: DeviceDataSource?
    public var serviceManager: ServiceManager?
    public var config: Configuration?
    
    let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    
    lazy var preferencesWindowController: PreferencesWindowController? = {
        let controller = PreferencesWindowController.loadController()
        controller.deviceDataSource = self.deviceDataSource
        controller.config = self.config
        return controller
    }()
    
    private var dragOperationPerformed: Bool = false
    
    override public func awakeFromNib() {
        let statusBarIcon = #imageLiteral(resourceName: "statusBarIcon")
        statusBarIcon.isTemplate = true
        
        self.statusBarItem.image = statusBarIcon
        self.statusBarItem.menu = self.statusBarMenu
        
        let dragTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType(rawValue: kUTTypeURL as String),
            NSPasteboard.PasteboardType(rawValue: kUTTypeText as String) ]
        self.statusBarItem.button?.window?.registerForDraggedTypes(dragTypes)
        self.statusBarItem.button?.window?.delegate = self
    }
    
    
    // MARK: Actions
    
    @IBAction func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }
    
    @IBAction func toggleLaunchOnLogin(_ sender: Any?) {
        self.config?.launchOnLogin = !(self.config?.launchOnLogin ?? false)
    }
    
    @IBAction func openPreferences(_ sender: Any?) {
        self.preferencesWindowController?.showWindow(nil)
    }
    
    @IBAction func showAboutWindow(_ sender: Any?) {
        AboutWindowController.showAboutWindow()
    }
    
    
    // MARK: Drag'n'Drop
    
    public dynamic func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperationPerformed = false
        for service in self.serviceManager?.services ?? [] {
            guard let destination = service as? NSDraggingDestination else { continue }
            guard let operation = destination.draggingEntered?(sender) else { continue }
            guard !operation.isEmpty else { continue }
            return operation
        }
        return []
    }
    
    public dynamic func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperationPerformed = false
        for service in self.serviceManager?.services ?? [] {
            guard let destination = service as? NSDraggingDestination else { continue }
            guard let operation = destination.draggingUpdated?(sender) else { continue }
            guard !operation.isEmpty else { continue }
            return operation
        }
        return []
    }
    
    public dynamic func draggingEnded(_ sender: NSDraggingInfo) {
        for service in self.serviceManager?.services ?? [] {
            guard let destination = service as? NSDraggingDestination else { continue }
            destination.draggingEnded?(sender)
        }
        
        // A workaround for items dragged from dock stack - in such case performDragOperation is not called
        if !dragOperationPerformed && self.statusBarItem.button?.frame.contains(sender.draggingLocation()) == true {
            _ = performDragOperation(sender)
        }
    }
    
    public dynamic func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragOperationPerformed = true
        for service in self.serviceManager?.services ?? [] {
            guard let destination = service as? NSDraggingDestination else { continue }
            guard destination.performDragOperation?(sender) == true else { continue }
            return true
        }
        return false
    }
    
    
    // MARK: NSMenuDelegate
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        NotificationCenter.default.post(name: ConnectionProvider.broadcastAnnouncementNotification, object: nil)
        
        if menu == self.statusBarMenu {
            self.refreshMenuDeviceList()
            self.launchOnLoginItem.state = (self.config?.launchOnLogin ?? false) ? NSControl.StateValue.on : NSControl.StateValue.off
        }
    }
    
    
    // MARK: Public methods
    
    func refreshDeviceLists() {
        self.preferencesWindowController?.refreshDeviceLists()
    }
    
    
    // MARK: Private methods
    
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
            let chargedWidth: CGFloat = fullWidth * CGFloat(batteryStatus.currentCharge) / 100.0
            NSColor.black.set()
            NSRect(x: 2, y: 2, width: chargedWidth, height: 8).fill()
            
            if batteryStatus.isCharging {
                let chargingIcon = #imageLiteral(resourceName: "batteryStatusChargingIcon")
                let mask = NSImage(size: chargingIcon.size, flipped: false) { _ in
                    NSColor.white.setFill()
                    rect.fill()
                    chargingIcon.draw(in: rect)
                    return true
                }
                if let context = NSGraphicsContext.current,
                    let cgMask = mask.cgImage(forProposedRect: &rect, context: context, hints: nil),
                    let cgMask2 = CGImage(maskWidth: cgMask.width, height: cgMask.height, bitsPerComponent: cgMask.bitsPerComponent, bitsPerPixel: cgMask.bitsPerPixel, bytesPerRow: cgMask.bytesPerRow, provider: cgMask.dataProvider!, decode: nil, shouldInterpolate: false) {
                    
                    chargingIcon.draw(in: rect, from: rect, operation: NSCompositingOperation.destinationOut, fraction: 1.0)
                    
                    context.cgContext.clip(to: rect, mask: cgMask2)
                    NSColor.black.setFill()
                    rect.fill()
                }
            }
            
            return true
        }
        
        image.isTemplate = true
        return image
    }
}
