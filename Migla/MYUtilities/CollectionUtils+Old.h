//
//  CollectionUtils+Old.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/7/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CollectionUtils.h"


NSString* $string( const char *utf8Str );


#if __has_feature(objc_arc)
#define setObj(VAR,VALUE) *(VAR) = (VALUE)
#define setObjCopy(VAR,VALUE) *(VAR) = [(VALUE) copy]
#define setString(VAR,VALUE) *(VAR) = [(VALUE) copy]
#define ifSetObj(VAR,VALUE) (((VALUE) != *(VAR) && ![(VALUE) isEqual: *(VAR)]) ? (*(VAR) = (VALUE), YES) : NO)
#else
void setObj( id *var, id value );
BOOL ifSetObj( id *var, id value );
void setObjCopy( id *var, id valueToCopy );
BOOL ifSetObjCopy( id *var, id value );
static inline void setString( NSString **var, NSString *value ) {setObjCopy(var,value);}
static inline BOOL ifSetString( NSString **var, NSString *value ) {return ifSetObjCopy(var,value);}
#endif


// Apply a selector to each array element, returning an array of the results:
// (See also -[NSArray my_map:], which is more general but requires block support)
NSArray* $apply( NSArray *src, SEL selector, id defaultValue );
NSArray* $applyKeyPath( NSArray *src, NSString *keyPath, id defaultValue );

BOOL kvSetObj( id owner, NSString *property, id *varPtr, id value );
BOOL kvSetObjCopy( id owner, NSString *property, id *varPtr, id value );
BOOL kvSetSet( id owner, NSString *property, NSMutableSet *set, NSSet *newSet );
BOOL kvAddToSet( id owner, NSString *property, NSMutableSet *set, id objToAdd );
BOOL kvRemoveFromSet( id owner, NSString *property, NSMutableSet *set, id objToRemove );


@interface NSArray (MYUtils_Deprecated)
- (NSArray*) my_arrayByApplyingSelector: (SEL)selector;
- (NSArray*) my_arrayByApplyingSelector: (SEL)selector withObject: (id)object;
@end
