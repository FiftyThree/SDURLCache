//
//  FTURLCache.h
//  Unknown Project
//
//  Copyright (c) 2013 FiftyThree, Inc. All rights reserved.
//

#import "SDURLCache.h"

@interface NSURLRequest (ColdStorage)

// If set, an attempt will be made to retrieve the request from cold storage, provided it's not in the normal
// cache.
- (BOOL)canBeRetrievedFromColdStorage;

// If set, the response to this request will be placed in cold storage, regardless of its Cache-Control
// settings.
- (BOOL)shouldBePlacedInColdStorage;

@end

@interface NSMutableURLRequest (ColdStorage)

// If set, an attempt will be made to retrieve the request from cold storage, provided it's not in the normal
// cache.
- (void)setCanBeRetrievedFromColdStorage:(BOOL)canBeRetrievedFromColdStorage;

// If set, the response to this request will be placed in cold storage, regardless of its Cache-Control
// settings.
- (void)setShouldBePlacedInColdStorage:(BOOL)shouldBePlacedInColdStorage;

@end

@interface FTURLCache : NSURLCache

@end
