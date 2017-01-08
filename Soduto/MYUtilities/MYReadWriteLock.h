//
//  MYReadWriteLock.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/15/14.
//
//

#import <Foundation/Foundation.h>


/** A multi-reader/single-writer lock. Based on a pthread_rwlock. */
@interface MYReadWriteLock : NSObject <NSLocking>

@property (copy) NSString* name;

/** Acquires a read lock. Multiple threads may have read locks at the same time, and a single
    thread may acquire the read lock multiple times (but must unlock the same number of times to
    relinquish the lock.)
    Calling -lock when the current thread already has the write lock will raise an exception. */
- (void) lock;

/** Attempts to acquire the read lock without blocking; returns YES if it did. */
- (BOOL) tryLock;

/** Acquires a write lock. Only one caller may have the write lock at a time, and no one can have
    the write lock as long as anyone has the read lock.
    Unlike the read lock, the write lock is NOT recursive! An exception will be raised if the
    current thread already has either the read or write lock. */
- (void) lockForWriting;

/** Attempts to acquire the write lock without blocking; returns YES if it did. */
- (BOOL) tryLockForWriting;

/** If this thread has acquired the read lock, unlocks it (one instance of it); otherwise unlocks
    the write lock. */
- (void) unlock;

/** Convenience method that calls -lock, executes the block, then calls -unlock. */
- (void) withLock: (void(^)())block;

/** Convenience method that calls -lockForWriting, executes the block, then calls -unlock. */
- (void) withWriteLock: (void(^)())block;

@end
