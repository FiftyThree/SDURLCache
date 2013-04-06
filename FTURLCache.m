//
//  FTURLCache.m
//  Unknown Project
//
//  Copyright (c) 2013 FiftyThree, Inc. All rights reserved.
//

#include <objc/runtime.h>
#import "FTURLCache.h"

static NSString * const kCanBeRetrievedFromColdStorageHeader = @"X-FiftyThree-CanBeRetrievedFromColdStorage";
static NSString * const kShouldBePlacedInColdStorageHeader = @"X-FiftyThree-ShouldBePlacedInColdStorage";
static NSString * const kColdStorageHeader = @"X-FiftyThree-ColdStorage";

static NSString * const kCacheControlHeader = @"Cache-Control";
static NSString * const kCacheControlOriginalHeader = @"X-FiftyThree-Cache-Control-Original";
static NSString * const kCacheControlHeaderValueOneYear = @"public, max-age=31536000";

@implementation NSURLRequest (ColdStorage)

- (BOOL)canBeRetrievedFromColdStorage
{
    return [self valueForHTTPHeaderField:kCanBeRetrievedFromColdStorageHeader] != nil;
}

- (BOOL)shouldBePlacedInColdStorage
{
    return [self valueForHTTPHeaderField:kShouldBePlacedInColdStorageHeader] != nil;
}

@end

@implementation NSMutableURLRequest (ColdStorage)

- (void)setCanBeRetrievedFromColdStorage:(BOOL)canBeRetrievedFromColdStorage
{
    // The value of this property is recorded as the presence/absence of an HTTP header field on the request.
    // This is the best approach to persisting the property through the entire pipeline because in many cases
    // the request object itself will not be maintained throughout.
    NSString *headerValue = canBeRetrievedFromColdStorage ? @"" : nil;
    [self setValue:headerValue forHTTPHeaderField:kCanBeRetrievedFromColdStorageHeader];
}

- (void)setShouldBePlacedInColdStorage:(BOOL)shouldBePlacedInColdStorage
{
    // The value of this property is recorded as the presence/absence of an HTTP header field on the request.
    // This is the best approach to persisting the property through the entire pipeline because in many cases
    // the request object itself will not be maintained throughout.
    NSString *headerValue = shouldBePlacedInColdStorage ? @"" : nil;
    [self setValue:headerValue forHTTPHeaderField:kShouldBePlacedInColdStorageHeader];
}

@end

@interface FTURLCache ()

@property (nonatomic) SDURLCache *coldStorageCache;

@end

@implementation FTURLCache

- (id)initWithMemoryCapacity:(NSUInteger)memoryCapacity
                diskCapacity:(NSUInteger)diskCapacity
                    diskPath:(NSString *)path
{
    self = [super initWithMemoryCapacity:memoryCapacity diskCapacity:diskCapacity diskPath:path];
    if (self)
    {
        // Initialize the cold storage cache with non memory capacity. We only want to use it for on-disk
        // caching.
        NSString *diskPath = [[SDURLCache defaultCachePath] stringByAppendingPathComponent:@"coldStorage"];
        self.coldStorageCache = [[SDURLCache alloc] initWithMemoryCapacity:0
                                                              diskCapacity:15<<20
                                                                  diskPath:diskPath];
    }
    return self;
}

// The cache behaves just as the default NSURLCache, except in the case where the request was marked as
// "canBeRetrievedFromColdStorage". In this case, we fetch the response from the cold storage cache in the
// event that its not in the normal cache.
- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request
{
    NSCachedURLResponse *cachedResponse;

    cachedResponse = [super cachedResponseForRequest:request];

    if (!cachedResponse && request.canBeRetrievedFromColdStorage)
    {
        cachedResponse = [self.coldStorageCache cachedResponseForRequest:request];
    }

    // If the response is not already in the cold storage, but we managed to pull it from normal cache, and it
    // should be in cold storage, then write it there. This could happen if we previously loaded the request
    // without the cold storage flag set and now are trying to load it with it set.
    if (cachedResponse &&
        request.shouldBePlacedInColdStorage &&
        ![self.coldStorageCache cachedResponseForRequest:request])
    {
        NSCachedURLResponse *modifiedCachedURLResponse = [self coldStorageCachedResponseBasedOnResponse:cachedResponse];
        [self.coldStorageCache storeCachedResponse:modifiedCachedURLResponse
                                        forRequest:request];
    }

    return cachedResponse;
}

// The cache behaves just as the default NSURLCache, except in the case where the request was marked as
// "shouldBePlacedInColdStorage". In this case, the request is written to the cache as normal and additionally
// it is written to the cold storage cache (regarldess of its Cache-Control settings).
- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request
{
    NSString *coldStorageHeaderValue;
    if ([cachedResponse.response isKindOfClass:NSHTTPURLResponse.class])
    {
        coldStorageHeaderValue = ((NSHTTPURLResponse *)cachedResponse.response).allHeaderFields[kColdStorageHeader];
    }

    // Store the response to the normal cache. We make sure to *never* polute this cache with a response from
    // cold storage.
    if (!coldStorageHeaderValue)
    {
        [super storeCachedResponse:cachedResponse forRequest:request];
    }

    if (request.shouldBePlacedInColdStorage)
    {
        NSCachedURLResponse *modifiedCachedURLResponse = [self coldStorageCachedResponseBasedOnResponse:cachedResponse];
        [self.coldStorageCache storeCachedResponse:modifiedCachedURLResponse
                                        forRequest:request];
    }
}

// Returns a new NSCachedURLResponse that is an exact copy of the existing response with the following
// modifications:
//
// - The Cache-Control header is set to 1 year.
// - If the Cache-Control header was already already present, then the old value is backed up as a new header.
// - A cold storage header is added, so that the response can later be identified as coming from old storage.
- (NSCachedURLResponse *)coldStorageCachedResponseBasedOnResponse:(NSCachedURLResponse *)cachedURLResponse
{
    if ([cachedURLResponse.response isKindOfClass:[NSHTTPURLResponse class]])
    {
        NSHTTPURLResponse *httpURLResponse = (NSHTTPURLResponse *)cachedURLResponse.response;

        NSMutableDictionary *headerFields = [httpURLResponse.allHeaderFields mutableCopy];

        // Mark this response as coming from cold storage.
        headerFields[kColdStorageHeader] = @"";

        // If there's already a cache control header, then back it up.
        if (headerFields[kCacheControlHeader])
        {
            headerFields[kCacheControlOriginalHeader] = headerFields[kCacheControlHeader];
        }

        // Store the new cache control header
        headerFields[kCacheControlHeader] = kCacheControlHeaderValueOneYear;

        NSURLResponse *modifiedHTTPURLResponse = [[NSHTTPURLResponse alloc] initWithURL:httpURLResponse.URL
                                                                             statusCode:httpURLResponse.statusCode
                                                                            HTTPVersion:@"HTTP/1.1"
                                                                           headerFields:headerFields];

        return [[NSCachedURLResponse alloc] initWithResponse:modifiedHTTPURLResponse
                                                        data:cachedURLResponse.data
                                                    userInfo:cachedURLResponse.userInfo
                                               storagePolicy:cachedURLResponse.storagePolicy];
    }
    else
    {
        return cachedURLResponse;
    }
}

@end
