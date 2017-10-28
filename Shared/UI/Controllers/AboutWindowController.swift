//
//  AboutWindowController.swift
//  Soduto
//
//  Created by Giedrius on 2017-10-19.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation
import Cocoa

public class AboutWindowController: NSWindowController {
    
    var dismissHandler: ((AboutWindowController)->Void)?
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private static var controller: AboutWindowController?
    
    public static func showAboutWindow() {
        if controller == nil {
            let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "AboutWindow"), bundle: nil)
            controller = storyboard.instantiateInitialController() as? AboutWindowController
        }
        assert(controller != nil, "Could not load about window controller.")
        NSApp.activate(ignoringOtherApps: true)
        controller?.dismissHandler = { _ in controller = nil }
        controller?.showWindow(nil)
    }
    
    public override func windowDidLoad() {
        super.windowDidLoad()
        
        // IB does not set it correctly on 10.12
        self.window?.titleVisibility = .hidden
        self.window?.styleMask.insert(.fullSizeContentView)
        self.window?.titlebarAppearsTransparent = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }
    
    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow == self.window else { return }
        dismissHandler?(self)
    }
}

public class AboutViewController: NSViewController {
    
    // MARK: Properties
    
    @IBOutlet weak var nameLabel: NSTextField!
    @IBOutlet weak var versionLabel: NSTextField!
    @IBOutlet weak var copyrightLabel: NSTextField!
    @IBOutlet weak var iconView: NSImageView!
    @IBOutlet weak var licenseButton: NSButton!
    @IBOutlet weak var acknowledgementsButton: NSButton!
    
    private var licensePath: String? { return Bundle.main.path(forResource: "License", ofType: "html") }
    private var acknowledgmentsPath: String? { return Bundle.main.path(forResource: "Acknowledgements", ofType: "html") }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let bundle = Bundle.main
        
        self.nameLabel.stringValue = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ""
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                self.versionLabel.stringValue = String.localizedStringWithFormat(NSLocalizedString("Version %@ (%@)", comment: ""), version, build)
            }
            else {
                self.versionLabel.stringValue = String.localizedStringWithFormat(NSLocalizedString("Version %s", comment: ""), version)
            }
        }
        else {
            self.versionLabel.stringValue = ""
        }
        self.copyrightLabel.stringValue = (bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String) ?? ""
        
        self.iconView.image = NSApp.applicationIconImage
        
        self.licenseButton.isEnabled = licensePath != nil
        self.acknowledgementsButton.isEnabled = acknowledgmentsPath != nil
    }
    
    @IBAction func showLicenceAgreement(_ sender: Any?) {
        guard let path = licensePath else { return }
        NSWorkspace.shared.openFile(path)
    }
    
    @IBAction func showAcknowledgments(_ sender: Any?) {
        guard let path = acknowledgmentsPath else { return }
        NSWorkspace.shared.openFile(path)
    }
}

