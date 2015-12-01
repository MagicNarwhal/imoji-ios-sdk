//
// Created by Nima on 7/29/15.
// Copyright (c) 2015 Imoji. All rights reserved.
//

#import <Bolts/BFTaskCompletionSource.h>
#import <Bolts/BFTask.h>
#import <Bolts/BFExecutor.h>
#import "IMImojiSession+Private.h"
#import "IMImojiSessionCredentials.h"
#import "ImojiSDK.h"
#import "BFTask+Utils.h"
#import "RequestUtils.h"
#import "ImojiSDKConstants.h"
#import "IMMutableImojiSessionStoragePolicy.h"
#import "IMMutableImojiObject.h"
#import "NSDictionary+Utils.h"
#import "UIImage+WebP.h"
#import "UIImage+Extensions.h"
#import "NSString+Utils.h"

NSString *const IMImojiSessionFileAccessTokenKey = @"at";
NSString *const IMImojiSessionFileRefreshTokenKey = @"rt";
NSString *const IMImojiSessionFileExpirationKey = @"ex";
NSString *const IMImojiSessionFileUserSynchronizedKey = @"sy";
NSString *const IMImojiSessionFileClientIdKey = @"ci";
NSUInteger const IMImojiSessionNumberOfRetriesForImojiDownload = 3;

@implementation IMImojiSession (Private)

#pragma mark Authentication Serialization/Deserialization

- (void)readAuthenticationFromDictionary:(NSDictionary *)authenticationInfo {
    [IMImojiSession credentials].accessToken = authenticationInfo[IMImojiSessionFileAccessTokenKey];
    [IMImojiSession credentials].refreshToken = authenticationInfo[IMImojiSessionFileRefreshTokenKey];
    [IMImojiSession credentials].expirationDate = [NSDate dateWithTimeIntervalSince1970:((NSNumber *) authenticationInfo[IMImojiSessionFileExpirationKey]).doubleValue];
    [IMImojiSession credentials].accountSynchronized = authenticationInfo[IMImojiSessionFileUserSynchronizedKey] && ((NSNumber *) authenticationInfo[IMImojiSessionFileUserSynchronizedKey]).boolValue;
    [IMImojiSession credentials].clientId = authenticationInfo[IMImojiSessionFileClientIdKey];

    [self updateImojiState:[IMImojiSession credentials].accountSynchronized ? IMImojiSessionStateConnectedSynchronized : IMImojiSessionStateConnected];
}

- (void)readAuthenticationCredentials {
    NSString *sessionFile = self.sessionFilePath;
    if ([[NSFileManager defaultManager] fileExistsAtPath:sessionFile]) {
        NSError *error;
        NSData *data = [NSData dataWithContentsOfFile:sessionFile options:0 error:&error];

        if (!error) {
            NSDictionary *jsonInfo = [NSJSONSerialization JSONObjectWithData:data
                                                                     options:NSJSONReadingAllowFragments
                                                                       error:&error];

            if (!error) {
                [self readAuthenticationFromDictionary:jsonInfo];
            }
        }

    }
}

- (BFTask *)writeAuthenticationCredentials {
    NSMutableDictionary *authenticationInfo = [NSMutableDictionary dictionaryWithCapacity:4];

    authenticationInfo[IMImojiSessionFileAccessTokenKey] = [IMImojiSession credentials].accessToken;
    authenticationInfo[IMImojiSessionFileRefreshTokenKey] = [IMImojiSession credentials].refreshToken;
    authenticationInfo[IMImojiSessionFileExpirationKey] = @([IMImojiSession credentials].expirationDate.timeIntervalSince1970);
    authenticationInfo[IMImojiSessionFileUserSynchronizedKey] = @([IMImojiSession credentials].accountSynchronized);
    authenticationInfo[IMImojiSessionFileClientIdKey] = [IMImojiSession credentials].clientId;

    return [BFTask im_serialBackgroundTaskWithBlock:^id(BFTask *task) {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:authenticationInfo
                                                           options:0
                                                             error:&error];

        if (error) {
            return nil;
        }

        NSString *sessionFile = self.sessionFilePath;
        [jsonData writeToFile:sessionFile options:NSDataWritingAtomic error:&error];

        if (error) {
            return nil;
        }

        return nil;
    }];
}

