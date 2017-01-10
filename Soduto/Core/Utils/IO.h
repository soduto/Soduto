//
//  IO.h
//  Soduto
//
//  Created by Giedrius Stanevičius on 2017-01-10.
//  Copyright © 2017 Soduto. All rights reserved.
//

#import <Foundation/Foundation.h>

/// Try locking a file. If succeeded - the lock remains for whole app running time
BOOL tryLock(NSString *path);
