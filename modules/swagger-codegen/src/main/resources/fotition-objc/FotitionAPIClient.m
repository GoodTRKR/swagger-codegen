#import "FotitionAPIClient.h"
#import "FTFile.h"
#import "FTQueryParamCollection.h"
#import "FTConfiguration.h"

@implementation FotitionAPIClient

NSString *const FotitionResponseObjectErrorKey = @"FotitionResponseObject";

static long requestId = 0;
static bool offlineState = false;
static NSMutableSet * queuedRequests = nil;
static bool cacheEnabled = false;
static AFNetworkReachabilityStatus reachabilityStatus = AFNetworkReachabilityStatusNotReachable;
static NSOperationQueue* sharedQueue;
static void (^reachabilityChangeBlock)(int);
static bool loggingEnabled = true;

#pragma mark - Log Methods

+(void)setLoggingEnabled:(bool) state {
    loggingEnabled = state;
}

- (void)logRequest:(NSURLRequest*)request {
    NSLog(@"request: %@", [self descriptionForRequest:request]);
}

- (void)logResponse:(id)data forRequest:(NSURLRequest*)request error:(NSError*)error {
    NSLog(@"request: %@  response: %@ ",  [self descriptionForRequest:request], data );
}

#pragma mark -

+(void)clearCache {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

+(void)setCacheEnabled:(BOOL)enabled {
    cacheEnabled = enabled;
}

+(void)configureCacheWithMemoryAndDiskCapacity: (unsigned long) memorySize
                                      diskSize: (unsigned long) diskSize {
    NSAssert(memorySize > 0, @"invalid in-memory cache size");
    NSAssert(diskSize >= 0, @"invalid disk cache size");

    NSURLCache *cache =
    [[NSURLCache alloc]
     initWithMemoryCapacity:memorySize
     diskCapacity:diskSize
     diskPath:@"swagger_url_cache"];

    [NSURLCache setSharedURLCache:cache];
}

+(NSOperationQueue*) sharedQueue {
    return sharedQueue;
}

+(FotitionAPIClient *)sharedClientFromPool:(NSString *)baseUrl {
    static NSMutableDictionary *_pool = nil;
    if (queuedRequests == nil) {
        queuedRequests = [[NSMutableSet alloc]init];
    }
    if(_pool == nil) {
        // setup static vars
        // create queue
        sharedQueue = [[NSOperationQueue alloc] init];

        // create pool
        _pool = [[NSMutableDictionary alloc] init];

        // initialize URL cache
        [FotitionAPIClient configureCacheWithMemoryAndDiskCapacity:4*1024*1024 diskSize:32*1024*1024];

        // configure reachability
        [FotitionAPIClient configureCacheReachibilityForHost:baseUrl];
    }

    @synchronized(self) {
        FotitionAPIClient * client = [_pool objectForKey:baseUrl];
        if (client == nil) {
            client = [[FotitionAPIClient alloc] initWithBaseURL:[NSURL URLWithString:baseUrl]];
            [_pool setValue:client forKey:baseUrl ];
            if(loggingEnabled)
                NSLog(@"new client for path %@", baseUrl);
        }
        if(loggingEnabled)
            NSLog(@"returning client for path %@", baseUrl);
        return client;
    }
}

/*
 * Detect `Accept` from accepts
 */
+ (NSString *) selectHeaderAccept:(NSArray *)accepts
{
    if (accepts == nil || [accepts count] == 0) {
        return @"";
    }
    
    NSMutableArray *lowerAccepts = [[NSMutableArray alloc] initWithCapacity:[accepts count]];
    [accepts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [lowerAccepts addObject:[obj lowercaseString]];
    }];

    
    if ([lowerAccepts containsObject:@"application/json"]) {
        return @"application/json";
    }
    else {
        return [lowerAccepts componentsJoinedByString:@", "];
    }
}

/*
 * Detect `Content-Type` from contentTypes
 */
+ (NSString *) selectHeaderContentType:(NSArray *)contentTypes
{
    if (contentTypes == nil || [contentTypes count] == 0) {
        return @"application/json";
    }
    
    NSMutableArray *lowerContentTypes = [[NSMutableArray alloc] initWithCapacity:[contentTypes count]];
    [contentTypes enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [lowerContentTypes addObject:[obj lowercaseString]];
    }];

    if ([lowerContentTypes containsObject:@"application/json"]) {
        return @"application/json";
    }
    else {
        return lowerContentTypes[0];
    }
}