#pragma mark Utilities

- (NSOperation *)cancellationTokenOperation {
    return [NSBlockOperation blockOperationWithBlock:^{
    }];
}

- (BFTask *)runPostTaskWithPath:(NSString *)path
                        headers:(NSDictionary *)headers
                  andParameters:(NSDictionary *)parameters {
    return [self runImojiURLRequest:[NSMutableURLRequest POSTRequestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", ImojiSDKServerURL, path]]
                                                                 parameters:parameters]
                            headers:headers];
}

- (BFTask *)runValidatedGetTaskWithPath:(NSString *)path
                          andParameters:(NSDictionary *)parameters {
    return [self runValidatedImojiURLRequest:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", ImojiSDKServerURL, path]]
                                  parameters:parameters
                                      method:@"GET"
                                     headers:@{}];
}

- (BFTask *)runValidatedPutTaskWithPath:(NSString *)path
                          andParameters:(NSDictionary *)parameters {
    return [self runValidatedImojiURLRequest:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", ImojiSDKServerURL, path]]
                                  parameters:parameters
                                      method:@"PUT"
                                     headers:@{}];
}

- (BFTask *)runValidatedPostTaskWithPath:(NSString *)path
                           andParameters:(NSDictionary *)parameters {
    return [self runValidatedImojiURLRequest:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", ImojiSDKServerURL, path]]
                                  parameters:parameters
                                      method:@"POST"
                                     headers:@{}];
}

- (BFTask *)runValidatedDeleteTaskWithPath:(NSString *)path
                             andParameters:(NSDictionary *)parameters {
    return [self runValidatedImojiURLRequest:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", ImojiSDKServerURL, path]]
                                  parameters:parameters
                                      method:@"DELETE"
                                     headers:@{}];
}

- (NSDictionary *)getRequestHeaders:(NSDictionary *)additionalHeaders {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];

    NSString *locale = [[NSLocale currentLocale] localeIdentifier];
    NSRange startRange = [locale rangeOfString:@"_"];
    NSString *language = [locale stringByReplacingCharactersInRange:NSMakeRange(0, startRange.length + 1)
                                                         withString:[NSLocale preferredLanguages][0]];

    headers[@"Imoji-SDK-Version"] = [ImojiSDK sharedInstance].sdkVersion;

    if (language != nil) {
        headers[@"User-Locale"] = language;
    }

    if (additionalHeaders) {
        [headers addEntriesFromDictionary:additionalHeaders];
    }

    return headers;
}

- (BFTask *)runValidatedImojiURLRequest:(NSURL *)url
                             parameters:(NSDictionary *)parameters
                                 method:(NSString *)method
                                headers:(NSDictionary *)headers {
    BFTaskCompletionSource *taskCompletionSource = [BFTaskCompletionSource taskCompletionSource];

    [[self validateSession] continueWithBlock:^id(BFTask *task) {
        if (task.error) {
            taskCompletionSource.error = task.error;
        } else {
            NSMutableURLRequest *request;
            NSMutableDictionary *parametersWithAuth = [NSMutableDictionary dictionaryWithDictionary:parameters];
            parametersWithAuth[@"access_token"] = task.result;

            if ([@"GET" isEqualToString:method]) {
                request = [NSMutableURLRequest GETRequestWithURL:url parameters:parametersWithAuth];
            } else if ([@"DELETE" isEqualToString:method]) {
                request = [NSMutableURLRequest DELETERequestWithURL:url parameters:parametersWithAuth];
            } else if ([@"POST" isEqualToString:method]) {
                request = [NSMutableURLRequest POSTRequestWithURL:url parameters:parametersWithAuth];
            } else if ([@"PUT" isEqualToString:method]) {
                request = [NSMutableURLRequest PUTRequestWithURL:url parameters:parametersWithAuth];
            }

            [[self runImojiURLRequest:request headers:headers] continueWithBlock:^id(BFTask *imojiRequest) {
                if (imojiRequest.error) {
                    if (imojiRequest.error.userInfo && [@"invalid_token" isEqualToString:imojiRequest.error.userInfo[@"status"]]) {
                        [self renewCredentials:^(BOOL successful, NSError *error) {
                            [[self runValidatedImojiURLRequest:url
                                                    parameters:parameters
                                                        method:method
                                                       headers:headers] continueWithBlock:^id(BFTask *validationTask) {
                                if (validationTask.error) {
                                    taskCompletionSource.error = validationTask.error;
                                } else {
                                    taskCompletionSource.result = validationTask.result;
                                }

                                return nil;
                            }];
                        }];
                    } else {
                        taskCompletionSource.error = imojiRequest.error;
                    }
                } else {
                    taskCompletionSource.result = imojiRequest.result;
                }

                return nil;
            }];
        }

        return nil;
    }];

    return taskCompletionSource.task;
}

