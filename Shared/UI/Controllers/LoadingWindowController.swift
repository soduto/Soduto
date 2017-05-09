//
//  LoadingViewsController.swift
//  Soduto
//
//  Created by Giedrius on 2017-05-08.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

public class LoadingWindowController: NSWindowController {
    
    // MARK: Properties
    
    public var dismissHandler: ((LoadingWindowController)->Void)?
    
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var hintLabel: NSTextField!
    @IBOutlet weak var imageView: NSImageView!
    @IBOutlet weak var cancelButton: HoverButton!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    

    static func loadController() -> LoadingWindowController {
        let controller = LoadingWindowController(windowNibName: "LoadingWindow")
        _ = controller.window // make sure window and its components are loaded for receiver
        return controller
    }
    
    
    public override func showWindow(_ sender: Any?) {
        // make sure window is loaded
        _ = self.window
        
        self.progressIndicator.startAnimation(true)
        
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
    }
    
    public override func dismissController(_ sender: Any?) {
        super.dismissController(sender)
        dismissHandler?(self)
    }
    
    public override func windowDidLoad() {
        super.windowDidLoad()
        
        self.window?.titlebarAppearsTransparent = true
        
        self.cancelButton.mouseEneteredHandler = { [weak self] _, _ in self?.hintLabel.animator().alphaValue = 1 }
        self.cancelButton.mouseExitedHandler = { [weak self] _, _ in self?.hintLabel.animator().alphaValue = 0 }
    }
}

