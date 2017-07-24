//
//  PreferencesWindowController.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-08-30.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation
import Cocoa

public class PreferencesWindowController: NSWindowController {
    
    var deviceDataSource: DeviceDataSource? {
        didSet { self.preferencesTabViewController?.deviceDataSource = self.deviceDataSource }
    }
    var config: HostConfiguration? {
        didSet { self.preferencesTabViewController?.config = self.config }
    }
    
    var preferencesTabViewController: PreferencesTabViewController? {
        assert(self.contentViewController is PreferencesTabViewController)
        return self.contentViewController as? PreferencesTabViewController
    }
    
    static func loadController() -> PreferencesWindowController {
        let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "PreferencesWindow"), bundle: nil)
        return storyboard.instantiateInitialController() as! PreferencesWindowController
    }
    
    func refreshDeviceLists() {
        self.preferencesTabViewController?.refreshDeviceLists()
    }
    
    public override func windowDidLoad() {
        super.windowDidLoad()
        
        let screenRect = NSScreen.main()?.frame ?? NSRect.zero
        self.window?.setFrame(NSRect(x: screenRect.width / 2 - 340, y: screenRect.height / 2 - 200, width: 680, height: 400), display: false)
        
        self.preferencesTabViewController?.deviceDataSource = self.deviceDataSource
        self.preferencesTabViewController?.config = self.config
    }
    
    public override func showWindow(_ sender: Any?) {
        // make sure window is loaded
        let _ = self.window
        
        NSApp.activate(ignoringOtherApps: true)
        
        super.showWindow(sender)
    }
    
}


// MARK: -

class PreferencesTabViewController: NSTabViewController {
    
    var deviceDataSource: DeviceDataSource? { didSet { updateDeviceDataSourceForSelectedTab() } }
    var config: HostConfiguration? { didSet { updateConfigForSelectedTab() } }
    
    override var selectedTabViewItemIndex: Int {
        didSet {
            updateDeviceDataSourceForSelectedTab()
            updateConfigForSelectedTab()
            refreshDeviceLists()
        }
    }
    
    func refreshDeviceLists() {
        guard !self.tabView.tabViewItems.isEmpty else { return }
        let selectedTabViewItem = self.tabView.tabViewItem(at: selectedTabViewItemIndex)
        if let controller = selectedTabViewItem.viewController as? DevicePreferencesViewController {
            controller.refreshDeviceList()
        }
        else if let controller = selectedTabViewItem.viewController as? ServicePreferencesViewController {
            controller.refreshDeviceList()
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        updateDeviceDataSourceForSelectedTab()
        updateConfigForSelectedTab()
    }
    
    private func updateDeviceDataSourceForSelectedTab() {
        guard !self.tabView.tabViewItems.isEmpty else { return }
        let selectedTabViewItem = self.tabView.tabViewItem(at: selectedTabViewItemIndex)
        if let controller = selectedTabViewItem.viewController as? DevicePreferencesViewController {
            controller.deviceDataSource = self.deviceDataSource
        }
        else if let controller = selectedTabViewItem.viewController as? ServicePreferencesViewController {
            controller.deviceDataSource = deviceDataSource
        }
    }
    
    private func updateConfigForSelectedTab() {
        guard !self.tabView.tabViewItems.isEmpty else { return }
        let selectedTabViewItem = self.tabView.tabViewItem(at: selectedTabViewItemIndex)
        if let controller = selectedTabViewItem.viewController as? DevicePreferencesViewController {
            controller.config = self.config
        }
    }
}
