//
//  HoverButton.swift
//  Soduto
//
//  Created by Giedrius on 2017-05-08.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

/// Button with exposed mouse eneter/exit handlers
public class HoverButton: NSButton {
    
    public var mouseEneteredHandler: ((NSEvent, NSButton)->Void)?
    public var mouseExitedHandler: ((NSEvent, NSButton)->Void)?
    
    private var trackingArea: NSTrackingArea?
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        self.mouseEneteredHandler?(event, self)
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        self.mouseExitedHandler?(event, self)
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let trackingArea = NSTrackingArea(rect: self.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }
    
}