-(void)setHeaderValue:(NSString*) value
               forKey:(NSString*) forKey {
    [self.requestSerializer setValue:value forHTTPHeaderField:forKey];
}

+(unsigned long)requestQueueSize {
    return [queuedRequests count];
}

+(NSNumber*) nextRequestId {
    @synchronized(self) {
        long nextId = ++requestId;
        if(loggingEnabled)
            NSLog(@"got id %ld", nextId);
        return [NSNumber numberWithLong:nextId];
    }
}

+(NSNumber*) queueRequest {
    NSNumber* requestId = [FotitionAPIClient nextRequestId];
    if(loggingEnabled)
        NSLog(@"added %@ to request queue", requestId);
    [queuedRequests addObject:requestId];
    return requestId;
}

+(void) cancelRequest:(NSNumber*)requestId {
    [queuedRequests removeObject:requestId];
}

+(NSString*) escape:(id)unescaped {
    if([unescaped isKindOfClass:[NSString class]]){
        return (NSString *)CFBridgingRelease
        (CFURLCreateStringByAddingPercentEscapes(
                                                 NULL,
                                                 (__bridge CFStringRef) unescaped,
                                                 NULL,
                                                 (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                                 kCFStringEncodingUTF8));
    }
    else {
        return [NSString stringWithFormat:@"%@", unescaped];
    }
}

-(Boolean) executeRequestWithId:(NSNumber*) requestId {
    NSSet* matchingItems = [queuedRequests objectsPassingTest:^BOOL(id obj, BOOL *stop) {
        if([obj intValue]  == [requestId intValue])
            return TRUE;
        else return FALSE;
    }];

    if(matchingItems.count == 1) {
        if(loggingEnabled)
            NSLog(@"removing request id %@", requestId);
        [queuedRequests removeObject:requestId];
        return true;
    }
    else
        return false;
}

-(id)initWithBaseURL:(NSURL *)url {
    self = [super initWithBaseURL:url];
    self.requestSerializer = [AFJSONRequestSerializer serializer];
    self.responseSerializer = [AFJSONResponseSerializer serializer];
    if (!self)
        return nil;
    return self;
}

+(AFNetworkReachabilityStatus) getReachabilityStatus {
    return reachabilityStatus;
}

+(void) setReachabilityChangeBlock:(void(^)(int))changeBlock {
    reachabilityChangeBlock = changeBlock;
}

+(void) setOfflineState:(BOOL) state {
    offlineState = state;
}

+(void) configureCacheReachibilityForHost:(NSString*)host {
    [[FotitionAPIClient sharedClientFromPool:host].reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        reachabilityStatus = status;
        switch (status) {
            case AFNetworkReachabilityStatusUnknown:
                if(loggingEnabled)
                    NSLog(@"reachability changed to AFNetworkReachabilityStatusUnknown");
                [FotitionAPIClient setOfflineState:true];
                break;

            case AFNetworkReachabilityStatusNotReachable:
                if(loggingEnabled)
                    NSLog(@"reachability changed to AFNetworkReachabilityStatusNotReachable");
                [FotitionAPIClient setOfflineState:true];
                break;

            case AFNetworkReachabilityStatusReachableViaWWAN:
                if(loggingEnabled)
                    NSLog(@"reachability changed to AFNetworkReachabilityStatusReachableViaWWAN");
                [FotitionAPIClient setOfflineState:false];
                break;

            case AFNetworkReachabilityStatusReachableViaWiFi:
                if(loggingEnabled)
                    NSLog(@"reachability changed to AFNetworkReachabilityStatusReachableViaWiFi");
                [FotitionAPIClient setOfflineState:false];
                break;
            default:
                break;
        }
        // call the reachability block, if configured
        if(reachabilityChangeBlock != nil) {
            reachabilityChangeBlock(status);
        }
    }];
    [[FotitionAPIClient sharedClientFromPool:host].reachabilityManager startMonitoring];
}

