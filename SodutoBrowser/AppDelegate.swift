//
//  AppDelegate.swift
//  SodutoBrowser
//
//  Created by Giedrius on 2017-03-03.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, BrowserWindowControllerDelegate {
    
    // MARK: Types
    
    struct MenuItemTags {
        // Go menu
        static let back: Int = 1001
        static let forward: Int = 1002
        static let enclosingFolder: Int = 1003
        
        // View menu
        static let toggleHiddenFiles: Int = 2001
        static let foldersAlwaysFirst: Int = 2101
        
        // File menu
        static let deleteFiles: Int = 3001
        static let newFolder: Int = 3002
        static let newWindow: Int = 3003
        static let closeTabGroup: Int = 3004
        static let close: Int = 3005
        static let newTab: Int = 3006
    }
    
    struct ToolbarItemTags {
        static let backForward: Int = 50001
    }
    
    
    // MARK: Properties

    private(set) var browserWindowControllers: [BrowserWindowController] = []
    
    var keyBrowserWindowController: BrowserWindowController? {
        return NSApp.keyWindow?.windowController as? BrowserWindowController
    }
    
    
    // MARK: NSApplicationDelegate
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        if #available(OSX 10.12, *) {
            NSWindow.allowsAutomaticWindowTabbing = true
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let fs = try! SftpFileSystem(name: "SFTP", host: "286840.s.dedikuoti.lt", user: "giedrius", password: "gargantuki", path: "/")
        newBrowserWindow(with: fs)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    
    // MARK: BrowserWindowControllerDelegate
    
    func browserWindowWillClose(_ controller: BrowserWindowController) {
        guard let index = self.browserWindowControllers.index(of: controller) else { return }
        self.browserWindowControllers.remove(at: index)
    }
    
    
    // MARK: Actions
    
    @IBAction func newWindow(_ sender: Any?) {
        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
        newBrowserWindow(with: controller.fileSystem)
    }
    
    @IBAction func newTab(_ sender: Any?) {
        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
        let newController = newBrowserWindow(with: controller.fileSystem)
        if #available(OSX 10.12, *) {
            if let newWindow = newController.window {
                controller.window?.addTabbedWindow(newWindow, ordered: .above)
            }
        }
    }
    
    @IBAction func closeTabGroup(_ sender: Any?) {
        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
        if #available(OSX 10.12, *) {
            controller.window?.tabbedWindows?.forEach { $0.close() }
        }
        else {
            controller.window?.close()
        }
    }
    
    @IBAction func close(_ sender: Any?) {
        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
        controller.window?.close()
    }
    
    
    // MARK: Menu
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
        case MenuItemTags.newWindow: return keyBrowserWindowController != nil
        case MenuItemTags.newTab:
            if #available(OSX 10.12, *) {
                menuItem.isHidden = false
            }
            else {
                menuItem.isHidden = true
            }
            return keyBrowserWindowController != nil
        case MenuItemTags.closeTabGroup:
            let available = isWindowTabbed(keyBrowserWindowController?.window)
            menuItem.isHidden = !available
            return available
        case MenuItemTags.close:
            let controller = keyBrowserWindowController
            menuItem.title = isWindowTabbed(controller?.window) ? NSLocalizedString("Close Tab", comment: "menu item") : NSLocalizedString("Close Window", comment: "menu item")
            return keyBrowserWindowController != nil
        default: return false
        }
    }

    
    // MARK: Private
    
    @discardableResult private func newBrowserWindow(with fileSystem: FileSystem) -> BrowserWindowController {
        let windowController = BrowserWindowController(fileSystem: fileSystem)
        windowController.delegate = self
        browserWindowControllers.append(windowController)
        return windowController
    }
    
    private func isWindowTabbed(_ window: NSWindow?) -> Bool {
        if #available(OSX 10.12, *) {
            return (window?.tabbedWindows?.count ?? 0) > 1
        } else {
            return false
        }
    }
}
