//
//  MYURLHandler.m
//  MYUtilities
//
//  Created by Jens Alfke on 3/15/12.
//  Copyright (c) 2012 Jens Alfke. All rights reserved.
//

#import "MYURLHandler.h"
#import <AppKit/AppKit.h>


@implementation MYURLHandler


+ (void) installHandler {
    NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
    [appleEventManager setEventHandler: self 
                           andSelector: @selector(handleGetURLEvent:withReplyEvent:)
                         forEventClass: kInternetEventClass
                            andEventID: kAEGetURL];
}


+ (void) handleGetURLEvent: (NSAppleEventDescriptor *)event
            withReplyEvent: (NSAppleEventDescriptor *)reply
{
    OSStatus err = paramErr;
    NSString *errStr = @"Unknown URL";
    
    NSString *urlStr = [[event paramDescriptorForKeyword: keyDirectObject] stringValue];
    if( urlStr ) {
        NSURL *url = [NSURL URLWithString: urlStr];
        if( url.scheme.length > 0 ) {
            id<MYURLHandlerDelegate> delegate = [NSApp delegate];
            NSError* error = nil;
            if ([delegate openURL: url error: &error]) {
                err = noErr;
                errStr = nil;
            } else if (error) {
                err = (OSStatus)error.code;
                errStr = error.localizedDescription;
            }
        }
    }
    
    if( reply ) {
        [reply setParamDescriptor: [NSAppleEventDescriptor descriptorWithInt32: err]
                       forKeyword: keyErrorNumber];
        if( errStr )
            [reply setParamDescriptor: [NSAppleEventDescriptor descriptorWithString: errStr]
                           forKeyword: keyErrorString];
    }
}

@end
