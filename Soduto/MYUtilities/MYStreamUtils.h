//
//  MYStreamUtils.h
//  MYUtilities
//
//  Created by Jens Alfke on 7/25/12.
//  Copyright (c) 2012 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSInputStream (MYUtils)

/** Reads from the stream and passes the read bytes/length to the supplied block.
    Note: The data buffer passed to the block is only valid for the duration of the call.
    @param block  Called if the read succeeds.
    @return  YES if the read succeeds, NO if it fails. */
- (BOOL) my_readBytes: (void(^)(const void* bytes, NSUInteger length))block;

/** Reads from the stream and passes the read data to the supplied block.
    Note: The NSData object passed to the block is only valid for the duration of the call; it's created with -initWithBytesNoCopy so it has a direct pointer to a temporary data buffer. If you need the data after the block returns, make a copy of it.
    @param block  Called if the read succeeds.
    @return  YES if the read succeeds, NO if it fails. */
- (BOOL) my_readData: (void(^)(NSData* data))block;

@end
