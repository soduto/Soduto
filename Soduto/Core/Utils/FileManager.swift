//
//  FileManager.swift
//  Soduto
//
//  Created by Giedrius on 2017-04-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

extension FileManager {
    
    public var compatTemporaryDirectory: URL {
        if #available(OSX 10.12, *) {
            return temporaryDirectory
        }
        else {
            return (try? url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }
    
}