- (void)renewCredentials:(IMImojiSessionAsyncResponseCallback)callback {
    [IMImojiSession credentials].accessToken = nil;
    [IMImojiSession credentials].refreshToken = nil;
    [IMImojiSession credentials].expirationDate = nil;
    [IMImojiSession credentials].accountSynchronized = NO;

    [[self validateSession] continueWithBlock:^id(BFTask *task) {
        if (callback) {
            if (task.error) {
                callback(NO, task.error);
            } else {
                callback(YES, nil);
            }
        }

        return nil;
    }];
}


- (BFTask *)runImojiURLRequest:(NSMutableURLRequest *)request
                       headers:(NSDictionary *)headers {

    [request setAllHTTPHeaderFields:[self getRequestHeaders:headers]];

    BFTaskCompletionSource *taskCompletionSource = [BFTaskCompletionSource taskCompletionSource];
    [[[IMImojiSession downloadURLSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            taskCompletionSource.error = error;
        } else {
            NSError *jsonError;
            NSDictionary *jsonInfo;

            if (data.length > 0) {
                jsonInfo = [NSJSONSerialization JSONObjectWithData:data
                                                           options:NSJSONReadingAllowFragments
                                                             error:&jsonError];
            } else {
                jsonInfo = nil;
            }

            if (jsonError) {
                taskCompletionSource.error = jsonError;
            } else {
                if ([response isKindOfClass:[NSHTTPURLResponse class]] &&
                        ((NSHTTPURLResponse *) response).statusCode != 200) {
                    taskCompletionSource.error = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                                     code:IMImojiSessionErrorCodeServerError
                                                                 userInfo:jsonInfo];
                } else {
                    taskCompletionSource.result = jsonInfo;
                }
            }
        }
    }] resume];

    return taskCompletionSource.task;
}

- (BFTask *)runExternalURLRequest:(NSMutableURLRequest *)request
                          headers:(NSDictionary *)headers {

    BFTaskCompletionSource *taskCompletionSource = [BFTaskCompletionSource taskCompletionSource];

    [[[IMImojiSession downloadURLSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            taskCompletionSource.error = error;
        } else {
            taskCompletionSource.result = data;
        }
    }] resume];

    return taskCompletionSource.task;
}