-(NSString*) pathWithQueryParamsToString:(NSString*) path
                             queryParams:(NSDictionary*) queryParams {
    NSString * separator = nil;
    int counter = 0;

    NSMutableString * requestUrl = [NSMutableString stringWithFormat:@"%@", path];
    if(queryParams != nil){
        for(NSString * key in [queryParams keyEnumerator]){
            if(counter == 0) separator = @"?";
            else separator = @"&";
            NSString * value;
            id queryParam = [queryParams valueForKey:key];
            if([queryParam isKindOfClass:[NSString class]]){
                [requestUrl appendString:[NSString stringWithFormat:@"%@%@=%@", separator,
                                          [FotitionAPIClient escape:key], [FotitionAPIClient escape:[queryParams valueForKey:key]]]];
            }
            else if([queryParam isKindOfClass:[FTQueryParamCollection class]]){
                FTQueryParamCollection * coll = (FTQueryParamCollection*) queryParam;
                NSArray* values = [coll values];
                NSString* format = [coll format];

                if([format isEqualToString:@"csv"]) {
                    [requestUrl appendString:[NSString stringWithFormat:@"%@%@=%@", separator,
                        [FotitionAPIClient escape:key], [NSString stringWithFormat:@"%@", [values componentsJoinedByString:@","]]]];

                }
                else if([format isEqualToString:@"tsv"]) {
                    [requestUrl appendString:[NSString stringWithFormat:@"%@%@=%@", separator,
                        [FotitionAPIClient escape:key], [NSString stringWithFormat:@"%@", [values componentsJoinedByString:@"\t"]]]];

                }
                else if([format isEqualToString:@"pipes"]) {
                    [requestUrl appendString:[NSString stringWithFormat:@"%@%@=%@", separator,
                        [FotitionAPIClient escape:key], [NSString stringWithFormat:@"%@", [values componentsJoinedByString:@"|"]]]];

                }
                else if([format isEqualToString:@"multi"]) {
                    for(id obj in values) {
                        [requestUrl appendString:[NSString stringWithFormat:@"%@%@=%@", separator,
                            [FotitionAPIClient escape:key], [NSString stringWithFormat:@"%@", obj]]];
                        counter += 1;
                    }

                }
            }
            else {
                [requestUrl appendString:[NSString stringWithFormat:@"%@%@=%@", separator,
                                          [FotitionAPIClient escape:key], [NSString stringWithFormat:@"%@", [queryParams valueForKey:key]]]];
            }

            counter += 1;
        }
    }
    return requestUrl;
}

- (NSString*)descriptionForRequest:(NSURLRequest*)request {
    return [[request URL] absoluteString];
}


/**
 * Update header and query params based on authentication settings
 */
- (void) updateHeaderParams:(NSDictionary *__autoreleasing *)headers
                queryParams:(NSDictionary *__autoreleasing *)querys
           WithAuthSettings:(NSArray *)authSettings {
    
    if (!authSettings || [authSettings count] == 0) {
        return;
    }
    
    NSMutableDictionary *headersWithAuth = [NSMutableDictionary dictionaryWithDictionary:*headers];
    NSMutableDictionary *querysWithAuth = [NSMutableDictionary dictionaryWithDictionary:*querys];
    
    FTConfiguration *config = [FTConfiguration sharedConfig];
    for (NSString *auth in authSettings) {
        NSDictionary *authSetting = [[config authSettings] objectForKey:auth];
        
        if (authSetting) {
            if ([authSetting[@"in"] isEqualToString:@"header"]) {
                [headersWithAuth setObject:authSetting[@"value"] forKey:authSetting[@"key"]];
            }
            else if ([authSetting[@"in"] isEqualToString:@"query"]) {
                [querysWithAuth setObject:authSetting[@"value"] forKey:authSetting[@"key"]];
            }
        }
    }
    
    *headers = [NSDictionary dictionaryWithDictionary:headersWithAuth];
    *querys = [NSDictionary dictionaryWithDictionary:querysWithAuth];
}

#pragma mark - Perform Request Methods

