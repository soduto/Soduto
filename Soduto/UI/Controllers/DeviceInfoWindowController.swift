//
//  DeviceInfoWindowController.swift
//  Soduto
//
//  Created by Giedrius on 2017-07-14.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

class DeviceInfoWindowController: NSWindowController {
    
    var device: Device? { didSet { updateInfo() } }
    
    @IBOutlet weak var deviceTypeImage: NSImageView?
    @IBOutlet weak var deviceNameLabel: NSTextField?
    @IBOutlet weak var statusLabel: NSTextField?
    @IBOutlet weak var deviceIDLabel: NSTextField?
    @IBOutlet weak var localCertificateLabel: NSTextField?
    @IBOutlet weak var remoteCertificateLabel: NSTextField?
    
    static func loadController() -> DeviceInfoWindowController {
        return DeviceInfoWindowController(windowNibName: NSNib.Name(rawValue: "DeviceInfoWindow"))
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        updateInfo()
    }
    
    @IBAction func testConnection(_ sender: Any?) {
        // TODO:
    }
    
    @IBAction func done(_ sender: Any?) {
        guard let window = self.window else { return }
        if window.isSheet {
            window.sheetParent?.endSheet(window)
        }
        else {
            window.close()
        }
    }
    
    private func updateInfo() {
        if let device = device {
            self.deviceTypeImage?.image = device.type.icon
            self.deviceNameLabel?.stringValue = device.name
            let deviceTypeInfo: String = device.type != .Unknown ? NSLocalizedString(device.type.rawValue, comment: "Device type") : ""
            let deviceStatusInfo: String = device.isReachable ? NSLocalizedString("reachable", comment: "Device status") : NSLocalizedString("unreachable", comment: "Device status")
            self.statusLabel?.stringValue = deviceTypeInfo.isEmpty ? deviceStatusInfo : "\(deviceTypeInfo) - \(deviceStatusInfo)"
            self.deviceIDLabel?.stringValue = device.id
            self.localCertificateLabel?.stringValue = device.hostCertificate != nil ? CertificateUtils.digestString(for: device.hostCertificate!) : "-"
            self.remoteCertificateLabel?.stringValue = device.peerCertificate != nil ? CertificateUtils.digestString(for: device.peerCertificate!) : "-"
        }
        else {
            self.deviceTypeImage?.image = nil
            self.deviceNameLabel?.stringValue = "-"
            self.statusLabel?.stringValue = "-"
            self.deviceIDLabel?.stringValue = "-"
            self.localCertificateLabel?.stringValue = "-"
            self.remoteCertificateLabel?.stringValue = "-"
        }
    }
}