- (BFTask *)validateSession {
    BFTaskCompletionSource *taskCompletionSource = [BFTaskCompletionSource taskCompletionSource];

    [BFTask im_serialBackgroundTaskWithBlock:^id(BFTask *task) {
        if (![ImojiSDK sharedInstance].clientId) {
            NSError *apiError = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                    code:IMImojiSessionErrorCodeInvalidCredentials
                                                userInfo:@{
                                                        NSLocalizedDescriptionKey : @"clientId not specified. Call [[ImojiSDK sharedInstance] setClientId:apiToken:] before making this call."
                                                }];
            taskCompletionSource.error = apiError;

        } else if (![ImojiSDK sharedInstance].apiToken) {
            NSError *apiError = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                    code:IMImojiSessionErrorCodeInvalidCredentials
                                                userInfo:@{
                                                        NSLocalizedDescriptionKey : @"apiToken not specified. Call [[ImojiSDK sharedInstance] setClientId:apiToken:] before making this call."
                                                }];
            taskCompletionSource.error = apiError;
        }

        if ([IMImojiSession credentials].accessToken) {
            // refresh
            if ([IMImojiSession credentials].expirationDate && [[IMImojiSession credentials].expirationDate compare:[NSDate date]] != NSOrderedDescending) {
                [[self runPostTaskWithPath:@"/oauth/token"
                                   headers:self.getOAuthBearerHeaders
                             andParameters:@{@"grant_type" : @"refresh_token", @"refresh_token" : [IMImojiSession credentials].refreshToken}]
                        continueWithBlock:^id(BFTask *postTask) {

                            if ([postTask.result isKindOfClass:[NSDictionary class]]) {
                                NSDictionary *results = postTask.result;

                                [IMImojiSession credentials].clientId = [ImojiSDK sharedInstance].clientId.UUIDString;
                                [IMImojiSession credentials].accessToken = results[@"access_token"];
                                [IMImojiSession credentials].refreshToken = results[@"refresh_token"];
                                [IMImojiSession credentials].expirationDate = [NSDate dateWithTimeIntervalSinceNow:((NSNumber *) results[@"expires_in"]).integerValue];

                                [self writeAuthenticationCredentials];
                                [self updateImojiState:[IMImojiSession credentials].accountSynchronized ? IMImojiSessionStateConnectedSynchronized : IMImojiSessionStateConnected];
                                taskCompletionSource.result = [IMImojiSession credentials].accessToken;

                            } else {
                                // get a new access token if the refresh token is invalid
                                [self getNewAccessTokenWithCompletionSource:taskCompletionSource];
                            }

                            return nil;
                        }];
            } else {
                // if the client id's changed, generate a new access token
                if ([IMImojiSession credentials].clientId && ![[IMImojiSession credentials].clientId isEqualToString:[ImojiSDK sharedInstance].clientId.UUIDString]) {
                    [self getNewAccessTokenWithCompletionSource:taskCompletionSource];
                } else {
                    taskCompletionSource.result = [IMImojiSession credentials].accessToken;
                    [self updateImojiState:[IMImojiSession credentials].accountSynchronized ? IMImojiSessionStateConnectedSynchronized : IMImojiSessionStateConnected];
                }
            }
        } else {
            [self getNewAccessTokenWithCompletionSource:taskCompletionSource];
        }

        return nil;
    }];

    return taskCompletionSource.task;
}

- (void)getNewAccessTokenWithCompletionSource:(BFTaskCompletionSource *)taskCompletionSource {
    [[self runPostTaskWithPath:@"/oauth/token"
                       headers:self.getOAuthBearerHeaders
                 andParameters:@{@"grant_type" : @"client_credentials"}]
            continueWithBlock:^id(BFTask *postTask) {

                if ([postTask.result isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *results = postTask.result;

                    [IMImojiSession credentials].accessToken = results[@"access_token"];
                    [IMImojiSession credentials].refreshToken = results[@"refresh_token"];
                    [IMImojiSession credentials].clientId = [ImojiSDK sharedInstance].clientId.UUIDString;
                    [IMImojiSession credentials].expirationDate = [NSDate dateWithTimeIntervalSinceNow:((NSNumber *) results[@"expires_in"]).integerValue];
                    [IMImojiSession credentials].accountSynchronized = NO;

                    [self writeAuthenticationCredentials];
                    [self updateImojiState:IMImojiSessionStateConnected];

                    taskCompletionSource.result = [IMImojiSession credentials].accessToken;
                } else {
                    taskCompletionSource.error = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                                     code:IMImojiSessionErrorCodeServerError
                                                                 userInfo:@{
                                                                         NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Server error: %@", postTask.error]
                                                                 }];

                    [self updateImojiState:IMImojiSessionStateNotConnected];
                }

                return nil;
            }];
}


