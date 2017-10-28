//
//  URL.swift
//  Soduto
//
//  Created by Giedrius Stanevičius on 2016-12-03.
//  Copyright © Soduto Soduto. All rights reserved.
//

import Foundation

public extension URL {
    
    public init(forDownloadedFile fileName: String) throws {
        let fileUrl = URL(fileURLWithPath: "").appendingPathComponent(fileName, isDirectory: false)
        let dirUrl = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: fileUrl, create: true)
        self.init(fileURLWithPath: fileUrl.relativeString, relativeTo: dirUrl)
    }
    
    public func alternativeForDuplicate() -> URL {
        let pathExtension = self.pathExtension
        let urlWithoutExtension = !pathExtension.isEmpty ? self.deletingPathExtension() : self
        let pathWithoutExtension = urlWithoutExtension.path
        
        let updatedPathWithoutExtension: String
        let regex = try! NSRegularExpression(pattern: "(.*)[(](\\d+)[)]$")
        let range = NSMakeRange(0, pathWithoutExtension.characters.count)
        if let match = regex.firstMatch(in: pathWithoutExtension, options: [], range: range){
            let prefix = substring(string: pathWithoutExtension, range: match.range(at: 1))
            let numberStr = substring(string: pathWithoutExtension, range: match.range(at: 2))
            let number = Int(numberStr) ?? 0
            updatedPathWithoutExtension = "\(prefix)(\(number + 1))"
        }
        else {
            updatedPathWithoutExtension = "\(urlWithoutExtension.path)(1)"
        }
        
        let updatedUrlWithoutExtension = URL(fileURLWithPath: updatedPathWithoutExtension)
        let updatedUrl = !pathExtension.isEmpty ? updatedUrlWithoutExtension.appendingPathExtension(pathExtension) : updatedUrlWithoutExtension
        return updatedUrl
    }
    
    
    // MARK: Private methods
    
    private func substring(string: String, range: NSRange) -> String {
        let startIndex = string.index(string.startIndex, offsetBy: range.location)
        let endIndex = string.index(startIndex, offsetBy: range.length)
        return String(string[startIndex ..< endIndex])
    }
}
