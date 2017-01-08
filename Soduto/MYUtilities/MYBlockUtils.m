//
//  MYBlockUtils.m
//  MYUtilities
//
//  Created by Jens Alfke on 1/28/12.
//  Copyright (c) 2012 Jens Alfke. All rights reserved.
//

#import "MYBlockUtils.h"
#import "Test.h"
#import "MYLogging.h"
#import <libkern/OSAtomic.h>


#if !__has_feature(objc_arc)
#error This source file must be compiled with ARC
#endif


@interface NSObject (MYBlockUtils)
- (void) my_run_as_block;
@end


/* This is sort of a kludge. This method only needs to be defined for blocks, but their class (NSBlock) isn't public, and the only public base class is NSObject. */
@implementation NSObject (MYBlockUtils)

- (void) my_run_as_block {
    ((void (^)())self)();
}

@end


void MYAfterDelay( NSTimeInterval delay, void (^block)() ) {
    block = [block copy];
    [block performSelector: @selector(my_run_as_block)
                withObject: nil
                afterDelay: delay];
}

id MYAfterDelayInModes( NSTimeInterval delay, NSArray* modes, void (^block)() ) {
    block = [block copy];
    [block performSelector: @selector(my_run_as_block)
                withObject: nil
                afterDelay: delay
                   inModes: modes];
    return block;
}

void MYCancelAfterDelay( id block ) {
    [NSObject cancelPreviousPerformRequestsWithTarget: block
                                             selector: @selector(my_run_as_block)
                                               object:nil];
}


static void MYOnThreadWaiting( NSThread* thread, BOOL waitUntilDone, void (^block)()) {
    block = [block copy];
    [block performSelector: @selector(my_run_as_block)
                  onThread: thread
                withObject: block
             waitUntilDone: waitUntilDone];
}


void MYOnThread( NSThread* thread, void (^block)()) {
    MYOnThreadWaiting(thread, NO, block);
}

void MYOnThreadSynchronously( NSThread* thread, void (^block)()) {
    MYOnThreadWaiting(thread, YES, block);
}


void MYOnThreadInModes( NSThread* thread, NSArray* modes, BOOL waitUntilDone, void (^block)()) {
    block = [block copy];
    [block performSelector: @selector(my_run_as_block)
                  onThread: thread
                withObject: block
             waitUntilDone: waitUntilDone
                     modes: modes];
}


BOOL MYWaitFor( NSString* mode, BOOL (^block)() ) {
    if (block())
        return YES;

    // Add a temporary input source for the private runloop mode, because -runMode:beforeDate: will
    // fail if there are no sources:
    NSPort* port = [NSPort port];
    [[NSRunLoop currentRunLoop] addPort: port forMode: mode];
    BOOL success = YES;
    do {
        if (![[NSRunLoop currentRunLoop] runMode: mode
                                      beforeDate: [NSDate distantFuture]]) {
            Warn(@"CBLDatabase waitFor: Runloop stopped");
            success = NO;
            break;
        }
    } while (!block());
    [[NSRunLoop currentRunLoop] removePort: port forMode: mode];
    return success;
}


dispatch_block_t MYThrottledBlock(NSTimeInterval minInterval, dispatch_block_t block) {
    __block CFAbsoluteTime lastTime = 0;
    block = [block copy];
    dispatch_block_t throttled = ^{
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastTime >= minInterval)
            block();
        lastTime = now;
    };
    return [throttled copy];
}


dispatch_block_t MYBatchedBlock(NSTimeInterval minInterval,
                                dispatch_queue_t queue,
                                void (^block)())
{
    __block uint8_t scheduled = 0;
    block = [block copy];
    dispatch_block_t batched = ^{
        uint8_t wasScheduled = OSAtomicTestAndSetBarrier(0, &scheduled);
        if (!wasScheduled) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(minInterval * NSEC_PER_SEC)),
                           queue, ^{
                OSAtomicTestAndClearBarrier(0, &scheduled);
                block();
            });
        }
    };
    return [batched copy];
}

TestCase(MYAfterDelay) {
    __block BOOL fired = NO;
    MYAfterDelayInModes(0.5, $array(NSRunLoopCommonModes), ^{fired = YES; NSLog(@"Fired!");});
    CAssert(!fired);
    
    while (!fired) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    CAssert(fired);
}



/*
 Copyright (c) 2008-2013, Jens Alfke <jens@mooseyard.com>. All rights reserved.

 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
