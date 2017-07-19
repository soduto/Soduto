//
//  IO.m
//  Soduto
//
//  Created by Giedrius Stanevičius on 2017-01-10.
//  Copyright © 2017 Soduto. All rights reserved.
//

#import "IO.h"

BOOL tryLock(NSString *path) {
    int fd = open([path UTF8String], O_CREAT | O_EXCL, S_IRUSR | S_IWUSR);
    if (fd == -1 && errno != EEXIST) {
        // something failed
        return NO;
    }
    close(fd);
    
    fd = open([path UTF8String], O_EXLOCK | O_NONBLOCK | O_RDWR);
    if (fd == -1 && errno == EWOULDBLOCK) {
        // file is locked
        return NO;
    }
//    if (fd == -1) {
//        NSLog(@"errno=%d", errno);
//    }
    return YES;
}
