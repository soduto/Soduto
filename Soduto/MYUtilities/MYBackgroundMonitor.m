//
//  MYBackgroundMonitor.m
//  MYUtilities
//
//  Created by Jens Alfke on 9/24/15.
//  Copyright © 2015 Jens Alfke. All rights reserved.
//

#import "MYBackgroundMonitor.h"
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>


@implementation MYBackgroundMonitor
{
    NSString* _name;
    UIBackgroundTaskIdentifier _bgTask;
}


@synthesize onAppBackgrounding=_onAppBackgrounding, onAppForegrounding=_onAppForegrounding;
@synthesize onBackgroundTaskExpired=_onBackgroundTaskExpired;


- (instancetype) init {
    self = [super init];
    if (self) {
        _bgTask = UIBackgroundTaskInvalid;
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(appBackgrounding:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(appForegrounding:)
                                                 name: UIApplicationWillEnterForegroundNotification
                                               object: nil];
    }
    return self;
}


- (BOOL) endBackgroundTask {
    @synchronized(self) {
        if (_bgTask == UIBackgroundTaskInvalid)
            return NO;
        [[UIApplication sharedApplication] endBackgroundTask: _bgTask];
        _bgTask = UIBackgroundTaskInvalid;
        return YES;
    }
}


- (void) stop {
    [self endBackgroundTask];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (void) dealloc {
    [self stop];
}


- (BOOL) beginBackgroundTaskNamed: (NSString*)name {
    @synchronized(self) {
        Assert(_bgTask == UIBackgroundTaskInvalid, @"Background task already running");
        _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName: name
                                                               expirationHandler: ^{
            // Process ran out of background time before endBackgroundTask was called.
            // NOTE: Called on the main thread
            if ([self endBackgroundTask])
                if (_onBackgroundTaskExpired)
                    _onBackgroundTaskExpired();
        }];
        return (_bgTask != UIBackgroundTaskInvalid);
    }
}


- (BOOL) hasBackgroundTask {
    @synchronized(self) {
        return _bgTask != UIBackgroundTaskInvalid;
    }
}


- (void) appBackgrounding: (NSNotification*)n {
    if (_onAppBackgrounding)
        _onAppBackgrounding();
}


- (void) appForegrounding: (NSNotification*)n {
    if (_onAppForegrounding)
        _onAppForegrounding();
}


@end
