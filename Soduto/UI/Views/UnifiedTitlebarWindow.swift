//
//  UnifiedTitlebarWindow.swift
//  Soduto
//
//  Created by Giedrius on 2017-02-02.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

class UnifiedTitlebarWindow: NSWindow {
    
    @IBOutlet weak var titleLabel: NSTextField?
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        
        self.titleVisibility = .hidden
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleLabel(notification:)), name: NSWindow.didBecomeKeyNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleLabel(notification:)), name: NSWindow.didResignKeyNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleLabel(notification:)), name: NSApplication.didBecomeActiveNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleLabel(notification:)), name: NSApplication.didResignActiveNotification, object: self)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        
        titleLabel?.stringValue = title
    }
    
    @objc dynamic private func updateTitleLabel(notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard window === self else { return }
        titleLabel?.textColor = NSApp.isActive && self.isKeyWindow ? NSColor.windowFrameTextColor : NSColor.windowFrameTextColor
    }
}
