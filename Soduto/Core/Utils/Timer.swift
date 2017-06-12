//
//  Timer.swift
//  Soduto
//
//  Created by Giedrius on 2017-04-05.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Foundation

extension Timer {
    
    /// Compatibility function to create timer with eecution block on pre-10.12 macOS systems
    public class func compatTimer(withTimeInterval timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer)->Void) -> Timer {
        let blockHolder = TimerBlockHolder(block: block)
        return Timer(timeInterval: timeInterval, target: blockHolder, selector: #selector(TimerBlockHolder.execute(_:)), userInfo: nil, repeats: repeats)
    }
    
    /// Compatibility function to create timer with eecution block on pre-10.12 macOS systems
    public class func compatScheduledTimer(withTimeInterval timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer)->Void) -> Timer {
        let blockHolder = TimerBlockHolder(block: block)
        return Timer.scheduledTimer(timeInterval: timeInterval, target: blockHolder, selector: #selector(TimerBlockHolder.execute(_:)), userInfo: nil, repeats: repeats)
    }
    
}

fileprivate class TimerBlockHolder {
    let block: (Timer)->Void
    
    init(block: @escaping (Timer)->Void) {
        self.block = block
    }
    
    @objc dynamic func execute(_ timer: Timer) {
        block(timer)
    }
}
