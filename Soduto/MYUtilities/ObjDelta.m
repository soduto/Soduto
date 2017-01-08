//
//  ObjDelta.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/25/13.
//
//

#import "ObjDelta.h"
#import "Test.h"


// If this is set to YES, deltas will always include the delta-form of an object even if it's
// longer than the entire replacement. Used only in testing.
static BOOL sIgnoreLength;


// Approximate number of bytes of the JSON encoding of this object
static NSUInteger lengthInJSON(id obj) {
    if ([obj isKindOfClass: [NSString class]]) {
        return 2 + [obj length];        //FIX: Assuming ASCII text and no escapes
    } else if ([obj isKindOfClass: [NSNumber class]]) {
        const char* encoding = [obj objCType];
        if (encoding[0] == 'f')
            return 7;
        else if (encoding[0] == 'd')
            return 10;
        else if (obj == (id)kCFBooleanFalse)
            return 5;
        else if (obj == (id)kCFBooleanTrue)
            return 4;
        else
            return (NSUInteger)ceil(log10([obj doubleValue]));
    } else if ([obj isKindOfClass: [NSDictionary class]]) {
        NSUInteger len = 1;
        for (NSString* key in obj)
            len += lengthInJSON(key) + 2 + lengthInJSON([obj objectForKey: key]);
        return len;
    } else if ([obj isKindOfClass: [NSArray class]]) {
        NSUInteger len = 1;
        for (id item in obj)
            len += lengthInJSON(item) + 1;
        return len;
    } else if ([obj isKindOfClass: [NSNull class]]) {
        return 4;
    } else if (obj == nil) {
        return 0;
    } else {
        Assert(NO, @"Invalid JSON object, class %@: %@", [obj class], obj);
    }
}


#pragma mark - CREATING DIFFS:


static NSArray* DeltaArrays(NSArray* a, NSArray* b) {
    NSMutableArray* delta = $marray();
    NSUInteger na = a.count, nb = b.count;
    for (NSUInteger i = 0; i < nb; i++) {
        id aa = (i < na) ? a[i] : nil;
        id bb = b[i];
        id d = DeltaObjects(aa, bb);
        if (d) {
            // Record a change by appending its index and the new value:
            [delta addObject: @(i)];
            [delta addObject: d];
        }
    }
    if (nb < na) {
        // Record that a got truncated:
        [delta addObject: @(nb)];
        [delta addObject: @[]];
    }
    return delta;
}


static NSDictionary* DeltaDictionaries(NSDictionary* a, NSDictionary* b) {
    NSMutableDictionary* delta = $mdict();
    for (id key in a) {
        id d = DeltaObjects(a[key], b[key]);
        if (d)
            delta[key] = d;
    }
    for (id key in b) {
        if (!a[key]) {
            delta[key] = b[key];
        }
    }
    return delta;
}


id DeltaObjects(id a, id b) {
    if ($equal(a, b))
        return nil;
    if ([a isKindOfClass: [NSDictionary class]]) {
        if ([b isKindOfClass: [NSDictionary class]]) {
            id delta = DeltaDictionaries(a, b);
            if (sIgnoreLength || lengthInJSON(delta) < lengthInJSON(b) + 2)
                return delta;
        }
    } else if ([a isKindOfClass: [NSArray class]]) {
        if ([b isKindOfClass: [NSArray class]]) {
            id delta = DeltaArrays(a, b);
            if (sIgnoreLength || lengthInJSON(delta) < lengthInJSON(b) + 2)
                return delta;
        }
    } else if ([a isKindOfClass: [NSNumber class]]) {
        if ([b isKindOfClass: [NSNumber class]]) {
            double na = [a doubleValue], nb = [b doubleValue];
            if (fabs(na-nb)/fmax(fabs(na),fabs(nb)) < 1.0e-6)
                return nil; // numbers are equal within rounding error
        }
    }

    return b ? @[b] : @[];
}


#pragma mark - APPLYING DIFFS:


static NSArray* ApplyDeltaToArray(NSArray* a, NSArray* delta) {
    NSMutableArray* b = [a mutableCopy];
    NSUInteger nb = b.count;
    for (NSUInteger i = 0; i < delta.count; i += 2) {
        NSUInteger index = [delta[i] unsignedIntegerValue];
        id bb = (i < nb) ? b[i] : nil;
        id updated = ApplyDeltaToObject(bb, delta[i+1]);
        if (updated == nil) {
            // Was truncated here
            [b removeObjectsInRange: NSMakeRange(index, b.count-index)];
            break;
        } else if (index < nb) {
            b[index] = updated;
        } else {
            AssertEq(index, nb);
            [b addObject: updated];
            nb++;
        }
    }
    return b;
}


static NSDictionary* ApplyDeltaToDict(NSDictionary* a, NSDictionary* delta) {
    NSMutableDictionary* b = [a mutableCopy];
    for (NSString* key in delta) {
        id value = ApplyDeltaToObject(b[key], delta[key]);
        [b setValue: value forKey: key];
    }
    return b;
}


id ApplyDeltaToObject(id object, id delta) {
    if (delta == nil) {
        return object;
    } else if ([delta isKindOfClass: [NSDictionary class]]) {
        Assert([object isKindOfClass: [NSDictionary class]]);
        return ApplyDeltaToDict(object, delta);
    } else if ([delta isKindOfClass: [NSArray class]]) {
        NSUInteger count = [delta count];
        if (count == 0)
            return nil;
        else if (count == 1)
            return [delta objectAtIndex: 0];
        else {
            Assert([object isKindOfClass: [NSArray class]]);
            return ApplyDeltaToArray(object, delta);
        }
    } else {
        return delta;
    }
}




#pragma mark - TESTS:
#if DEBUG

static NSString* toJSON(id obj) {
    if (!obj)
        return nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject: obj options: 0 error: NULL];
    return data.my_UTF8ToString;
}

static void testDelta(id a, id b) {
    Log(@"A = %@", toJSON(a));
    Log(@"B = %@", toJSON(b));
    id delta = DeltaObjects(a, b);
    Log(@"Delta = %@", toJSON(delta));
    id recover = ApplyDeltaToObject(a, delta);
    Log(@"Result = %@", toJSON(recover));
    AssertEqual(recover, b);
}


TestCase(DeltaObjects) {
    sIgnoreLength = YES;
    id a = @{@"foo": @"bar"};
    id b = @{@"foo": @"baz"};
    testDelta(a,a);
    testDelta(a, b);

    a = @{@"foo": @{@"age": @18}};
    b = @{@"foo": @{@"age": @19}};
    testDelta(a, b);
    b = @{@"foo": @{@"size": @8}};
    testDelta(a, b);
    a = @{@"foo": @{@"age": @18}, @"bar": @YES};
    testDelta(a, b);

    a = @[@1, @2, @3];
    b = @[@1, @99, @3];
    testDelta(a, b);
    testDelta(@{@"x": a}, @{@"x": b});

    a = @[@1, @2, @3, @4];
    b = @[@1, @99, @3];
    testDelta(a, b);
    testDelta(b, a);

    testDelta(@{@"foo": @{@"a": @"b"}}, @{@"foo": @[@1]});
    sIgnoreLength = NO;
}
#endif //DEBUG
