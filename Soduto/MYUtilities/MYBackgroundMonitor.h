//
//  MYBackgroundMonitor.h
//  MYUtilities
//
//  Created by Jens Alfke on 9/24/15.
//  Copyright © 2015 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Monitors when a UIKit app enters/leaves the background, and allows the client to start a
    "background task" to request more time to finish an activity. */
@interface MYBackgroundMonitor : NSObject

- (instancetype) init;

/** Explicitly stops the monitor. (So does deallocing it.) */
- (void) stop;

/** Starts a background task. Should be called from the onAppBackgrounding block.
    Only one background task can be active at a time. */
- (BOOL) beginBackgroundTaskNamed: (NSString*)name;

/** Tells the OS that the current background task is done.
    @return  YES if there was a background task, NO if none was running. */
- (BOOL) endBackgroundTask;

/** YES if there is currently a background task. */
@property (readonly) BOOL hasBackgroundTask;

/** This block will be called when the app goes into the background.
    The app will soon stop being scheduled for CPU time unless the block starts a background task
    by calling -beginBackgroundTaskNamed:. */
@property (strong) void (^onAppBackgrounding)();

/** Called when the app returns to the foreground. */
@property (strong) void (^onAppForegrounding)();

/** Called if the OS loses its patience before -endBackgroundTask is called.
    The task is implicitly ended, and the app will soon stop being scheduled for CPU time. */
@property (strong) void (^onBackgroundTaskExpired)();

@end