- (NSDictionary *)getOAuthBearerHeaders {
    NSData *stringCredentials = [[NSString stringWithFormat:@"%@:%@", [[ImojiSDK sharedInstance].clientId.UUIDString lowercaseString], [ImojiSDK sharedInstance].apiToken] dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64Credentials = [stringCredentials base64EncodedStringWithOptions:0];

    return @{
            @"Authorization" : [NSString stringWithFormat:@"Basic %@", base64Credentials]
    };
}

- (void)updateImojiState:(IMImojiSessionState)newState {
    IMImojiSessionState oldState = self.sessionState;

    if (newState != oldState) {
        _sessionState = newState;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.delegate && [self.delegate respondsToSelector:@selector(imojiSession:stateChanged:fromState:)]) {
                [self.delegate imojiSession:self stateChanged:newState fromState:oldState];
            }
        });
    }
}

- (BFTask *)createLocalImojiWithRawImage:(UIImage *)rawImage
                           borderedImage:(UIImage *)borderedImage
                                    tags:(NSArray *)tags {
    IMMutableImojiObject *imojiObject = [IMMutableImojiObject imojiWithIdentifier:[NSString im_stringWithRandomUUID]
                                                                             tags:tags
                                                                             urls:@{}];

    NSDictionary *renderingOptions = @{
            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeThumbnail
                                                     borderStyle:IMImojiObjectBorderStyleNone
                                                     imageFormat:IMImojiObjectImageFormatWebP] : [rawImage im_resizedImageToFitInSize:CGSizeMake(150.f, 150.f) scaleIfSmaller:NO],

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeFullResolution
                                                     borderStyle:IMImojiObjectBorderStyleNone
                                                     imageFormat:IMImojiObjectImageFormatWebP] : rawImage,

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeThumbnail
                                                     borderStyle:IMImojiObjectBorderStyleSticker
                                                     imageFormat:IMImojiObjectImageFormatWebP] : [borderedImage im_resizedImageToFitInSize:CGSizeMake(150.f, 150.f) scaleIfSmaller:NO],

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeFullResolution
                                                     borderStyle:IMImojiObjectBorderStyleSticker
                                                     imageFormat:IMImojiObjectImageFormatWebP] : borderedImage
    };

    NSMutableDictionary *urls = [NSMutableDictionary new];
    NSMutableArray *tasks = [NSMutableArray new];
    for (IMImojiObjectRenderingOptions *renderingOption in renderingOptions.allKeys) {
        urls[renderingOption] = [(IMMutableImojiSessionStoragePolicy *) self.storagePolicy filePathFromImoji:imojiObject
                                                                                            renderingOptions:renderingOption];

        [tasks addObject:[(IMMutableImojiSessionStoragePolicy *) self.storagePolicy writeImoji:imojiObject
                                                                              renderingOptions:renderingOption
                                                                                 imageContents:UIImagePNGRepresentation(renderingOptions[renderingOption])
                                                                                   synchronous:NO]];
    }

    return [[BFTask taskForCompletionOfAllTasks:tasks] continueWithBlock:^id(BFTask *task) {
        return [IMMutableImojiObject imojiWithIdentifier:imojiObject.identifier tags:imojiObject.tags urls:urls];
    }];
}

