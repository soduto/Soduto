//
//  IO.m
//  Soduto
//
//  Created by Giedrius Stanevičius on 2017-01-10.
//  Copyright © 2017 Soduto. All rights reserved.
//

#import "IO.h"

BOOL tryLock(NSString *path) {
    int fd = open([path UTF8String], O_CREAT);
    if (fd == -1) {
        // something failed, just give up
        return YES;
    }
    close(fd);
    
    fd = open([path UTF8String], O_EXLOCK | O_NONBLOCK | O_RDWR);
    if (fd == -1 && errno == EWOULDBLOCK) {
        // file is locked
        return NO;
    }
    return YES;
}
