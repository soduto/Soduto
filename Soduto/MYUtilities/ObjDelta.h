//
//  ObjDelta.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/25/13.
//
//

#import <Foundation/Foundation.h>


/** Returns a JSON-compatible object (a "delta") that describes how to change oldObject into newObject. */
id DeltaObjects(id oldObject, id newObject);

/** Applies a delta to the old version of an object, returning the new version. */
id ApplyDeltaToObject(id oldObject, id delta);
