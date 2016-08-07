//
//  MYLogging.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/23/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "MYLogging.h"
#import "CollectionUtils.h"

#include <unistd.h>
#include <fcntl.h>
#include <sys/param.h>
#include <termios.h>


#if !__has_feature(objc_arc)
#error This source file must be compiled with ARC
#endif


BOOL gMYWarnRaisesException;


DefineLogDomain(MYDefault);

MYLogDomain* gMYLogDomainList;


typedef enum {
    kLoggingToOther,
    kLoggingToFile,
    kLoggingToTTY,
    kLoggingToColorTTY,     // Terminal that supports ANSI color escape codes
    kLoggingToColorXcode    // Xcode with XcodeColors plugin installed
} MYLoggingTo;


BOOL (^MYLoggingCallback)(NSString* domain, NSString* message) = nil;


static MYLogLevel enableLogTo(NSString *domain, MYLogLevel level);
static MYLoggingTo loggingMode();


static void InitLogging() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            for (MYLogDomain* domain = gMYLogDomainList; domain; domain = domain->next)
                domain->level = 0;

            if ([[NSUserDefaults standardUserDefaults] boolForKey: @"Log"]) {
                MYDefault_LogDomain.level = 1;
                NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
                for(NSString *key in [defaults dictionaryRepresentation]) {
                    if ([key hasPrefix: @"Log"] && key.length > 3 && [defaults boolForKey: key])
                        enableLogTo([key substringFromIndex: 3], MYLogLevelOn);
                }

                static const char* kModeNames[] = {"NSLog", "file", "TTY", "color TTY", "color Xcode"};

                // Log a list of the enabled domains and their verbosity:
                NSMutableArray* names = $marray();
                for (MYLogDomain* domain = gMYLogDomainList; domain; domain = domain->next) {
                    if (domain->level > MYLogLevelOff && domain != &MYDefault_LogDomain) {
                        NSString* name = @(domain->name);
                        if (domain->level >= MYLogLevelDebug)
                            name = [name stringByAppendingString: @"(Debug)"];
                        else if (domain->level >= MYLogLevelVerbose)
                            name = [name stringByAppendingString: @"(Verbose)"];
                        [names addObject: name];
                    }
                }
                [names sortUsingSelector: @selector(caseInsensitiveCompare:)];
                AlwaysLog(@"Logging %@ to %s", [names componentsJoinedByString: @", "], kModeNames[loggingMode()]);
            }
        }
    });
}


static MYLogDomain* findDomain(NSString* name) {
    const char* cname = name ? name.UTF8String : "MYDefault";
    for (MYLogDomain* domain = gMYLogDomainList; domain; domain = domain->next) {
        if (strcmp(domain->name, cname) == 0)
            return domain;
    }
    return NULL;
}


#ifndef MY_DISABLE_LOGGING
BOOL EnableLog(BOOL enable) {
    InitLogging();
    BOOL old = MYDefault_LogDomain.level > 0;
    MYDefault_LogDomain.level = enable ? MYLogLevelOn : MYLogLevelOff;
    return old;
}

BOOL _WillLogTo(NSString *domain, MYLogLevel atLevel) {
    InitLogging();
    MYLogDomain* d = findDomain(domain);
    return d && d->level >= atLevel;
}
#endif

static MYLogLevel enableLogTo(NSString *domain, MYLogLevel level) {
    MYLogLevel domainLevel = MYLogLevelOn;
    if ([domain hasSuffix: @"Debug"]) {
        domain = [domain substringToIndex: domain.length - 5];
        domainLevel = MYLogLevelDebug;
#if !DEBUG
        Warn(@"Debug-level logging has no effect in release builds");
#endif
    }
    while ([domain hasSuffix: @"Verbose"]) {
        domain = [domain substringToIndex: domain.length - 7];
        domainLevel++;
    }

    if (level == MYLogLevelOn && domainLevel > level)
        level = domainLevel;

    MYLogDomain* d = findDomain(domain);
    if (!d) {
        Warn(@"EnableLogTo: There is no logging domain named '%@'. Available domains are: %@",
             domain, [AllLogDomains() componentsJoinedByString: @", "]);
        return MYLogLevelOff;
    }
    MYLogLevel old = d->level;
    d->level = level;
    return old;
}

#ifndef MY_DISABLE_LOGGING
MYLogLevel EnableLogTo(NSString *domain, MYLogLevel level) {
    InitLogging();
    return enableLogTo(domain, level);
}
#endif


NSArray* AllLogDomains() {
    NSMutableArray* names = $marray();
    for (MYLogDomain* domain = gMYLogDomainList; domain; domain = domain->next) {
        if (domain != &MYDefault_LogDomain)
            [names addObject: @(domain->name)];
    }
    [names sortUsingSelector: @selector(caseInsensitiveCompare:)];
    return names;
}


