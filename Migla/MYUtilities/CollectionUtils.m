//
//  CollectionUtils.m
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008-2013 Jens Alfke. All rights reserved.
//

#import "CollectionUtils.h"
#import "Test.h"


#if !__has_feature(objc_arc)
#error This source file must be compiled with ARC
#endif


NSDictionary* _dictof(const _dictpair pairs[], size_t count)
{
    CAssert(count<10000);
    id objects[count], keys[count];
    size_t n = 0;
    const _dictpair* pair = pairs;
    for( size_t i=0; i<count; i++,pair++ ) {
        if( (*pair)[1] ) {
            keys[n] = (*pair)[0];
            objects[n] = (*pair)[1];
            n++;
        }
    }
    return [NSDictionary dictionaryWithObjects: objects forKeys: keys count: n];
}


NSMutableDictionary* _mdictof(const _dictpair pairs[], size_t count)
{
    CAssert(count<10000);
    id objects[count], keys[count];
    size_t n = 0;
    const _dictpair* pair = pairs;
    for( size_t i=0; i<count; i++,pair++ ) {
        if( (*pair)[1] ) {
            keys[n] = (*pair)[0];
            objects[n] = (*pair)[1];
            n++;
        }
    }
    return [NSMutableDictionary dictionaryWithObjects: objects forKeys: keys count: n];
}


BOOL $equal(id obj1, id obj2)      // Like -isEqual: but works even if either/both are nil
{
    if( obj1 )
        return obj2 && [obj1 isEqual: obj2];
    else
        return obj2==nil;
}


id _box(const void *value, const char *encoding)
{
    // file:///Developer/Documentation/DocSets/com.apple.ADC_Reference_Library.DeveloperTools.docset/Contents/Resources/Documents/documentation/DeveloperTools/gcc-4.0.1/gcc/Type-encoding.html
    char e = encoding[0];
    if( e=='r' )                // ignore 'const' modifier
        e = encoding[1];
    switch( e ) {
        case 'B':   return [NSNumber numberWithBool: *(BOOL*)value];
        case 'c':   return [NSNumber numberWithChar: *(char*)value];
        case 'C':   return [NSNumber numberWithUnsignedChar: *(char*)value];
        case 's':   return [NSNumber numberWithShort: *(short*)value];
        case 'S':   return [NSNumber numberWithUnsignedShort: *(unsigned short*)value];
        case 'i':   return [NSNumber numberWithInt: *(int*)value];
        case 'I':   return [NSNumber numberWithUnsignedInt: *(unsigned int*)value];
        case 'l':   return [NSNumber numberWithLong: *(long*)value];
        case 'L':   return [NSNumber numberWithUnsignedLong: *(unsigned long*)value];
        case 'q':   return [NSNumber numberWithLongLong: *(long long*)value];
        case 'Q':   return [NSNumber numberWithUnsignedLongLong: *(unsigned long long*)value];
        case 'f':   return [NSNumber numberWithFloat: *(float*)value];
        case 'd':   return [NSNumber numberWithDouble: *(double*)value];
        case '*':   return [NSString stringWithUTF8String: *(char**)value];
        case '@':   return (__bridge id)*(void**)value;
        default:    return [NSValue value: value withObjCType: encoding];
    }
}


id _cast( Class requiredClass, id object )
{
    if( object && ! [object isKindOfClass: requiredClass] )
        [NSException raise: NSInvalidArgumentException format: @"%@ required, but got %@ %p",
         requiredClass,[object class],object];
    return object;
}

id _castNotNil( Class requiredClass, id object )
{
    if( ! [object isKindOfClass: requiredClass] )
        [NSException raise: NSInvalidArgumentException format: @"%@ required, but got %@ %p",
         requiredClass,[object class],object];
    return object;
}

id _castIf( Class requiredClass, id object )
{
    if( object && ! [object isKindOfClass: requiredClass] )
        object = nil;
    return object;
}

