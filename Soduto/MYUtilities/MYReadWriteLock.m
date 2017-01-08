//
//  MYReadWriteLock.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/15/14.
//
//  Adapted from CHReadWriteLock, at http://cocoaheads.byu.edu/wiki/locks

#import "MYReadWriteLock.h"
#import <pthread.h>

@implementation MYReadWriteLock
{
    pthread_rwlock_t _lock;
}

@synthesize name=_name;

- (id) init {
	if (self = [super init]) {
		pthread_rwlock_init(&_lock, NULL);
	}
	return self;
}
 
- (void) dealloc {
	pthread_rwlock_destroy(&_lock);
}

- (NSString*) description {
    if (_name)
        return [NSString stringWithFormat: @"%@[%@]", self.class, _name];
    else
        return [NSString stringWithFormat: @"%@[%p]", self.class, self];
}

 
- (void) lock {
    int err = pthread_rwlock_rdlock(&_lock);
    if (err)
        [self _check: err];
}
 
- (void) unlock {
	int err = pthread_rwlock_unlock(&_lock);
    if (err)
        [self _check: err];
}
 
- (void) lockForWriting {
    int err = pthread_rwlock_wrlock(&_lock);
    if (err)
        [self _check: err];
}
 
- (BOOL) tryLock {
	int err = pthread_rwlock_tryrdlock(&_lock);
    if (err == EBUSY)
        return NO;
    else if (err)
        [self _check: err];
    return YES;
}
 
- (BOOL) tryLockForWriting {
	int err =  pthread_rwlock_trywrlock(&_lock);
    if (err == EBUSY)
        return NO;
    else if (err)
        [self _check: err];
    return YES;
}

- (void) withLock: (void(^)())block {
    [self lock];
    @try {
        block();
    } @finally {
        [self unlock];
    }
}

- (void) withWriteLock: (void(^)())block {
    [self lockForWriting];
    @try {
        block();
    } @finally {
        [self unlock];
    }
}

- (void) _check: (int)err {
    switch (err) {
        case 0:
            return;
        case EDEADLK:
            [NSException raise: NSInternalInconsistencyException
                        format: @"Deadlock! %@ already write-locked on this thread", self];
        default:
            [NSException raise: NSInternalInconsistencyException
                        format: @"Pthread error %d on %@", err, self];
    }
}

 
@end