#pragma mark - LOG OUTPUT:


/** Does the file descriptor connect to console output, i.e. a terminal or Xcode? */
static MYLoggingTo getLoggingMode(int fd ) {
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
    return kLoggingToOther;
#else
    if (isatty(fd)) {
        const char *xcode_colors = getenv("XcodeColors");
        if (xcode_colors && (strcmp(xcode_colors, "YES") == 0))
            return kLoggingToColorXcode;

        const char *term = getenv("TERM");
        if (term && (strstr(term,"ANSI") || strstr(term,"ansi") || strstr(term,"color")))
            return kLoggingToColorTTY;
        else
            return kLoggingToTTY;
    } else {
#if GNUSTEP
        return kLoggingToFile;
#else
        char path[MAXPATHLEN];
        if (fcntl(fd, F_GETPATH, path) == 0)
            return kLoggingToFile;
        else
            return kLoggingToOther;
#endif
    }
#endif
}

static MYLoggingTo loggingMode() {
    static MYLoggingTo sMode;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sMode = getLoggingMode(STDERR_FILENO);
    });
    return sMode;
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
    switch (loggingMode()) {
        case kLoggingToColorTTY:    return ansi;
        case kLoggingToColorXcode:  return xcode;
        default:                    return @"";
    }
}


static MYLogDomain sWarningDomain = {1, "WARNING", NULL};


static void _Logv(const MYLogDomain* domain, NSString *msg, va_list args) {
    @autoreleasepool {
        // Format the message:
        msg = [[NSString alloc] initWithFormat: msg arguments: args];
        BOOL hasDomain = domain && strcmp(domain->name, "MYDefault") != 0;

        if (MYLoggingCallback) {
            NSString* prefix = hasDomain ? @(domain->name) : nil;
            if (!MYLoggingCallback(prefix, msg))
                return;
        }

        if (loggingMode() > kLoggingToOther) {
            static NSDateFormatter *sTimestampFormat;
            if (! sTimestampFormat) {
                sTimestampFormat = [[NSDateFormatter alloc] init];
                sTimestampFormat.dateFormat = @"HH:mm:ss.SSS";
            }
            NSDate *now = [[NSDate alloc] init];
            NSString *timestamp = [sTimestampFormat stringFromDate: now];

            NSString* timestampTrailer = @"|";
            if (![[NSThread currentThread] isMainThread])
                timestampTrailer = @"‖";

            NSString *separator = hasDomain ?@": " :@"";
            BOOL isWarning = (domain == &sWarningDomain);
            NSString* prefix = hasDomain ? @(domain->name) : @"";
            NSString *prefixColor = isWarning ?COLOR_WARNING :COLOR_PREFIX;
            NSString *msgColor = isWarning ?@"" :COLOR_RESET;
            NSString *finalMsg = [[NSString alloc] initWithFormat: @"%@%@%@ %@%@%@%@%@\n", 
                                  COLOR_TIME,timestamp, timestampTrailer,
                                  prefixColor, prefix, separator,
                                  msgColor,msg];
            fputs([finalMsg UTF8String], stderr);
        } else {
            if (hasDomain)
                NSLog(@"%s: %@", domain->name, msg);
            else
                NSLog(@"%@", msg);
        }
    }
}

static void _Log(const MYLogDomain* domain, NSString *msg, ...) {
    va_list args;
    va_start(args,msg);
    _Logv(domain, msg, args);
    va_end(args);
}


void AlwaysLog(NSString *msg, ...) {
    va_list args;
    va_start(args,msg);
    _Logv(&MYDefault_LogDomain, msg, args);
    va_end(args);
}


void MYLogTo(const MYLogDomain* domain, NSString *msg, ...) {
    InitLogging();
    if (MYDefault_LogDomain.level > 0 && domain->level > 0) {
        va_list args;
        va_start(args,msg);
        _Logv(domain, msg, args);
        va_end(args);
    }
}


void MYWarn(const char *where, int line, NSString *msg, ...) {
    va_list args;
    va_start(args,msg);
    NSString* formatted = [[NSString alloc] initWithFormat: msg arguments: args];
    va_end(args);

#ifdef MY_DISABLE_LOGGING
    NSLog(@"WARNING: %@" formatted);
#else
    _Log(&sWarningDomain, @"%@ {at %s:%d}", formatted, where, line);
#endif

    if (gMYWarnRaisesException) {
        va_list args;
        va_start(args,msg);
        [NSException raise: NSInternalInconsistencyException
                    format: @"Warn() was called from %s:%d: %@", where, line, formatted];
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
