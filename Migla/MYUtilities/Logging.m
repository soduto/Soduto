//
//  Logging.m
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

#import "Logging.h"
#import "CollectionUtils.h"

#include <unistd.h>
#include <fcntl.h>
#include <sys/param.h>
#include <termios.h>


BOOL gMYWarnRaisesException;


NSString* LOC( NSString *key )     // Localized string lookup
{
    NSString *value = [[NSBundle mainBundle] localizedStringForKey:key value:nil table:nil];
    if( value == key ) {
        Warn(@"No localized string for '%@' in Localizable.strings!",key);
        value = [key uppercaseString];
    }
    return value;
}


#ifndef MY_DISABLE_LOGGING


typedef enum {
    kLoggingToOther,
    kLoggingToFile,
    kLoggingToTTY,
    kLoggingToColorTTY,     // Terminal that supports ANSI color escape codes
    kLoggingToColorXcode    // Xcode with XcodeColors plugin installed
} MYLoggingTo;


int _gShouldLog = -1;
BOOL (^MYLoggingCallback)(NSString* domain, NSString* message) = nil;

static MYLoggingTo sLoggingTo;
static NSMutableSet *sEnabledDomains;


/** Does the file descriptor connect to console output, i.e. a terminal or Xcode? */
static MYLoggingTo getLoggingMode( int fd )
{
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
    return kLoggingToOther;
#else
    if( isatty(fd) ) {
        const char *xcode_colors = getenv("XcodeColors");
        if (xcode_colors && (strcmp(xcode_colors, "YES") == 0))
            return kLoggingToColorXcode;

        const char *term = getenv("TERM");
        if( term && (strstr(term,"ANSI") || strstr(term,"ansi") || strstr(term,"color")) )
            return kLoggingToColorTTY;
        else
            return kLoggingToTTY;
    } else {
#if GNUSTEP
        return kLoggingToFile;
#else
        char path[MAXPATHLEN];
        if( fcntl(fd, F_GETPATH, path) == 0 )
            return kLoggingToFile;
        else
            return kLoggingToOther;
#endif
    }
#endif
}


static void InitLogging()
{
    if( _gShouldLog != -1 )
        return;

    @autoreleasepool {
        _gShouldLog = NO;
        sEnabledDomains = [[NSMutableSet alloc] init];
        NSDictionary *dflts = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        for( NSString *key in dflts ) {
            if( [key hasPrefix: @"Log"] ) {
                BOOL value = [[NSUserDefaults standardUserDefaults] boolForKey: key];
                if( key.length==3 )
                    _gShouldLog = value;
                else if( value ) {
                    NSString* trimmedKey = [key substringFromIndex: 3]; // trim 'Log'
                    [sEnabledDomains addObject: trimmedKey];
                    if (trimmedKey.length > 7 && [trimmedKey hasSuffix: @"Verbose"]) {
                        trimmedKey = [trimmedKey substringToIndex: trimmedKey.length - 7]; // trim 'Verbose'
                        [sEnabledDomains addObject: trimmedKey];
                    }
                }
            }
        }
        sLoggingTo = getLoggingMode(STDERR_FILENO);

        static const char* kModeNames[] = {"NSLog", "file", "TTY", "color TTY", "color Xcode"};
        
        Log(@"Logging %@ to %s",
            [[[sEnabledDomains allObjects] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)]
                    componentsJoinedByString: @", "],
            kModeNames[sLoggingTo]);
    }
}


BOOL EnableLog( BOOL enable )
{
    if( _gShouldLog == -1 )
        InitLogging();
    BOOL old = _gShouldLog != 0;
    _gShouldLog = enable;
    return old;
}

BOOL _WillLogTo( NSString *domain )
{
    if( _gShouldLog == -1 )
        InitLogging();
    return _gShouldLog && (domain==nil || [sEnabledDomains containsObject: domain]);
}

BOOL _EnableLogTo( NSString *domain, BOOL enable )
{
    if( _gShouldLog == -1 )
        InitLogging();
    BOOL old = [sEnabledDomains containsObject: domain];
    if( enable )
        [sEnabledDomains addObject: domain];
    else
        [sEnabledDomains removeObject: domain];
    return old;
}