id _castIfProto( Protocol* requiredProtocol, id object )
{
    if( object && ! [object conformsToProtocol: requiredProtocol] )
        object = nil;
    return object;
}

NSArray* _castArrayOf(Class itemClass, NSArray *a)
{
    for(id item in $cast(NSArray,a) )
        _cast(itemClass,item);
    return a;
}

NSArray* _castIfArrayOf(Class itemClass, NSArray *a)
{
    a = $castIf(NSArray,a);
    for(id item in a )
        if (!_castIf(itemClass,item))
            return nil;
    return a;
}


void cfSetObj(void *var, CFTypeRef value) {
    CFTypeRef oldValue = *(CFTypeRef*)var;
    if( value != oldValue ) {
        cfrelease(oldValue);
        *(CFTypeRef*)var = cfretain(value);
    }
}


@implementation NSObject (MYUtils)
- (NSString*) my_compactDescription
{
    return [self description];
}
@end


@implementation NSString (MYUtils)

- (NSString*) my_compactDescription
{
    return $sprintf(@"\"%@\"", self);
}

@end


@implementation NSArray (MYUtils)

- (BOOL) my_containsObjectIdenticalTo: (id)object
{
    return [self indexOfObjectIdenticalTo: object] != NSNotFound;
}


- (NSArray*) my_map: (id (^)(id obj))block {
    NSMutableArray* mapped = [[NSMutableArray alloc] initWithCapacity: self.count];
    for (id obj in self) {
        id mappedObj = block(obj);
        if (mappedObj)
            [mapped addObject: mappedObj];
    }
    return [mapped copy];
}

- (NSArray*) my_filter: (int (^)(id obj))block {
    NSMutableArray* filtered = [[NSMutableArray alloc] initWithCapacity: self.count];
    for (id obj in self) {
        if (block(obj))
            [filtered addObject: obj];
    }
    return [filtered copy];
}


- (NSString*) my_compactDescription
{
    NSMutableString *desc = [NSMutableString stringWithCapacity: 100];
    [desc appendString: @"["];
    BOOL first = YES;
    for(id item in self) {
        if( first )
            first = NO;
        else
            [desc appendString: @", "];
        [desc appendString: [item my_compactDescription]];
    }
    [desc appendString: @"]"];
    return desc;
}

@end



@implementation NSMutableArray (MYUtils)

- (void) my_removeMatching: (int (^)(id obj))block {
    for (NSInteger i = self.count - 1; i >= 0; --i) {
        if (!block([self objectAtIndex: i]))
            [self removeObjectAtIndex: i];
    }
}

@end




@implementation NSSet (MYUtils)

- (NSString*) my_compactDescription
{
    return [[self allObjects] my_compactDescription];
}

+ (NSSet*) my_unionOfSet: (NSSet*)set1 andSet: (NSSet*)set2
{
    if( set1 == set2 || set2.count==0 )
        return set1;
    else if( set1.count==0 )
        return set2;
    else {
        NSMutableSet *result = [set1 mutableCopy];
        [result unionSet: set2];
        return result;
    }
}

+ (NSSet*) my_intersectionOfSet: (NSSet*)set1 andSet: (NSSet*)set2
{
    if( set1 == set2 || set1.count==0 )
        return set1;
    else if( set2.count==0 )
        return set2;
    else {
        NSMutableSet *result = [set1 mutableCopy];
        [result intersectSet: set2];
        return result;
    }
}

+ (NSSet*) my_differenceOfSet: (NSSet*)set1 andSet: (NSSet*)set2
{
    if( set1.count==0 || set2.count==0 )
        return set1;
    else if( set1==set2 )
        return [NSSet set];
    else {
        NSMutableSet *result = [set1 mutableCopy];
        [result minusSet: set2];
        return result;
    }
}

@end


@implementation NSDictionary (MYUtils)

