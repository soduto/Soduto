//
//  MYAction.m
//  MYUtilities
//
//  Created by Jens Alfke on 8/28/15.
//  Copyright © 2015 Jens Alfke. All rights reserved.
//

#import "MYAction.h"
#import "MYErrorUtils.h"


@implementation MYAction
{
    NSMutableArray *_performs, *_backOuts, *_cleanUps;
    NSUInteger _nextStep;  // next step to perform
}

@synthesize error=_error, failedStep=_failedStep;


static MYActionBlock sNullAction;


+ (void) initialize {
    if (self == [MYAction class]) {
        sNullAction = ^BOOL(NSError** error) { return YES; };
    }
}


- (instancetype) init {
    self = [super init];
    if (self) {
        _performs = [NSMutableArray new];
        _backOuts = [NSMutableArray new];
        _cleanUps = [NSMutableArray new];
        _failedStep = NSNotFound;
    }
    return self;
}


- (instancetype) initWithPerform: (MYActionBlock)perform
                         backOut: (MYActionBlock)backOut
                         cleanUp: (MYActionBlock)cleanUp
{
    self = [self init];
    if (self) {
        [self addPerform: perform backOut: backOut cleanUp: cleanUp];
    }
    return self;
}


- (void) addPerform: (MYActionBlock)perform
            backOut: (MYActionBlock)backOut
            cleanUp: (MYActionBlock)cleanUp
{
    [_performs addObject: (perform ?: sNullAction)];
    [_backOuts addObject: (backOut ?: sNullAction)];
    [_cleanUps addObject: (cleanUp ?: sNullAction)];
}


- (void) addPerform: (MYActionBlock)perform
   backOutOrCleanUp: (MYActionBlock)backOutOrCleanUp
{
    [self addPerform: perform backOut: backOutOrCleanUp cleanUp: backOutOrCleanUp];
}


- (void) addAction: (id<MYAction>)action {
    Assert(action);
    if ([action isKindOfClass: [MYAction class]]) {
        MYAction* a = action;
        [_performs addObjectsFromArray: a->_performs];
        [_backOuts addObjectsFromArray: a->_backOuts];
        [_cleanUps addObjectsFromArray: a->_cleanUps];
    } else {
        [self addPerform: ^BOOL(NSError** error) { return [action perform: error]; }
                 backOut: ^BOOL(NSError** error) { return [action backOut: error]; }
                 cleanUp: ^BOOL(NSError** error) { return [action cleanUp: error]; }];
    }
}


- (BOOL) perform: (NSError**)outError {
    Assert(_nextStep == 0, @"Actions have already been run");
    NSError* error = nil;
    _failedStep = NSNotFound;
    for (; _nextStep < _performs.count; ++_nextStep) {
        error = [self doActionFromArray: _performs];
        if (error) {
            _failedStep = _nextStep;
            if (_nextStep > 0)
                [self backOut: NULL]; // back out the steps that already completed
            if (outError) *outError = error;
            return NO;
        }
    }
    return YES;
}


- (BOOL) backOut: (NSError**)outError {
    Assert(_nextStep > 0, @"Actions have not been run");
    NSError* backOutError = nil;
    while (_nextStep-- > 0) {
        backOutError = [self doActionFromArray: _backOuts];
        if (backOutError) {
            Warn(@"MYAction: Error backing out step #%d: %@", (int)_nextStep, backOutError);
            if (outError) *outError = backOutError;
            return NO;
        }
    }
    return YES;
}


- (BOOL) cleanUp: (NSError**)outError {
    Assert(_nextStep == _performs.count, @"Actions did not all run");
    NSError* cleanUpError = nil;
    while (_nextStep-- > 0) {
        cleanUpError = [self doActionFromArray: _cleanUps];
        if (cleanUpError) {
            Warn(@"MYAction: Error cleaning up step #%d: %@", (int)_nextStep, cleanUpError);
            if (outError) *outError = cleanUpError;
            return NO;
        }
    }
    return YES;
}


- (BOOL) run: (NSError**)outError {
    NSError* error;
    if ([self perform: &error]) {
        [self cleanUp: NULL];
        _error = nil;
        return YES;
    } else {
        // (perform: has already backed out whatever it did)
        _error = error;
        if (outError) *outError = error;
        return NO;
    }
}


// subroutine that calls an action block from either _performs, _backOuts or _cleanUps.
- (NSError*) doActionFromArray: (NSArray*)actionArray {
    NSError* error;
    @try {
        if (((MYActionBlock)actionArray[_nextStep])(&error))
            error = nil;
    } @catch (NSException *exception) {
        Warn(@"MYAction: Exception raised by step #%d: %@", (int)_nextStep, exception);
        error = [NSError errorWithDomain: @"MYAction" code: 1
                                 userInfo: @{@"NSException": exception}];
    }
    return error;
}


#pragma mark - FILE ACTIONS:


static BOOL isFileNotFoundError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == ENOENT)
        || ($equal(domain, NSCocoaErrorDomain) && (code == NSFileNoSuchFileError ||
                                                   code == NSFileReadNoSuchFileError));
}


+ (instancetype) deleteFile: (NSString*)path {
    Assert(path);
    NSString* tempPath = [NSTemporaryDirectory() stringByAppendingString: [NSUUID new].UUIDString];
    NSFileManager* fmgr = [NSFileManager defaultManager];
    __block BOOL exists;
    return [[self alloc] initWithPerform: ^BOOL(NSError** outError) {
        NSError* error;
        exists = [fmgr moveItemAtPath: path toPath: tempPath error: &error];
        if (exists || isFileNotFoundError(error))
            return YES;
        if (outError) *outError = error;
        return NO;
    } backOut: ^BOOL(NSError** outError) {
        return !exists || [fmgr moveItemAtPath: tempPath toPath: path error: outError];
    } cleanUp: ^BOOL(NSError** outError) {
        return !exists || [fmgr removeItemAtPath: tempPath error: outError];
    }];
}


+ (instancetype) moveFile: (NSString*)srcPath toEmptyPath: (NSString*)dstPath {
    Assert(srcPath && dstPath);
    NSFileManager* fmgr = [NSFileManager defaultManager];
    return [[self alloc] initWithPerform: ^BOOL(NSError** outError) {
        return [fmgr moveItemAtPath: srcPath toPath: dstPath error: outError];
    } backOut: ^BOOL(NSError** outError) {
        return [fmgr moveItemAtPath: dstPath toPath: srcPath error: outError];
    } cleanUp: nil];
}


+ (instancetype) moveFile: (NSString*)srcPath toPath: (NSString*)dstPath {
    MYAction* seq = [self new];
    [seq addAction: [self deleteFile: dstPath]];
    [seq addAction: [self moveFile: srcPath toEmptyPath: dstPath]];
    return seq;
}


+ (instancetype) cleanUpTemporaryFile: (NSString*)path {
    Assert(path);
    MYActionBlock deleteIt = ^BOOL(NSError** outError) {
        return [[NSFileManager defaultManager] removeItemAtPath: path error: outError];
    };
    return [[self alloc] initWithPerform: nil backOut: deleteIt cleanUp: deleteIt];
}


@end
