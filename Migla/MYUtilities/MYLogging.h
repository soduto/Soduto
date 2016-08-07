//
//  MYLogging.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/23/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/*
    This is a configurable console-logging facility that lets logging be turned on and off independently for various subsystems or areas of the code. It's used similarly to NSLog:
        Log(@"the value of foo is %@", foo);

    You can associate a log message with a particular subsystem or tag by defining a logging domain. In one source file, define the domain:
        DefineLogDomain(Foo);
    If you need to use the same domain in other source files, add the line
        UsingLogDomain(Foo);
    Now you can use the Foo domain for logging:
        LogTo(Foo, @"the value of foo is %@", foo);
 
    By default, logging is compiled in but disabled at runtime.

    To enable logging in general, set the user default 'Log' to 'YES'. You can do this persistently using the 'defaults write' command; but it's very convenient during development to use the Arguments tab in the Xcode Executable Info panel. Just add a new entry to the arguments list, of the form "-Log YES". Now you can check and uncheck that as desired; the change will take effect when relaunching.

    Once logging is enabled, you can turn on individual domains. For any domain "Foo", to enable output from calls of the form LogTo(Foo, @"..."), set the user default 'LogFoo' to 'YES', just as above.
 
    You can use LogVerbose() and LogDebug() for messages that add more detail but shouldn't be seen by default when the domain is enabled. To enable verbose mode for a domain, e.g. 'Foo', set the default 'LogFooVerbose' to YES. To enable both verbose and debug modes, set 'LogFooDebug' to YES.

    Warn() is a related function that _always_ logs, and prefixes the message with "WARNING:".
        Warn(@"Reactor coolant system has failed");
 
    Note: Logging is still present in release/nondebug builds. I've found this to be very useful in tracking down problems in the field, since I can tell a user how to turn on logging, and then get detailed logs back. To disable logging code from being compiled at all, define the preprocessor symbol MY_DISABLE_LOGGING (in your prefix header or target build settings.)
*/ 



#define MYLOGGING


typedef NS_ENUM(uint8_t, MYLogLevel) {
    MYLogLevelOff,
    MYLogLevelOn,
    MYLogLevelVerbose,
    MYLogLevelDebug
};


typedef struct MYLogDomain {
    MYLogLevel level;
    const char* const name;
    struct MYLogDomain* next;
} MYLogDomain;


#define UsingLogDomain(DOMAIN) \
    extern MYLogDomain DOMAIN##_LogDomain

#ifndef MY_DISABLE_LOGGING

    #define DefineLogDomain(DOMAIN) \
        MYLogDomain DOMAIN##_LogDomain = {255, #DOMAIN}; \
        __attribute__((constructor)) static void register_##DOMAIN##_LogDomain() \
            { DOMAIN##_LogDomain.next = gMYLogDomainList; gMYLogDomainList = &DOMAIN##_LogDomain; }


    BOOL EnableLog(BOOL enable);
    MYLogLevel EnableLogTo(NSString *domain, MYLogLevel level);
    BOOL _WillLogTo(NSString *domain, MYLogLevel atLevel);
    NSArray* AllLogDomains(void);

    void AlwaysLog(NSString *msg, ...) __attribute__((format(__NSString__, 1, 2)));

    #define WillLogTo( DOMAIN )             (DOMAIN##_LogDomain.level >= MYLogLevelOn)
    #define WillLogVerbose( DOMAIN )        (DOMAIN##_LogDomain.level >= MYLogLevelVerbose)
    #define WillLog()                       WillLogTo(MYDefault)

    #if DEBUG
    #define WillLogDebug( DOMAIN )          (DOMAIN##_LogDomain.level >= MYLogLevelDebug)
    #else
    #define WillLogDebug( DOMAIN )          NO
    #endif

#else
    // When logging is disabled:
    #define DefineLogDomain(DOMAIN) \
        MYLogDomain DOMAIN##_LogDomain = {0, #DOMAIN};

    #define EnableLog(ENABLE) do{ }while(0)
    #define EnableLogTo( DOMAIN, VALUE ) do{ }while(0)

    #define AlwaysLog NSLog

    #define WillLog() 0
    #define WillLogTo( DOMAIN ) 0
    #define _WillLogTo( DOMAIN, LEVEL ) 0
    #define WillLogVerbose( DOMAIN ) 0
    #define WillLogDebug( DOMAIN ) 0
#endif // MY_DISABLE_LOGGING


#define LogTo(DOMAIN, FMT, ARGS...) \
    ({if (__builtin_expect(WillLogTo(DOMAIN), NO)) \
        MYLogTo(&DOMAIN##_LogDomain, FMT, ##ARGS);})

#define MYLogVerbose(DOMAIN, FMT, ARGS...) \
    ({if (__builtin_expect(WillLogVerbose(DOMAIN), NO)) \
        MYLogTo(&DOMAIN##_LogDomain, FMT, ##ARGS);})

#if DEBUG
#define MYLogDebug(DOMAIN, FMT, ARGS...) \
    ({if (__builtin_expect(WillLogDebug(DOMAIN), NO)) \
        MYLogTo(&DOMAIN##_LogDomain, FMT, ##ARGS);})
#else
#define MYLogDebug(DOMAIN, FMT, ARGS...) \
    ({ })
#endif

#define LogVerbose MYLogVerbose
#define LogDebug MYLogDebug


UsingLogDomain(MYDefault);

#define Log(FMT, ARGS...)  LogTo(MYDefault, FMT, ##ARGS)


/** Setting this causes logging functions to call that block before outputting anything.
    If the block returns NO, regular log output is skipped. */
extern BOOL (^MYLoggingCallback)(NSString* domain, NSString* message);

void MYWarn( const char *file, int line, NSString *msg, ... )
        __attribute__((format(__NSString__, 3, 4)));

#define Warn(FMT, ARGS...) MYWarn(__func__, __LINE__, FMT, ##ARGS)

/** Setting this to YES causes Warn() to raise an exception. Useful in unit tests. */
extern BOOL gMYWarnRaisesException;


// internals; don't use directly
extern MYLogDomain* gMYLogDomainList;
void MYLogTo(const MYLogDomain*, NSString* fmt, ...) __attribute__((format(__NSString__, 2, 3)));
