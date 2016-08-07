//
//  CollectionUtils.h
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

//  NOTE: Old/deprecated stuff has been moved to CollectionUtils+Old

#import <Foundation/Foundation.h>
#define _MYUTILITIES_COLLECTIONUTILS_ 1

// Collection creation conveniences:

#define $array(OBJS...)     ({id objs[]={OBJS}; \
                              [NSArray arrayWithObjects: objs count: sizeof(objs)/sizeof(id)];})
#define $marray(OBJS...)    ({id objs[]={OBJS}; \
                              [NSMutableArray arrayWithObjects: objs count: sizeof(objs)/sizeof(id)];})

#define $dict(PAIRS...)     ({_dictpair pairs[]={PAIRS}; \
                              _dictof(pairs,sizeof(pairs)/sizeof(_dictpair));})
#define $mdict(PAIRS...)    ({_dictpair pairs[]={PAIRS}; \
                              _mdictof(pairs,sizeof(pairs)/sizeof(_dictpair));})

#define $object(VAL)        ({__typeof(VAL) v=(VAL); _box(&v,@encode(__typeof(v)));})


// Object conveniences:

BOOL $equal(id obj1, id obj2);      // Like -isEqual: but works even if either/both are nil

#define $sprintf(FORMAT, ARGS... )  [NSString stringWithFormat: (FORMAT), ARGS]

#define $cast(CLASSNAME,OBJ)        ((CLASSNAME*)(_cast([CLASSNAME class],(OBJ))))
#define $castNotNil(CLASSNAME,OBJ)  ((CLASSNAME*)(_castNotNil([CLASSNAME class],(OBJ))))
#define $castIf(CLASSNAME,OBJ)      ((CLASSNAME*)(_castIf([CLASSNAME class],(OBJ))))
#define $castArrayOf(ITEMCLASSNAME,OBJ) _castArrayOf([ITEMCLASSNAME class],(OBJ))
#define $castIfArrayOf(ITEMCLASSNAME,OBJ) _castIfArrayOf([ITEMCLASSNAME class],(OBJ))
#define $castIfProtocol(PROTONAME,OBJ) ((id<PROTONAME>)(_castIfProto(@protocol(PROTONAME),(OBJ))))


static inline CFTypeRef cfretain(CFTypeRef obj) {if (obj) CFRetain(obj); return obj;}
static inline void cfrelease(CFTypeRef obj) {if (obj) CFRelease(obj);}

void cfSetObj(void *var, CFTypeRef value);

#if __has_feature(objc_arc)
#  define MYRelease(OBJ) ((void)(OBJ))
#  define MYAutorelease(OBJ) (OBJ)
#  define MYRetain(OBJ) (OBJ)
#else
#  define MYRelease(OBJ) [(OBJ) release]
#  define MYAutorelease(OBJ) [(OBJ) autorelease]
#  define MYRetain(OBJ) [(OBJ) retain]
#endif

// Use this to prevent an object from being dealloced in this scope, even if you call something
// that releases it.
#if __has_feature(objc_arc)
#define MYDeferDealloc(OBJ) __unused id _deferDealloc_##__LINE__ = (OBJ)
#else
#define MYDeferDealloc(OBJ) [[(OBJ) retain] autorelease]
#endif

#if __has_attribute(noescape)
#  ifdef NS_NOESCAPE
#    define MYNoEscape NS_NOESCAPE
#  else
#    define MYNoEscape __attribute((noescape))
#  endif
#else
#  define MYNoEscape
#endif

#define $true   ((NSNumber*)kCFBooleanTrue)
#define $false  ((NSNumber*)kCFBooleanFalse)
#define $null   [NSNull null]


@interface NSObject (MYUtils)
- (NSString*) my_compactDescription;
@end

@interface NSArray (MYUtils)
- (BOOL) my_containsObjectIdenticalTo: (id)object;
- (NSArray*) my_map: (MYNoEscape id (^)(id obj))block;
- (NSArray*) my_filter: (MYNoEscape int (^)(id obj))block;
@end

@interface NSMutableArray (MYUtils)
- (void) my_removeMatching: (MYNoEscape int (^)(id obj))block;
@end

#if MY_ENABLE_ENUMERATOR_MAP
@interface NSEnumerator (MYUtils)
- (NSEnumerator*) my_map: (MYNoEscape id (^)(id obj))block;
@end
#endif

@interface NSSet (MYUtils)
+ (NSSet*) my_unionOfSet: (NSSet*)set1 andSet: (NSSet*)set2;
+ (NSSet*) my_intersectionOfSet: (NSSet*)set1 andSet: (NSSet*)set2;
+ (NSSet*) my_differenceOfSet: (NSSet*)set1 andSet: (NSSet*)set2;
@end

@interface NSDictionary (MYUtils)
- (NSDictionary*) my_dictionaryByUpdatingValues: (MYNoEscape id (^)(id key, id value))block;

@end


@interface NSData (MYUtils)
- (NSString*) my_UTF8ToString;
@end


#ifdef GNUSTEP
#define kCFBooleanTrue  ([NSNumber numberWithBool: YES])
#define kCFBooleanFalse ([NSNumber numberWithBool: NO])
#endif


// Internals (don't use directly)
typedef id _dictpair[2];
NSDictionary* _dictof(const _dictpair*, size_t count);
NSMutableDictionary* _mdictof(const _dictpair[], size_t count);
id _box(const void *value, const char *encoding);
id _cast(Class,id);
id _castNotNil(Class,id);
id _castIf(Class,id);
id _castIfProto(Protocol*,id);
NSArray* _castArrayOf(Class,NSArray*);
NSArray* _castIfArrayOf(Class,NSArray*);
