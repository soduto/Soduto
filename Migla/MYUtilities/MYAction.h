//
//  MYAction.h
//  MYUtilities
//
//  Created by Jens Alfke on 8/28/15.
//  Copyright © 2015 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


/** An abstraction whose instances can perform some action and back it out. */
@protocol MYAction <NSObject>

/** Performs the action. Behavior should be all-or-nothing: if the action doesn't succeed, it
    should restore any temporary state to what it was before, before returning an error. */
- (BOOL) perform: (NSError**)error;

/** Backs out the completed action. This will be called if a subsequent action has failed. */
- (BOOL) backOut: (NSError**)error;

/** Cleans up after all actions have completed. This may involve releasing/deleting any temporary
    resources being kept around to fulfil a backOut request.*/
- (BOOL) cleanUp: (NSError**)error;

@end



typedef BOOL (^MYActionBlock)(NSError**);



@interface MYAction : NSObject <MYAction>

- (instancetype) init;

- (instancetype) initWithPerform: (MYActionBlock)perform
                         backOut: (MYActionBlock)backOut
                         cleanUp: (MYActionBlock)cleanUp;

/** Adds a MYAction as a step of this one. */
- (void) addAction: (id<MYAction>)action;

/** Adds an action as a step of this one. The action has three components, each optional.
    @param perform  A block that tries to perform the action, or returns an error if it fails.
                    (If the block fails, it should clean up; the backOut will _not_ be called!)
    @param backOut  A block that undoes the effect of the action; it will be called if a _later_
                    action fails, so that the system can be returned to the initial state.
    @param cleanUp  A block that performs any necessary cleanup after all actions have been
                    performed (e.g. deleting a temporary file.) */
- (void) addPerform: (MYActionBlock)perform
            backOut: (MYActionBlock)backOut
            cleanUp: (MYActionBlock)cleanUp;

- (void) addPerform: (MYActionBlock)perform
   backOutOrCleanUp: (MYActionBlock)backOutOrCleanUp;

/** Performs all the actions in order.
    If any action fails, backs out the previously performed actions in reverse order.
    If the actions succeeded, cleans them up in reverse order.
    The `error` property is set to the error returned by the failed perform block.
    The `failedStep` property is set to the index of the failed perform block. */
- (BOOL) run: (NSError**)error;

/** The error returned by the last -run call. */
@property (readonly) NSError* error;

/** The index of the action whose perform block failed; NSNotFound if none. */
@property (readonly) NSUInteger failedStep;


// File-based actions:

/** Deletes the file/directory at the given path, if it exists. */
+ (instancetype) deleteFile: (NSString*)path;

/** Moves the file/directory to a new location, which must not already exist. */
+ (instancetype) moveFile: (NSString*)srcPath toEmptyPath: (NSString*)dstPath;

/** Moves the file/directory to a new location, replacing anything that already exists there. */
+ (instancetype) moveFile: (NSString*)srcPath toPath: (NSString*)dstPath;

/** Removes an existing temporary file.
    Performs no action, but on backOut or cleanUp deletes the file. */
+ (instancetype) cleanUpTemporaryFile: (NSString*)tempPath;

@end
