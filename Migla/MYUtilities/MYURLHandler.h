//
//  MYURLHandler.h
//  MYUtilities
//
//  Created by Jens Alfke on 3/15/12.
//  Copyright (c) 2012 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Utility for installing an AppleEvent handler that handles open-URL events. */
@interface MYURLHandler : NSObject

/** Installs a handler for open-URL ('GURL') AppleEvents.
    The handler calls the application delegate's -openURL:error: method. */
+ (void) installHandler;

@end


@protocol MYURLHandlerDelegate <NSObject>

/** The NSApplication's delegate must implement this method.
    @param url  The URL that's been sent to the app to handle.
    @param outError  On failure, this should be set to an NSError describing the problem.
    @return  YES if the URL was handled, NO if it wasn't. */
- (BOOL) openURL: (NSURL*)url error: (NSError**)outError;

@end