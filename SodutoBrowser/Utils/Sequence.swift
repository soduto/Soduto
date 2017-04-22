//
//  Sequence.swift
//  Soduto
//
//  Created by Giedrius on 2017-04-12.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

extension Sequence {
    
    public func every(condition: (Self.Iterator.Element) throws -> Bool) rethrows -> Bool {
        for element in self {
            guard try condition(element) else { return false }
        }
        return true
    }
    
}
