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
//        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
    }

    
    // MARK: Private
    
    private func newBrowserWindow(with fileSystem: FileSystem) {
        let windowController = BrowserWindowController(fileSystem: fileSystem)
        windowController.delegate = self
        browserWindowControllers.append(windowController)
    }
}