- (void)removeLocalImoj:(IMImojiObject *)imoji {
    NSArray *renderingOptions = @[
            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeThumbnail
                                                     borderStyle:IMImojiObjectBorderStyleNone
                                                     imageFormat:IMImojiObjectImageFormatWebP],

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeFullResolution
                                                     borderStyle:IMImojiObjectBorderStyleNone
                                                     imageFormat:IMImojiObjectImageFormatWebP],

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeThumbnail
                                                     borderStyle:IMImojiObjectBorderStyleSticker
                                                     imageFormat:IMImojiObjectImageFormatWebP],

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeFullResolution
                                                     borderStyle:IMImojiObjectBorderStyleSticker
                                                     imageFormat:IMImojiObjectImageFormatWebP]
    ];

    for (IMImojiObjectRenderingOptions *renderingOption in renderingOptions) {
        [(IMMutableImojiSessionStoragePolicy *) self.storagePolicy removeImoji:imoji
                                                              renderingOptions:renderingOption];
    }
}

- (NSString *)sessionFilePath {
    return [NSString stringWithFormat:@"%@/imoji.session", ((IMMutableImojiSessionStoragePolicy *) self.storagePolicy).persistentPath.path];
}


+ (IMImojiSessionCredentials *)credentials {
    static IMImojiSessionCredentials *authInfo = nil;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        authInfo = [IMImojiSessionCredentials new];
    });

    return authInfo;
}

+ (NSURLSession *)downloadURLSession {
    static NSURLSession *session = nil;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        sessionConfiguration.HTTPMaximumConnectionsPerHost = 10;
        sessionConfiguration.networkServiceType = NSURLNetworkServiceTypeDefault;
        sessionConfiguration.URLCache = nil;

        session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
    });

    return session;
}

+ (NSURLSession *)uploadInBackgroundURLSession {
    static NSURLSession *session = nil;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        sessionConfiguration.HTTPMaximumConnectionsPerHost = 3;
        sessionConfiguration.networkServiceType = NSURLNetworkServiceTypeBackground;
        sessionConfiguration.URLCache = nil;

        session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
    });

    return session;
}

- (BOOL)validateServerResponse:(NSDictionary *)results error:(NSError **)error {
    NSString *status = [results im_checkedStringForKey:@"status"];
    if (![@"SUCCESS" isEqualToString:status]) {
        if (error) {
            *error = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                         code:IMImojiSessionErrorCodeServerError
                                     userInfo:@{
                                             NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Imoji Server returned %@", status]
                                     }];
        }

        return NO;
    }

    return YES;
}

- (NSArray *)convertServerDataSetToImojiArray:(NSDictionary *)serverResponse {
    NSArray *results = serverResponse[@"results"];
    if (!results.count == 0) {
        NSMutableArray *imojiObjectsArray = [NSMutableArray arrayWithCapacity:results.count];
        for (NSDictionary *result in results) {
            [imojiObjectsArray addObject:[self readImojiObject:result]];
        }

        return imojiObjectsArray;
    }

    return @[];
}

- (void)handleImojiFetchResponse:(NSArray *)imojiObjects
                renderingOptions:(IMImojiObjectRenderingOptions *)renderingOptions
               cancellationToken:(NSOperation *)cancellationToken
          searchResponseCallback:(IMImojiSessionResultSetResponseCallback)searchResponseCallback
           imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    if (cancellationToken.isCancelled) {
        return;
    }

    if (searchResponseCallback) {
        searchResponseCallback(@(imojiObjects.count), nil);
    }

    for (IMMutableImojiObject *imoji in imojiObjects) {
        if (![(IMMutableImojiSessionStoragePolicy *) self.storagePolicy imojiExists:imoji renderingOptions:renderingOptions]) {
            [self downloadImojiImageAsync:imoji
                         renderingOptions:renderingOptions
                               imojiIndex:[imojiObjects indexOfObject:imoji]
                        cancellationToken:cancellationToken
                    imojiResponseCallback:imojiResponseCallback];
        } else {
            if (imojiResponseCallback && !cancellationToken.isCancelled) {
                imojiResponseCallback(imoji, [imojiObjects indexOfObject:imoji], nil);
            }
        }
    }
}