#define kWarningPrefix @"WARNING"

// See http://en.wikipedia.org/wiki/ANSI_escape_code#Colors
// See https://github.com/robbiehanson/XcodeColors
#define ANSI_COLOR_ESC(STR)     @"\033[" STR "m"
#define XCODE_COLOR_ESC(STR)    @"\033[" STR ";"

#define COLOR_RESET     color(ANSI_COLOR_ESC("0"),  XCODE_COLOR_ESC(""))
#define COLOR_WARNING   color(ANSI_COLOR_ESC("91"), XCODE_COLOR_ESC("fg194,54,33"))
#define COLOR_PREFIX    color(ANSI_COLOR_ESC("93"), XCODE_COLOR_ESC("fg0,128,0"))
#define COLOR_TIME      color(ANSI_COLOR_ESC("36"), XCODE_COLOR_ESC("fg160,160,160"))

static NSString* color(NSString* ansi, NSString* xcode) {
    switch (sLoggingTo) {
        case kLoggingToColorTTY:    return ansi;
        case kLoggingToColorXcode:  return xcode;
        default:                    return @"";
    }
}


static void _Logv( NSString *prefix, NSString *msg, va_list args )
{
    if (MYLoggingCallback) {
        msg = [[NSString alloc] initWithFormat: msg arguments: args];
        if (!MYLoggingCallback(prefix, msg))
            return;
    }
    if (sLoggingTo > kLoggingToOther) {
        @autoreleasepool {
            static NSDateFormatter *sTimestampFormat;
            if( ! sTimestampFormat ) {
                sTimestampFormat = [[NSDateFormatter alloc] init];
                sTimestampFormat.dateFormat = @"HH:mm:ss.SSS";
            }
            NSDate *now = [[NSDate alloc] init];
            NSString *timestamp = [sTimestampFormat stringFromDate: now];

            NSString* timestampTrailer = @"|";
            if (![[NSThread currentThread] isMainThread])
                timestampTrailer = @"‖";

            NSString *separator = prefix.length ?@": " :@"";
            msg = [[NSString alloc] initWithFormat: msg arguments: args];
            BOOL isWarning = [prefix isEqualToString: kWarningPrefix];
            NSString *prefixColor = isWarning ?COLOR_WARNING :COLOR_PREFIX;
            NSString *msgColor = isWarning ?@"" :COLOR_RESET;
            NSString *finalMsg = [[NSString alloc] initWithFormat: @"%@%@%@ %@%@%@%@%@\n", 
                                  COLOR_TIME,timestamp, timestampTrailer,
                                  prefixColor,prefix,separator,
                                  msgColor,msg];
            fputs([finalMsg UTF8String], stderr);
        }
    } else {
        if( prefix.length )
            msg = $sprintf(@"%@: %@", prefix,msg);
        NSLogv(msg,args);
    }
}


void AlwaysLog( NSString *msg, ... )
{
    va_list args;
    va_start(args,msg);
    _Logv(@"",msg,args);
    va_end(args);
}


void _Log( NSString *msg, ... )
{
    if( _gShouldLog == -1 )
        InitLogging();
    if( _gShouldLog ) {
        va_list args;
        va_start(args,msg);
        _Logv(@"",msg,args);
        va_end(args);
    }
}


void _LogTo( NSString *domain, NSString *msg, ... )
{
    if( _gShouldLog == -1 )
        InitLogging();
    if( _gShouldLog && [sEnabledDomains containsObject: domain] ) {
        va_list args;
        va_start(args,msg);
        _Logv(domain, msg, args);
        va_end(args);
    }
}


#endif // MY_DISABLE_LOGGING


void Warn( NSString *msg, ... )
{
    va_list args;
    va_start(args,msg);
#ifdef MY_DISABLE_LOGGING
    NSLogv([@"WARNING: " stringByAppendingString: msg], args);
#else
    _Logv(kWarningPrefix,msg,args);
#endif
    va_end(args);

    if (gMYWarnRaisesException) {
        va_list args;
        va_start(args,msg);
        [NSException raise: NSInternalInconsistencyException
                    format: [@"Warn() was called: " stringByAppendingString: msg]
                 arguments: args];
        va_end(args);
    }
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
