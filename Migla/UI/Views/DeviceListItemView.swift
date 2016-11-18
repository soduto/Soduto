//
//  DeviceListItemView.swift
//  Migla
//
//  Created by Giedrius Stanevičius on 2016-09-01.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import Cocoa

public class DeviceListItemView: NSTableCellView {
    
    @IBOutlet weak var infoLabel: NSTextField!
    @IBOutlet weak var actionButton: NSButton!
    
    @IBAction func actionButtonAction(sender: NSButton) {
        guard let device = self.device else { return }
        
        switch device.state {
        case .unpaired:
            device.requestPairing()
            break
        case .paired:
            device.unpair()
            break
        default:
            break
        }
    }
    
    var device: Device? {
        didSet {
            if let device = self.device {
                self.textField?.stringValue = device.name
                self.infoLabel.stringValue = device.type.rawValue
                self.actionButton.title = device.state == .paired ? NSLocalizedString("Unpair", comment: "action") : NSLocalizedString("Pair", comment: "action")
                self.actionButton.isEnabled = device.state != .pairing
                self.actionButton.isHidden = false
                
                switch device.type {
                case .Desktop:
                    self.imageView?.image = #imageLiteral(resourceName: "desktopIcon")
                case .Phone:
                    self.imageView?.image = #imageLiteral(resourceName: "phoneIcon")
                default: break
                }
            }
            else {
                self.textField?.stringValue = ""
                self.infoLabel.stringValue = ""
                self.actionButton.isHidden = true
                self.imageView?.isHidden = true
            }
        }
    }
    
}