- (void)downloadImojiImageAsync:(IMMutableImojiObject *)imoji
               renderingOptions:(IMImojiObjectRenderingOptions *)renderingOptions
                     imojiIndex:(NSUInteger)imojiIndex
              cancellationToken:(NSOperation *)cancellationToken
          imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    [self downloadImojiImageAsync:imoji
                 renderingOptions:renderingOptions
                      retriesLeft:IMImojiSessionNumberOfRetriesForImojiDownload
                       imojiIndex:imojiIndex
                cancellationToken:cancellationToken
            imojiResponseCallback:imojiResponseCallback];
}

- (void)downloadImojiImageAsync:(IMMutableImojiObject *)imoji
               renderingOptions:(IMImojiObjectRenderingOptions *)renderingOptions
                    retriesLeft:(NSUInteger)retriesLeft
                     imojiIndex:(NSUInteger)imojiIndex
              cancellationToken:(NSOperation *)cancellationToken
          imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    NSURL *url = [imoji getUrlForRenderingOptions:renderingOptions];
    [BFTask im_concurrentBackgroundTaskWithBlock:^id(BFTask *task) {
        if (cancellationToken.isCancelled) {
            return [BFTask cancelledTask];
        }

        [[self runExternalURLRequest:[NSMutableURLRequest GETRequestWithURL:url
                                                                 parameters:@{}]
                             headers:@{}] continueWithBlock:^id(BFTask *urlTask) {

            if (urlTask.error) {
                if (!cancellationToken.isCancelled) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (retriesLeft > 0) {
                            [self downloadImojiImageAsync:imoji
                                         renderingOptions:renderingOptions
                                              retriesLeft:retriesLeft - 1
                                               imojiIndex:imojiIndex
                                        cancellationToken:cancellationToken
                                    imojiResponseCallback:imojiResponseCallback
                            ];
                        } else {
                            imojiResponseCallback(imoji, imojiIndex, [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                                                         code:IMImojiSessionErrorCodeServerError
                                                                                     userInfo:@{
                                                                                             NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Unable to download %@ error code: %@", url, @(urlTask.error.code)]
                                                                                     }]);
                        }
                    });
                }
            } else {
                UIImage *image;
                switch (renderingOptions.imageFormat) {
                    case IMImojiObjectImageFormatWebP:
                        image = [UIImage im_imageWithWebPData:urlTask.result];
                        break;

                    case IMImojiObjectImageFormatPNG:
                    default:
                        image = [UIImage imageWithData:urlTask.result];
                        break;

                }

                [[(IMMutableImojiSessionStoragePolicy *) self.storagePolicy writeImoji:imoji
                                                                      renderingOptions:renderingOptions
                                                                         imageContents:UIImagePNGRepresentation(image)
                                                                           synchronous:YES]
                        continueWithExecutor:[BFExecutor mainThreadExecutor]
                                   withBlock:^id(BFTask *writeTask) {
                                       if (!cancellationToken.isCancelled) {
                                           imojiResponseCallback(imoji, imojiIndex, nil);
                                       }

                                       return nil;
                                   }];
            }


            return nil;
        }];

        return nil;
    }];
}

- (BFTask *)uploadImageInBackgroundWithRetries:(UIImage *)image
                                     uploadUrl:(NSURL *)uploadUrl
                                    retryCount:(int)retryCount {
    BFTaskCompletionSource *taskCompletionSource = [BFTaskCompletionSource taskCompletionSource];

    [self uploadImageInBackgroundWithRetries:image uploadUrl:uploadUrl retryCount:retryCount taskCompletionSource:taskCompletionSource];

    return taskCompletionSource.task;
}