-(NSNumber*)  dictionary: (NSString*) path
                  method: (NSString*) method
             queryParams: (NSDictionary*) queryParams
                    body: (id) body
            headerParams: (NSDictionary*) headerParams
            authSettings: (NSArray *) authSettings
      requestContentType: (NSString*) requestContentType
     responseContentType: (NSString*) responseContentType
         completionBlock: (void (^)(NSDictionary *, NSDictionary*, NSError *))completionBlock {
    
    
    // save existing header params
    NSDictionary *oldHeaderParams;
    
    if ([self.requestSerializer HTTPRequestHeaders]) {
        oldHeaderParams = [self.requestSerializer HTTPRequestHeaders];
    }
    
    // setting request serializer
    if ([requestContentType isEqualToString:@"application/json"]) {
        self.requestSerializer = [AFJSONRequestSerializer serializer];
    }
    else if ([requestContentType isEqualToString:@"application/x-www-form-urlencoded"]) {
        self.requestSerializer = [AFHTTPRequestSerializer serializer];
    }
    else if ([requestContentType isEqualToString:@"multipart/form-data"]) {
        self.requestSerializer = [AFHTTPRequestSerializer serializer];
    }
    else {
        NSAssert(false, @"unsupport request type %@", requestContentType);
    }
    
    //re-assign old params
    if(oldHeaderParams){
        for (NSString *key in oldHeaderParams) {
            [self setValue:oldHeaderParams[key] forKey:key];
        }
    }

    // setting response serializer
    if ([responseContentType isEqualToString:@"application/json"]) {
        self.responseSerializer = [AFJSONResponseSerializer serializer];
    }
    else {
        self.responseSerializer = [AFHTTPResponseSerializer serializer];
    }
    
    // auth setting
    [self updateHeaderParams:&headerParams queryParams:&queryParams WithAuthSettings:authSettings];

    NSMutableURLRequest * request = nil;
    if (body != nil && [body isKindOfClass:[NSArray class]]){
        FTFile * file;
        NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
        for(id obj in body) {
            if([obj isKindOfClass:[FTFile class]]) {
                file = (FTFile*) obj;
                requestContentType = @"multipart/form-data";
            }
            else if([obj isKindOfClass:[NSDictionary class]]) {
                for(NSString * key in obj) {
                    params[key] = obj[key];
                }
            }
        }
        NSString * urlString = [[NSURL URLWithString:path relativeToURL:self.baseURL] absoluteString];

        // request with multipart form
        if([requestContentType isEqualToString:@"multipart/form-data"]) {
            request = [self.requestSerializer multipartFormRequestWithMethod: @"POST"
                                                                   URLString: urlString
                                                                  parameters: nil
                                                   constructingBodyWithBlock: ^(id<AFMultipartFormData> formData) {

                                                       for(NSString * key in params) {
                                                           NSData* data = [params[key] dataUsingEncoding:NSUTF8StringEncoding];
                                                           [formData appendPartWithFormData: data name: key];
                                                       }

                                                       if (file) {
                                                           [formData appendPartWithFileData: [file data]
                                                                                       name: [file paramName]
                                                                                   fileName: [file name]
                                                                                   mimeType: [file mimeType]];
                                                       }

                                                   }
                                                                       error:nil];
        }
        // request with form parameters or json
        else {
            NSString* pathWithQueryParams = [self pathWithQueryParamsToString:path queryParams:queryParams];
            NSString* urlString = [[NSURL URLWithString:pathWithQueryParams relativeToURL:self.baseURL] absoluteString];

            request = [self.requestSerializer requestWithMethod:method
                                                      URLString:urlString
                                                     parameters:params
                                                          error:nil];
        }
    }
    else {
        NSString * pathWithQueryParams = [self pathWithQueryParamsToString:path queryParams:queryParams];
        NSString * urlString = [[NSURL URLWithString:pathWithQueryParams relativeToURL:self.baseURL] absoluteString];

        request = [self.requestSerializer requestWithMethod:method
                                                  URLString:urlString
                                                 parameters:body
                                                      error:nil];
    }
    BOOL hasHeaderParams = false;
    if(headerParams != nil && [headerParams count] > 0)
        hasHeaderParams = true;
    if(offlineState) {
        NSLog(@"%@ cache forced", path);
        [request setCachePolicy:NSURLRequestReturnCacheDataDontLoad];
    }
    else if(!hasHeaderParams && [method isEqualToString:@"GET"] && cacheEnabled) {
        NSLog(@"%@ cache enabled", path);
        [request setCachePolicy:NSURLRequestUseProtocolCachePolicy];
    }
    else {
        NSLog(@"%@ cache disabled", path);
        [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    }

    if(body != nil) {
        if([body isKindOfClass:[NSDictionary class]] || [body isKindOfClass:[NSArray class]]){
            [self setHeaderValue:requestContentType forKey:@"Content-Type"];
        }
        else if ([body isKindOfClass:[FTFile class]]) {}
        else {
            NSAssert(false, @"unsupported post type!");
        }
    }
    if(headerParams != nil){
        for(NSString * key in [headerParams keyEnumerator]){
            [request setValue:[headerParams valueForKey:key] forHTTPHeaderField:key];
        }
    }
    [self setHeaderValue:responseContentType forKey:@"Accept"];

    // Always disable cookies!
    [request setHTTPShouldHandleCookies:NO];


    if (self.logRequests) {
        [self logRequest:request];
    }

    NSNumber* requestId = [FotitionAPIClient queueRequest];
    AFHTTPRequestOperation *op =
    [self HTTPRequestOperationWithRequest:request
     success:^(AFHTTPRequestOperation *operation, id JSON) {
         if([self executeRequestWithId:requestId]) {
             if(self.logServerResponses)
                 [self logResponse:JSON forRequest:request error:nil];
             completionBlock([[operation response] allHeaderFields], JSON, nil);
         }
     } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
         if([self executeRequestWithId:requestId]) {
             NSMutableDictionary *userInfo = [error.userInfo mutableCopy];
             if(operation.responseObject) {
                 // Add in the (parsed) response body.
                 userInfo[FotitionResponseObjectErrorKey] = operation.responseObject;
             }
             NSError *augmentedError = [error initWithDomain:error.domain code:error.code userInfo:userInfo];

             if(self.logServerResponses)
                 [self logResponse:nil forRequest:request error:augmentedError];
             completionBlock([[operation response] allHeaderFields], nil, augmentedError);
         }
     }
     ];

    [self.operationQueue addOperation:op];
    return requestId;
}

