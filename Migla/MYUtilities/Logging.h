//
//  Logging.h
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


/* NOTE: This is the old/legacy logging API. The new one is MYLogging.h. */


NSString* LOC( NSString *key );     // Localized string lookup


#ifndef MYLOGGING   // Don't interfere with MYLogging.h if it's already been included


#define Warn Warn


#ifndef MY_DISABLE_LOGGING


#define Log(FMT,ARGS...) do{if(__builtin_expect(_gShouldLog,0)) {\
                            _Log(FMT,##ARGS);\
                         } }while(0)
#define LogTo(DOMAIN,FMT,ARGS...) do{if(__builtin_expect(_gShouldLog,0)) {\
                                    if(_WillLogTo(@""#DOMAIN)) _LogTo(@""#DOMAIN,FMT,##ARGS);\
                                  } }while(0)


void AlwaysLog( NSString *msg, ... ) __attribute__((format(__NSString__, 1, 2)));
BOOL EnableLog( BOOL enable );
#define EnableLogTo( DOMAIN, VALUE )  _EnableLogTo(@""#DOMAIN, VALUE)
#define WillLog()  _WillLogTo(nil)
#define WillLogTo( DOMAIN )  _WillLogTo(@""#DOMAIN)

/** Setting this causes logging functions to call that block before outputting anything.
    If the block returns NO, regular log output is skipped. */
extern BOOL (^MYLoggingCallback)(NSString* domain, NSString* message);

/** Setting this to YES causes Warn() to raise an exception. Useful in unit tests. */
extern BOOL gMYWarnRaisesException;

// internals; don't use directly
extern int _gShouldLog;
void _Log( NSString *msg, ... ) __attribute__((format(__NSString__, 1, 2)));
void _LogTo( NSString *domain, NSString *msg, ... ) __attribute__((format(__NSString__, 2, 3)));
BOOL _WillLogTo( NSString *domain );
BOOL _EnableLogTo( NSString *domain, BOOL enable );


#else // MY_DISABLE_LOGGING

#define Log(FMT,ARGS...) do{ }while(0)
#define LogTo(DOMAIN,FMT,ARGS...) do{ }while(0)
#define AlwaysLog NSLog
#define EnableLogTo( DOMAIN, VALUE ) do{ }while(0)
#define WillLog() NO
#define WillLogTo( DOMAIN ) NO

#endif // MY_DISABLE_LOGGING

void Warn( NSString *msg, ... ) __attribute__((format(__NSString__, 1, 2)));

#endif // MYLOGGING