- (void)uploadImageInBackgroundWithRetries:(UIImage *)image
                                 uploadUrl:(NSURL *)uploadUrl
                                retryCount:(int)retryCount
                      taskCompletionSource:(BFTaskCompletionSource *)taskCompletionSource {
    [BFTask im_concurrentBackgroundTaskWithBlock:^id(BFTask *task) {
        NSMutableURLRequest *request = [NSMutableURLRequest new];

        request.timeoutInterval = 15.0;
        request.HTTPMethod = @"PUT";
        request.URL = uploadUrl;

        [request addValue:@"image/png" forHTTPHeaderField:@"Content-Type"];

        [[[IMImojiSession uploadInBackgroundURLSession] uploadTaskWithRequest:request
                                                                     fromData:UIImagePNGRepresentation(image)
                                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                                if (error) {
                                                                    if (retryCount == 0) {
                                                                        taskCompletionSource.error = error;
                                                                    } else {
                                                                        [self uploadImageInBackgroundWithRetries:image uploadUrl:uploadUrl retryCount:retryCount - 1 taskCompletionSource:taskCompletionSource];
                                                                    }
                                                                } else {
                                                                    taskCompletionSource.result = @YES;
                                                                }
                                                            }] resume];

        return nil;
    }];
}

- (IMMutableImojiObject *)readImojiObject:(NSDictionary *)result {
    if (result) {
        NSString *imojiId = [result im_checkedStringForKey:@"imojiId"] ? [result im_checkedStringForKey:@"imojiId"] : [result im_checkedStringForKey:@"id"];
        NSArray *tags = [result[@"tags"] isKindOfClass:[NSArray class]] ? result[@"tags"] : @[];

        NSDictionary *imagesDictionary = result[@"urls"];
        NSMutableDictionary *imageUrls = [NSMutableDictionary new];

        for (NSNumber *renderSize in @[@(IMImojiObjectRenderSizeThumbnail), @(IMImojiObjectRenderSizeFullResolution), @(IMImojiObjectRenderSize320), @(IMImojiObjectRenderSize512)]) {
            for (NSNumber *borderStyle in @[@(IMImojiObjectBorderStyleSticker), @(IMImojiObjectBorderStyleNone)]) {
                for (NSNumber *imageFormat in @[@(IMImojiObjectImageFormatWebP), @(IMImojiObjectImageFormatPNG)]) {
                    IMImojiObjectRenderingOptions *renderingOptions = [IMImojiObjectRenderingOptions optionsWithRenderSize:(IMImojiObjectRenderSize) renderSize.unsignedIntegerValue
                                                                                                               borderStyle:(IMImojiObjectBorderStyle) borderStyle.unsignedIntegerValue
                                                                                                               imageFormat:(IMImojiObjectImageFormat) imageFormat.unsignedIntegerValue];

                    id path;
                    switch (renderingOptions.imageFormat) {
                        case IMImojiObjectImageFormatPNG:
                            path = imagesDictionary[@"png"];
                            break;
                        case IMImojiObjectImageFormatWebP:
                            path = imagesDictionary[@"webp"];
                            break;
                    }

                    if (!path || ![path isKindOfClass:[NSDictionary class]]) {
                        imageUrls[renderingOptions] = [NSNull null];
                        continue;
                    }

                    switch (renderingOptions.borderStyle) {
                        case IMImojiObjectBorderStyleSticker:
                            break;

                        case IMImojiObjectBorderStyleNone:
                            path = path[@"raw"];
                            break;
                    }

                    if (!path || ![path isKindOfClass:[NSDictionary class]]) {
                        imageUrls[renderingOptions] = [NSNull null];
                        continue;
                    }

                    id url;
                    switch (renderingOptions.renderSize) {
                        case IMImojiObjectRenderSizeThumbnail:
                            url = path[@"thumb"];
                            break;

                        case IMImojiObjectRenderSizeFullResolution:
                            url = path[@"full"];
                            break;

                        case IMImojiObjectRenderSize320:
                            url = path[@"320"];
                            break;

                        case IMImojiObjectRenderSize512:
                            url = path[@"512"];
                            break;
                    }

                    if (!url || ![url isKindOfClass:[NSString class]]) {
                        imageUrls[renderingOptions] = [NSNull null];
                    } else {
                        imageUrls[renderingOptions] = [NSURL URLWithString:url];
                    }
                }
            }
        }

        return [IMMutableImojiObject imojiWithIdentifier:imojiId
                                                    tags:tags
                                                    urls:imageUrls];
    } else {
        return nil;
    }
}

@end
