//
//  FileSystem.swift
//  Soduto
//
//  Created by Giedrius on 2017-03-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

enum FileSystemError: Error {
    case invalidUrl(url: URL)
    case loadFailed(url: URL, reason: String)
    case deleteFailed(url: URL, reason: String)
    case copyFailed(url: URL, reason: String)
    case moveFailed(url: URL, reason: String)
    case fileExists(url: URL)
    case fileDoesNotExist(url: URL)
    case fileSystemUnreachable(url: URL)
}

struct Place {
    let name: String
    let url: URL
    init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

protocol FileSystem: class {
    
    var name: String { get }
    var rootUrl: URL { get }
    var places: [Place] { get }
    
    /// Read file list for provided URL. URL must reside under rootUrl.
    func load(_ url: URL, completionHandler: @escaping ([FileItem]?, Error?)->Void)
    
    /// Delete file at provided URL. URL must reside under rootUrl
    func delete(_ url: URL, completionHandler: @escaping (Error?)->Void)
    
    /// Copy file from one place to another. At least one URL must reside under rootUrl. destUrl must indicate the
    /// final copied file name, not the directory containing it.
    func copy(_ srcUrl: URL, to destUrl: URL, completionHandler: @escaping (Error?)->Void)
    
    /// Move file from one place to another. Both URLs must reside under rootUrl
    func move(_ srcUrl: URL, to destUrl: URL, completionHandler: @escaping (Error?)->Void)
}

extension FileSystem {
    
    var defaultPlace: Place {
        if self.places.count > 0 {
            return self.places[0]
        }
        else {
            return Place(name: NSLocalizedString("Root", comment: "directory"), url: self.rootUrl)
        }
    }
    
    func isUnderRoot(_ url: URL) -> Bool {
        return url.isSubpathOf(self.rootUrl, strict: true)
    }
}