- (NSString*) my_compactDescription
{
    NSMutableString *desc = [NSMutableString stringWithCapacity: 100];
    [desc appendString: @"{"];
    BOOL first = YES;
    for(id key in [[self allKeys] sortedArrayUsingSelector: @selector(compare:)]) {
        if( first )
            first = NO;
        else
            [desc appendString: @", "];
        id value = [self objectForKey: key];
        [desc appendString: [key my_compactDescription]];
        [desc appendString: @": "];
        [desc appendString: [value my_compactDescription]];
    }
    [desc appendString: @"}"];
    return desc;
}


- (NSDictionary*) my_dictionaryByUpdatingValues: (id (^)(id key, id value))block {
    __block NSMutableDictionary* updated = nil;
    [self enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        id nuValue = block(key, value);
        if (nuValue != value) {
            if (!updated)
                updated = [self mutableCopy];
            [updated setValue: nuValue forKey: key];
        }
    }];
    return updated ?: self;
}


@end


@implementation NSData (MYUtils)

- (NSString*) my_UTF8ToString {
    return [[NSString alloc] initWithData: self encoding: NSUTF8StringEncoding];
}

@end


#if MY_ENABLE_ENUMERATOR_MAP
@interface MYMappedEnumerator : NSEnumerator
{
    NSEnumerator* _source;
    id (^_filter)(id obj) ;
}
- (instancetype) initWithEnumerator: (NSEnumerator*)enumerator filter: (id (^)(id obj))filter;
@end

@implementation MYMappedEnumerator

- (instancetype) initWithEnumerator: (NSEnumerator*)enumerator filter: (id (^)(id obj))filter {
    self = [super init];
    if (self) {
        _source = [enumerator retain];
        _filter = [filter copy];
    }
    return self;
}

- (void)dealloc
{
    [_source release];
    [_filter release];
    [super dealloc];
}

- (id) nextObject {
    id obj;
    while (nil != (obj = [_source nextObject])) {
        id mapped = _filter(obj);
        if (mapped)
            return mapped;
    }
    return nil;
}

@end


@implementation NSEnumerator (MYUtils)

- (NSEnumerator*) my_map: (id (^)(id obj))block {
    return [[[MYMappedEnumerator alloc] initWithEnumerator: self filter: block] autorelease];
}

@end
#endif // MY_ENABLE_ENUMERATOR_MAP


#if DEBUG
#import "Test.h"

TestCase(CollectionUtils) {
    NSArray *a = $array(@"foo",@"bar",@"baz");
    //Log(@"a = %@",a);
    NSArray *aa = [NSArray arrayWithObjects: @"foo",@"bar",@"baz",nil];
    CAssertEqual(a,aa);

    const char *cstr = "a C string";
    id o = $object(cstr);
    //Log(@"o = %@",o);
    CAssertEqual(o,@"a C string");

    NSDictionary *d = $dict({@"int",    $object(1)},
                            {@"double", $object(-1.1)},
                            {@"char",   $object('x')},
                            {@"ulong",  $object(1234567UL)},
                            {@"longlong",$object(987654321LL)},
                            {@"cstr",   $object(cstr)});
    //Log(@"d = %@",d);
    NSDictionary *dd = [NSDictionary dictionaryWithObjectsAndKeys:
                        [NSNumber numberWithInt: 1],                    @"int",
                        [NSNumber numberWithDouble: -1.1],              @"double",
                        [NSNumber numberWithChar: 'x'],                 @"char",
                        [NSNumber numberWithUnsignedLong: 1234567UL],   @"ulong",
                        [NSNumber numberWithDouble: 987654321LL],       @"longlong",
                        @"a C string",                                  @"cstr",
                        nil];
    CAssertEqual(d,dd);

#if MY_ENABLE_ENUMERATOR_MAP
    NSEnumerator* source = [$array(@"teenage", @"mutant", @"ninja", @"turtles") objectEnumerator];
    NSEnumerator* mapped = [source my_map: ^id(NSString* str) {
        return [str hasPrefix: @"t"] ? [str uppercaseString] : nil;
    }];
    CAssertEqual(mapped.allObjects, $array(@"TEENAGE", @"TURTLES"));
#endif
}
#endif

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
