//
//  DevicePreferencesViewController.swift
//  Soduto
//
//  Created by Giedrius on 2017-07-22.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

class DevicePreferencesViewController: NSViewController {
    
    // MARK: Properties
    
    var deviceDataSource: DeviceDataSource?
    var config: HostConfiguration?
    
    @IBOutlet weak var hostNameLabel: NSTextField!
    
    private weak var deviceListController: DeviceListController?
    
    
    // MARK: Public methods
    
    func refreshDeviceList() {
        self.deviceListController?.refreshDeviceList()
    }
    
    
    // MARK: NSViewController
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        if let hostName = config?.hostDeviceName {
            let label = NSMutableAttributedString(string: NSLocalizedString("This device is discoverable as", comment: "") + ":")
            label.addAttributes([
                NSAttributedStringKey.foregroundColor: NSColor.disabledControlTextColor,
                NSAttributedStringKey.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize())
                ], range: NSMakeRange(0, label.length))
            label.append(NSAttributedString(string: "\n\(hostName)"))
            label.setAlignment(.center, range: NSMakeRange(0, label.length))
            self.hostNameLabel.attributedStringValue = label
        }
        else {
            self.hostNameLabel.stringValue = ""
        }
        
        self.deviceListController?.deviceDataSource = self.deviceDataSource
        self.deviceListController?.refreshDeviceList()
        self.view.layoutSubtreeIfNeeded()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let deviceListController = segue.destinationController as? DeviceListController {
            self.deviceListController = deviceListController
        }
    }
    
    
    
}
