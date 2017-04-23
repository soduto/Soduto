//
//  URL.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-12.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

extension URL {
    
    public func isUnder(_ otherUrl: URL) -> Bool {
        guard self.scheme == otherUrl.scheme else { return false }
        guard self.host == otherUrl.host else { return false }
        guard self.port == otherUrl.port else { return false }
        guard self.user == otherUrl.user else { return false }
        let pathComponents1 = self.pathComponents
        let pathComponents2 = otherUrl.pathComponents
        guard pathComponents1.count > pathComponents2.count else { return false }
        for i in 0 ..< pathComponents2.count {
            guard pathComponents1[i] == pathComponents2[i] else { return false }
        }
        return true
    }
    
    public func movedTo(_ destUrl: URL) -> URL {
        assert(destUrl.hasDirectoryPath, "Destination url (\(destUrl)) expected to be a directory.")
        return destUrl.appendingPathComponent(self.lastPathComponent, isDirectory: self.hasDirectoryPath)
    }
    
}
