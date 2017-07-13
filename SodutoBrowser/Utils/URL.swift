//
//  URL.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-12.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

extension URL {
    
    public static func url(scheme: String? = nil, host: String? = nil, port: UInt16? = nil, user: String? = nil, password: String? = nil, path: String? = nil, fragment: String? = nil) -> URL? {
        let urlComponents = NSURLComponents()
        urlComponents.scheme = scheme
        urlComponents.host = host
        urlComponents.port = port != nil ? port! as NSNumber : nil
        urlComponents.user = user
        urlComponents.password = password
        urlComponents.path = path
        urlComponents.fragment = fragment
        return urlComponents.url
    }
    
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
            relativeUrl.appendPathComponent(component, isDirectory: absSelf.hasDirectoryPath)
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
    
    public func nonExisting(validator: (URL)->Bool) -> URL {
        var result = self
        while !validator(result) {
            result = result.alternativeForDuplicate()
        }
        return result
    }
    
    public func alternativeForDuplicate() -> URL {
        let pathExtension = self.pathExtension
        let urlWithoutExtension = !pathExtension.isEmpty ? self.deletingPathExtension() : self
        let nameWithoutExtension = urlWithoutExtension.lastPathComponent
        
        let updatedNameWithoutExtension: String
        let regex = try! NSRegularExpression(pattern: "(.*)[(](\\d+)[)]$")
        let range = NSMakeRange(0, nameWithoutExtension.characters.count)
        if let match = regex.firstMatch(in: nameWithoutExtension, options: [], range: range){
            let prefix = substring(string: nameWithoutExtension, range: match.range(at: 1))
            let numberStr = substring(string: nameWithoutExtension, range: match.range(at: 2))
            let number = Int(numberStr) ?? 0
            updatedNameWithoutExtension = "\(prefix)(\(number + 1))"
        }
        else {
            updatedNameWithoutExtension = "\(nameWithoutExtension)(1)"
        }
        
        let updatedUrlWithoutExtension = self.deletingLastPathComponent().appendingPathComponent(updatedNameWithoutExtension, isDirectory: hasDirectoryPath)
        let updatedUrl = !pathExtension.isEmpty ? updatedUrlWithoutExtension.appendingPathExtension(pathExtension) : updatedUrlWithoutExtension
        return updatedUrl
    }
    
    public var regularFileURL: URL {
        let lastPathComponent = self.lastPathComponent
        guard !lastPathComponent.isEmpty else { return self }
        return self.deletingLastPathComponent().appendingPathComponent(lastPathComponent)
    }
    
    
    // MARK: Private methods
    
    private func substring(string: String, range: NSRange) -> String {
        let startIndex = string.index(string.startIndex, offsetBy: range.location)
        let endIndex = string.index(startIndex, offsetBy: range.length)
        let stringRange = startIndex ..< endIndex
        return string.substring(with: stringRange)
    }
    
}
