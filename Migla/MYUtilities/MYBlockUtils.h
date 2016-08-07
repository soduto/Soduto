//
//  MYBlockUtils.h
//  MYUtilities
//
//  Created by Jens Alfke on 1/28/12.
//  Copyright (c) 2012 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "CollectionUtils.h"


/** Block-based delayed perform. Even works on NSOperationQueues that don't have runloops. */
void MYAfterDelay( NSTimeInterval delay, void (^block)() );

/** Block-based equivalent to -performSelector:withObject:afterDelay:inModes:. */
id MYAfterDelayInModes( NSTimeInterval delay, NSArray* modes, void (^block)() );

/** Cancels a prior call to MYAfterDelayInModes, before the delayed block runs.
    @param block  The return value of the MYAfterDelayInModes call that you want to cancel. */
void MYCancelAfterDelay( id block );

/** Runs the block on the given thread's runloop. */
void MYOnThread( NSThread* thread, void (^block)());
void MYOnThreadSynchronously( NSThread* thread, void (^block)());

void MYOnThreadInModes(NSThread* thread,
                       NSArray* modes,
                       BOOL waitUntilDone,
                       void (^block)());

/** Spins the runloop in the given mode until the block returns YES. */
BOOL MYWaitFor( NSString* mode, MYNoEscape BOOL (^block)() );

/** Returns a block that when called invokes `block` unless the time since the last call to
    `block` was less than `minInterval` seconds ago. */
dispatch_block_t MYThrottledBlock(NSTimeInterval minInterval, void (^block)());

/** Returns a block that when called invokes `block` on `queue`, but not more often than
    `minInterval`.
    There will be a delay of up to `minInterval` seconds before the call to `block`,
    but every call to the returned block will result in a future call of `block`. */
dispatch_block_t MYBatchedBlock(NSTimeInterval minInterval,
                                dispatch_queue_t queue,
                                void (^block)());
