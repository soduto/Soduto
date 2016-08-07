//
//  CollectionUtils+Old.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/7/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

// This source file must be compiled without ARC. (-fno-objc-arc)

#import "CollectionUtils+Old.h"
#import "Test.h"


NSString* $string( const char *utf8Str )
{
    if( utf8Str )
        return [NSString stringWithCString: utf8Str encoding: NSUTF8StringEncoding];
    else
        return nil;
}


NSArray* $apply( NSArray *src, SEL selector, id defaultValue )
{
    NSMutableArray *dst = [NSMutableArray arrayWithCapacity: src.count];
    for( id obj in src ) {
        id result = [obj performSelector: selector] ?: defaultValue;
        [dst addObject: result];
    }
    return dst;
}

NSArray* $applyKeyPath( NSArray *src, NSString *keyPath, id defaultValue )
{
    NSMutableArray *dst = [NSMutableArray arrayWithCapacity: src.count];
    for( id obj in src ) {
        id result = [obj valueForKeyPath: keyPath] ?: defaultValue;
        [dst addObject: result];
    }
    return dst;
}


void setObj( id *var, id value )
{
    if( value != *var ) {
        [*var release];
        *var = [value retain];
    }
}

BOOL ifSetObj( id *var, id value )
{
    if( value != *var && ![value isEqual: *var] ) {
        [*var release];
        *var = [value retain];
        return YES;
    } else {
        return NO;
    }
}

void setObjCopy( id *var, id valueToCopy ) {
    if( valueToCopy != *var ) {
        [*var release];
        *var = [valueToCopy copy];
    }
}

BOOL ifSetObjCopy( id *var, id value )
{
    if( value != *var && ![value isEqual: *var] ) {
        [*var release];
        *var = [value copy];
        return YES;
    } else {
        return NO;
    }
}


BOOL kvSetObj( id owner, NSString *property, id *varPtr, id value )
{
    if( *varPtr != value && ![*varPtr isEqual: value] ) {
        [owner willChangeValueForKey: property];
        [*varPtr autorelease];
        *varPtr = [value retain];
        [owner didChangeValueForKey: property];
        return YES;
    } else {
        return NO;
    }
}


BOOL kvSetObjCopy( id owner, NSString *property, id *varPtr, id value )
{
    if( *varPtr != value && ![*varPtr isEqual: value] ) {
        [owner willChangeValueForKey: property];
        [*varPtr autorelease];
        *varPtr = [value copy];
        [owner didChangeValueForKey: property];
        return YES;
    } else {
        return NO;
    }
}


BOOL kvSetSet( id owner, NSString *property, NSMutableSet *set, NSSet *newSet ) {
    CAssert(set);
    if (!newSet)
        newSet = [NSSet set];
    if (![set isEqualToSet: newSet]) {
        [owner willChangeValueForKey: property
                     withSetMutation:NSKeyValueSetSetMutation 
                        usingObjects:newSet]; 
        [set setSet: newSet];
        [owner didChangeValueForKey: property 
                    withSetMutation:NSKeyValueSetSetMutation 
                       usingObjects:newSet]; 
        return YES;
    } else
        return NO;
}


BOOL kvAddToSet( id owner, NSString *property, NSMutableSet *set, id objToAdd ) {
    CAssert(set);
    if (![set containsObject: objToAdd]) {
        NSSet *changedObjects = [[NSSet alloc] initWithObjects: &objToAdd count: 1];
        [owner willChangeValueForKey: property
                     withSetMutation: NSKeyValueUnionSetMutation 
                        usingObjects: changedObjects]; 
        [set addObject: objToAdd];
        [owner didChangeValueForKey: property 
                    withSetMutation: NSKeyValueUnionSetMutation 
                       usingObjects: changedObjects]; 
        [changedObjects release];
        return YES;
    } else
        return NO;
}


BOOL kvRemoveFromSet( id owner, NSString *property, NSMutableSet *set, id objToRemove ) {
    if ([set containsObject: objToRemove]) {
        NSSet *changedObjects = [[NSSet alloc] initWithObjects: &objToRemove count: 1];
        [owner willChangeValueForKey: property
                     withSetMutation: NSKeyValueMinusSetMutation 
                        usingObjects: changedObjects]; 
        [set removeObject: objToRemove];
        [owner didChangeValueForKey: property 
                    withSetMutation: NSKeyValueMinusSetMutation 
                       usingObjects: changedObjects]; 
        [changedObjects release];
        return YES;
    } else
        return NO;
}


@implementation NSArray (MYUtils_Deprecated)

- (NSArray*) my_arrayByApplyingSelector: (SEL)selector
{
    return [self my_arrayByApplyingSelector: selector withObject: nil];
}

- (NSArray*) my_arrayByApplyingSelector: (SEL)selector withObject: (id)object
{
    NSUInteger count = [self count];
    NSMutableArray *temp = [[NSMutableArray alloc] initWithCapacity: count];
    NSArray *result;
    NSUInteger i;
    for( i=0; i<count; i++ )
        [temp addObject: [[self objectAtIndex: i] performSelector: selector withObject: object]];
    result = [NSArray arrayWithArray: temp];
    [temp release];
    return result;
}

@end


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
