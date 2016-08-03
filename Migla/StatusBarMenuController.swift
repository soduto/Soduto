//
//  StatusBarMenuController.swift
//  Migla
//
//  Created by Giedrius Stanevicius on 2016-07-26.
//  Copyright © 2016 Migla. All rights reserved.
//

import Foundation
import AppKit

public class StatusBarMenuController: NSObject {
    
    @IBAction func quit(_ sender: AnyObject?) {
        NSApp.terminate(sender)
    }
    
}
