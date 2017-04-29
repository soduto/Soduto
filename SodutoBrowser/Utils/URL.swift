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
    
    public func renamed(to newName: String) -> URL {
        return self.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: self.hasDirectoryPath)
    }
    
    public func relativeTo(_ baseUrl: URL) -> URL {
        let absSelf = self.absoluteURL
        let baseUrl = baseUrl.absoluteURL
        
        assert(absSelf.isUnder(baseUrl) || baseUrl == absSelf, "baseUrl [\(baseUrl)] expected to be prefix of [\(absSelf)].")
        guard absSelf.isUnder(baseUrl) || baseUrl == absSelf else { return absSelf }
        
        let relativeComponents = absSelf.pathComponents.suffix(from: baseUrl.pathComponents.count)
        guard var relativeUrl = URL(string: ".", relativeTo: baseUrl) else { assertionFailure("Could not contruct relative URL with base [\(baseUrl)]"); return absSelf }
        for component in relativeComponents {
            relativeUrl.appendPathComponent(component)
        }
        return relativeUrl
    }
    
    public func rebasing(to newBaseUrl: URL) -> URL {
        assert(baseURL != nil, "Expected relative URL: \(self).")
        guard baseURL != nil else { return self }
        guard let rebased = URL(string: relativeString, relativeTo: newBaseUrl) else { assertionFailure("Failed to create relative URL from [\(self)] rebased to [\(newBaseUrl)]."); return self }
        return rebased
    }
    
    public func rebasing(from oldBaseUrl: URL, to newBaseUrl: URL) -> URL {
        return self.relativeTo(oldBaseUrl).rebasing(to: newBaseUrl)
    }
    
}