-(NSNumber*)  stringWithCompletionBlock: (NSString*) path
                                 method: (NSString*) method
                            queryParams: (NSDictionary*) queryParams
                                   body: (id) body
                           headerParams: (NSDictionary*) headerParams
                           authSettings: (NSArray *) authSettings
                     requestContentType: (NSString*) requestContentType
                    responseContentType: (NSString*) responseContentType
                        completionBlock: (void (^)(NSDictionary *, NSString*, NSError *))completionBlock {
    
    // save existing header params
    NSDictionary *oldHeaderParams;
    
    if ([self.requestSerializer HTTPRequestHeaders]) {
        oldHeaderParams = [self.requestSerializer HTTPRequestHeaders];
    }
    
    
    // setting request serializer
    if ([requestContentType isEqualToString:@"application/json"]) {
        self.requestSerializer = [AFJSONRequestSerializer serializer];
    }
    else if ([requestContentType isEqualToString:@"application/x-www-form-urlencoded"]) {
        self.requestSerializer = [AFHTTPRequestSerializer serializer];
    }
    else if ([requestContentType isEqualToString:@"multipart/form-data"]) {
        self.requestSerializer = [AFHTTPRequestSerializer serializer];
    }
    else {
        NSAssert(false, @"unsupport request type %@", requestContentType);
    }
    
    //re-assign old header params
    if(oldHeaderParams){
        for (NSString *key in oldHeaderParams) {
            [self setValue:oldHeaderParams[key] forKey:key];
        }
    }

    // setting response serializer
    if ([responseContentType isEqualToString:@"application/json"]) {
        self.responseSerializer = [AFJSONResponseSerializer serializer];
    }
    else {
        self.responseSerializer = [AFHTTPResponseSerializer serializer];
    }
    
    // auth setting
    [self updateHeaderParams:&headerParams queryParams:&queryParams WithAuthSettings:authSettings];

    NSMutableURLRequest * request = nil;
    if (body != nil && [body isKindOfClass:[NSArray class]]){
        FTFile * file;
        NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
        for(id obj in body) {
            if([obj isKindOfClass:[FTFile class]]) {
                file = (FTFile*) obj;
                requestContentType = @"multipart/form-data";
            }
            else if([obj isKindOfClass:[NSDictionary class]]) {
                for(NSString * key in obj) {
                    params[key] = obj[key];
                }
            }
        }
        NSString * urlString = [[NSURL URLWithString:path relativeToURL:self.baseURL] absoluteString];

        // request with multipart form
        if([requestContentType isEqualToString:@"multipart/form-data"]) {
            request = [self.requestSerializer multipartFormRequestWithMethod: @"POST"
                                                                   URLString: urlString
                                                                  parameters: nil
                                                   constructingBodyWithBlock: ^(id<AFMultipartFormData> formData) {

                                                       for(NSString * key in params) {
                                                           NSData* data = [params[key] dataUsingEncoding:NSUTF8StringEncoding];
                                                           [formData appendPartWithFormData: data name: key];
                                                       }

                                                       if (file) {
                                                           [formData appendPartWithFileData: [file data]
                                                                                       name: [file paramName]
                                                                                   fileName: [file name]
                                                                                   mimeType: [file mimeType]];
                                                       }

                                                   }
                                                                       error:nil];
        }
        // request with form parameters or json
        else {
            NSString* pathWithQueryParams = [self pathWithQueryParamsToString:path queryParams:queryParams];
            NSString* urlString = [[NSURL URLWithString:pathWithQueryParams relativeToURL:self.baseURL] absoluteString];

            request = [self.requestSerializer requestWithMethod:method
                                                      URLString:urlString
                                                     parameters:params
                                                          error:nil];
        }

    }
    else {
        NSString * pathWithQueryParams = [self pathWithQueryParamsToString:path queryParams:queryParams];
        NSString * urlString = [[NSURL URLWithString:pathWithQueryParams relativeToURL:self.baseURL] absoluteString];

        request = [self.requestSerializer requestWithMethod: method
                                                  URLString: urlString
                                                 parameters: body
                                                      error: nil];
    }
    BOOL hasHeaderParams = false;
    if(headerParams != nil && [headerParams count] > 0)
        hasHeaderParams = true;
    if(offlineState) {
        NSLog(@"%@ cache forced", path);
        [request setCachePolicy:NSURLRequestReturnCacheDataDontLoad];
    }
    else if(!hasHeaderParams && [method isEqualToString:@"GET"] && cacheEnabled) {
        NSLog(@"%@ cache enabled", path);
        [request setCachePolicy:NSURLRequestUseProtocolCachePolicy];
    }
    else {
        NSLog(@"%@ cache disabled", path);
        [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    }


    if(body != nil) {
        if([body isKindOfClass:[NSDictionary class]] || [body isKindOfClass:[NSArray class]]){
            [self.requestSerializer setValue:requestContentType forHTTPHeaderField:@"Content-Type"];
        }
        else if ([body isKindOfClass:[FTFile class]]){}
        else {
            NSAssert(false, @"unsupported post type!");
        }
    }
    if(headerParams != nil){
        for(NSString * key in [headerParams keyEnumerator]){
            [request setValue:[headerParams valueForKey:key] forHTTPHeaderField:key];
        }
    }
    [self.requestSerializer setValue:responseContentType forHTTPHeaderField:@"Accept"];


    // Always disable cookies!
    [request setHTTPShouldHandleCookies:NO];

    NSNumber* requestId = [FotitionAPIClient queueRequest];
    AFHTTPRequestOperation *op = [self HTTPRequestOperationWithRequest:request
     success:^(AFHTTPRequestOperation *operation, id responseObject) {
         NSString *response = [operation responseString];
         if([self executeRequestWithId:requestId]) {
             if(self.logServerResponses)
                 [self logResponse:responseObject forRequest:request error:nil];
             completionBlock([[operation response] allHeaderFields], response, nil);
         }
     } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
         if([self executeRequestWithId:requestId]) {
             NSMutableDictionary *userInfo = [error.userInfo mutableCopy];
             if(operation.responseObject) {
                 // Add in the (parsed) response body.
                 userInfo[FotitionResponseObjectErrorKey] = operation.responseObject;
             }
             NSError *augmentedError = [error initWithDomain:error.domain code:error.code userInfo:userInfo];

             if(self.logServerResponses)
                 [self logResponse:nil forRequest:request error:augmentedError];
             completionBlock([[operation response] allHeaderFields], nil, augmentedError);
         }
     }];

    [self.operationQueue addOperation:op];
    return requestId;
}

@end








