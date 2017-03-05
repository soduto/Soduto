//
//  AppDelegate.swift
//  SodutoBrowser
//
//  Created by Giedrius on 2017-03-03.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    struct MenuItemTags {
        static let back: Int = 1001
        static let forward: Int = 1002
        static let enclosingFolder: Int = 1003
    }

    private var browserWindowController: BrowserWindowController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.browserWindowController = BrowserWindowController(fileSystem: LocalFileSystem())
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

