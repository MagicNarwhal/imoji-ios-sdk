//
// Created by Nima on 7/29/15.
// Copyright (c) 2015 Imoji. All rights reserved.
//

#import <Bolts/Bolts.h>
#import <YYImage/YYImage.h>
#import "IMImojiSession+Private.h"
#import "IMImojiSessionCredentials.h"
#import "ImojiSDK.h"
#import "BFTask+Utils.h"
#import "RequestUtils.h"
#import "ImojiSDKConstants.h"
#import "IMMutableImojiObject.h"
#import "NSDictionary+Utils.h"
#import "UIImage+Extensions.h"
#import "NSString+Utils.h"
#import "IMMutableCategoryAttribution.h"
#import "IMMutableArtist.h"
#import "IMMutableCategoryObject.h"

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

    [self updateImojiState:IMImojiSessionStateConnected];
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

    [[self->_urlSession dataTaskWithRequest:request
                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
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

    [[self->_urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
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
                                [self updateImojiState:IMImojiSessionStateConnected];
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
                    [self updateImojiState:IMImojiSessionStateConnected];
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
    if (!rawImage) {
        return [BFTask taskWithError:[NSError errorWithDomain:IMImojiSessionErrorDomain
                                                         code:IMImojiSessionErrorCodeInvalidImage
                                                     userInfo:@{
                                                             NSLocalizedDescriptionKey : @"parameter rawImage is nil"
                                                     }]];
    }

    if (!borderedImage) {
        return [BFTask taskWithError:[NSError errorWithDomain:IMImojiSessionErrorDomain
                                                         code:IMImojiSessionErrorCodeInvalidImage
                                                     userInfo:@{
                                                             NSLocalizedDescriptionKey : @"parameter borderedImage is nil"
                                                     }]];
    }

    IMMutableImojiObject *imojiObject = [IMMutableImojiObject imojiWithIdentifier:[NSString im_stringWithRandomUUID]
                                                                             tags:tags
                                                                             urls:@{}];

    UIImage *resizedRawImage = [rawImage im_resizedImageToFitInSize:CGSizeMake(150.f, 150.f) scaleIfSmaller:NO];
    if (!resizedRawImage) {
        return [BFTask taskWithError:[NSError errorWithDomain:IMImojiSessionErrorDomain
                                                         code:IMImojiSessionErrorCodeInvalidImage
                                                     userInfo:@{
                                                             NSLocalizedDescriptionKey : @"Unable to resize rawImage"
                                                     }]];
    }


    UIImage *resizedBorderImage = [borderedImage im_resizedImageToFitInSize:CGSizeMake(150.f, 150.f) scaleIfSmaller:NO];
    if (!resizedBorderImage) {
        return [BFTask taskWithError:[NSError errorWithDomain:IMImojiSessionErrorDomain
                                                         code:IMImojiSessionErrorCodeInvalidImage
                                                     userInfo:@{
                                                             NSLocalizedDescriptionKey : @"Unable to resize bordered image"
                                                     }]];
    }

    NSDictionary *renderingOptions = @{
            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeThumbnail
                                                     borderStyle:IMImojiObjectBorderStyleNone
                                                     imageFormat:IMImojiObjectImageFormatPNG] : resizedRawImage,

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeFullResolution
                                                     borderStyle:IMImojiObjectBorderStyleNone
                                                     imageFormat:IMImojiObjectImageFormatPNG] : rawImage,

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeThumbnail
                                                     borderStyle:IMImojiObjectBorderStyleSticker
                                                     imageFormat:IMImojiObjectImageFormatPNG] : resizedBorderImage,

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeFullResolution
                                                     borderStyle:IMImojiObjectBorderStyleSticker
                                                     imageFormat:IMImojiObjectImageFormatPNG] : borderedImage
    };

    NSMutableDictionary *urls = [NSMutableDictionary new];
    NSMutableArray *tasks = [NSMutableArray new];
    for (IMImojiObjectRenderingOptions *renderingOption in renderingOptions.allKeys) {
        urls[renderingOption] = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", [self filePathFromImoji:imojiObject
                                                                                                     renderingOptions:renderingOption]]];

        [tasks addObject:[self writeImoji:imojiObject
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
                                                     imageFormat:IMImojiObjectImageFormatPNG],

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeFullResolution
                                                     borderStyle:IMImojiObjectBorderStyleNone
                                                     imageFormat:IMImojiObjectImageFormatPNG],

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeThumbnail
                                                     borderStyle:IMImojiObjectBorderStyleSticker
                                                     imageFormat:IMImojiObjectImageFormatPNG],

            [IMImojiObjectRenderingOptions optionsWithRenderSize:IMImojiObjectRenderSizeFullResolution
                                                     borderStyle:IMImojiObjectBorderStyleSticker
                                                     imageFormat:IMImojiObjectImageFormatPNG]
    ];

    for (IMImojiObjectRenderingOptions *renderingOption in renderingOptions) {
        [self removeImoji:imoji renderingOptions:renderingOption];
    }
}

- (NSString *)sessionFilePath {
    return [NSString stringWithFormat:@"%@/imoji.session", self.storagePolicy.persistentPath.path];
}


+ (IMImojiSessionCredentials *)credentials {
    static IMImojiSessionCredentials *authInfo = nil;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        authInfo = [IMImojiSessionCredentials new];
    });

    return authInfo;
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
    if (results.count != 0) {
        NSMutableArray *imojiObjectsArray = [NSMutableArray arrayWithCapacity:results.count];
        for (NSDictionary *result in results) {
            [imojiObjectsArray addObject:[self readImojiObject:result]];
        }

        return imojiObjectsArray;
    }

    return @[];
}

- (void)handleImojiFetchResponse:(NSArray *)imojiObjects
               relatedSearchTerm:(NSString *)relatedSearchTerm
               relatedCategories:(NSArray<IMImojiCategoryObject *> *)relatedCategories
               cancellationToken:(NSOperation *)cancellationToken
          searchResponseCallback:(IMImojiSessionResultSetResponseCallback)searchResponseCallback
           imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    if (cancellationToken.isCancelled) {
        return;
    }

    if (searchResponseCallback) {
        IMImojiResultSetMetadata *resultSetMetadata = [IMImojiResultSetMetadata new];
        resultSetMetadata.relatedSearchTerm = relatedSearchTerm;
        resultSetMetadata.relatedCategories = relatedCategories;
        resultSetMetadata.resultCount = @(imojiObjects.count);
        searchResponseCallback(resultSetMetadata, nil);
    }

    for (IMMutableImojiObject *imoji in imojiObjects) {
        if (imojiResponseCallback && !cancellationToken.isCancelled) {
            imojiResponseCallback(imoji, [imojiObjects indexOfObject:imoji], nil);
        }
    }
}

- (BFTask *)downloadImojiImageAsync:(IMMutableImojiObject *)imoji
                   renderingOptions:(IMImojiObjectRenderingOptions *)renderingOptions
                         imojiIndex:(NSUInteger)imojiIndex
                  cancellationToken:(NSOperation *)cancellationToken {
    return [self downloadImojiImageAsync:imoji
                        renderingOptions:renderingOptions
                             retriesLeft:IMImojiSessionNumberOfRetriesForImojiDownload
                              imojiIndex:imojiIndex
                       cancellationToken:cancellationToken];
}

- (BFTask *)downloadImojiImageAsync:(IMMutableImojiObject *)imoji
                   renderingOptions:(IMImojiObjectRenderingOptions *)renderingOptions
                        retriesLeft:(NSUInteger)retriesLeft
                         imojiIndex:(NSUInteger)imojiIndex
                  cancellationToken:(NSOperation *)cancellationToken {
    BFTaskCompletionSource *taskCompletionSource = [BFTaskCompletionSource taskCompletionSource];
    NSURL *url = [imoji getUrlForRenderingOptions:renderingOptions];

    [BFTask im_concurrentBackgroundTaskWithBlock:^id(BFTask *task) {
        if (cancellationToken.isCancelled) {
            return [BFTask cancelledTask];
        }

        // local files are stored as PNGs. Used in creation process for temporary Imojis
        if (url.isFileURL) {
            taskCompletionSource.result = [YYImage imageWithData:[NSData dataWithContentsOfURL:url] scale:[UIScreen mainScreen].scale];
            return nil;
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
                            ];
                        } else {
                            taskCompletionSource.error = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                                             code:IMImojiSessionErrorCodeServerError
                                                                         userInfo:@{
                                                                                 NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Unable to download %@ error code: %@", url, @(urlTask.error.code)]
                                                                         }];
                        }
                    });
                }
            } else {
                taskCompletionSource.result = [YYImage imageWithData:(NSData *) urlTask.result scale:[UIScreen mainScreen].scale];
            }

            return nil;
        }];

        return nil;
    }];

    return taskCompletionSource.task;
}

- (NSArray *)readCategories:(NSArray *)categories {
    NSMutableArray *imojiCategories = [NSMutableArray arrayWithCapacity:categories.count > 0 ? categories.count : 1];
    NSUInteger order = 0;

    for (NSDictionary *dictionary in categories) {
        NSDictionary *artistDictionary = dictionary[@"artist"];
        IMCategoryAttribution *attribution = nil;
        if (![artistDictionary isEqual:[NSNull null]]) {
            attribution = [self readAttribution:artistDictionary];
        }

        NSArray *imojisDictionary = [dictionary im_checkedArrayForKey:@"imojis"];
        NSMutableArray *previewImojis = [NSMutableArray new];
        if (imojisDictionary) {
            for (NSDictionary *imojiDictionary in imojisDictionary) {
                [previewImojis addObject:[self readImojiObject:imojiDictionary]];
            }
        } else if (dictionary[@"images"]) { // legacy support, pre server version v2.1
            [previewImojis addObject:[self readImojiObject:dictionary]];
        }

        [imojiCategories addObject:[IMMutableCategoryObject objectWithIdentifier:[dictionary im_checkedStringForKey:@"searchText"]
                                                                           order:order++
                                                                   previewImojis:previewImojis
                                                                        priority:[dictionary im_checkedNumberForKey:@"priority" defaultValue:@0].unsignedIntegerValue
                                                                           title:[dictionary im_checkedStringForKey:@"title"]
                                                                     attribution:attribution]];
    }

    return imojiCategories;
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

        [[self->_urlSession uploadTaskWithRequest:request
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
        IMImojiObjectLicenseStyle licenseStyle = IMImojiObjectLicenseStyleNonCommercial;
        if (result[@"licenseStyle"] && [@"commercialPrint" isEqualToString:result[@"licenseStyle"]]) {
            licenseStyle = IMImojiObjectLicenseStyleCommercialPrint;
        }

        BOOL readLegacy = [result[@"urls"] isKindOfClass:[NSDictionary class]];
        NSDictionary *imagesDictionary = readLegacy ? result[@"urls"] : result[@"images"];
        NSMutableDictionary *imageUrls = [NSMutableDictionary new];
        NSMutableDictionary *fileSizes = [NSMutableDictionary new];
        NSMutableDictionary *dimensions = [NSMutableDictionary new];
        NSNull *nullValue = [NSNull null];

        for (NSNumber *renderSize in @[@(IMImojiObjectRenderSizeThumbnail), @(IMImojiObjectRenderSizeFullResolution), @(IMImojiObjectRenderSize320), @(IMImojiObjectRenderSize512)]) {
            for (NSNumber *borderStyle in @[@(IMImojiObjectBorderStyleSticker), @(IMImojiObjectBorderStyleNone)]) {
                for (NSNumber *imageFormat in @[@(IMImojiObjectImageFormatWebP), @(IMImojiObjectImageFormatPNG), @(IMImojiObjectImageFormatAnimatedWebp), @(IMImojiObjectImageFormatAnimatedGif)]) {
                    IMImojiObjectRenderingOptions *renderingOptions = [IMImojiObjectRenderingOptions optionsWithRenderSize:(IMImojiObjectRenderSize) renderSize.unsignedIntegerValue
                                                                                                               borderStyle:(IMImojiObjectBorderStyle) borderStyle.unsignedIntegerValue
                                                                                                               imageFormat:(IMImojiObjectImageFormat) imageFormat.unsignedIntegerValue];

                    id path;
                    id url, width, height, fileSize;
                    BOOL animated = NO;

                    // read the old response format, in cache some old results are fetched from NSCache
                    if (readLegacy) {
                        switch (renderingOptions.imageFormat) {
                            case IMImojiObjectImageFormatPNG:
                                path = imagesDictionary[@"png"];
                                break;
                            case IMImojiObjectImageFormatWebP:
                                path = imagesDictionary[@"webp"];
                                break;
                            case IMImojiObjectImageFormatAnimatedGif:
                                animated = YES;
                                path = result[@"animated"][@"gif"];
                                break;
                            case IMImojiObjectImageFormatAnimatedWebp:
                                animated = YES;
                                path = result[@"animated"][@"webp"];
                                break;
                            default:
                                path = nil;
                                break;
                        }

                        if (!path || ![path isKindOfClass:[NSDictionary class]]) {
                            imageUrls[renderingOptions] = [NSNull null];
                            continue;
                        }

                        if (!animated) {
                            switch (renderingOptions.borderStyle) {
                                case IMImojiObjectBorderStyleSticker:
                                    break;

                                case IMImojiObjectBorderStyleNone:
                                    path = path[@"raw"];
                                    break;
                            }
                        }

                        if (!path || ![path isKindOfClass:[NSDictionary class]]) {
                            imageUrls[renderingOptions] = [NSNull null];
                            continue;
                        }

                        switch (renderingOptions.renderSize) {
                            case IMImojiObjectRenderSizeThumbnail:
                                if (animated) {
                                    url = path[@"150"][@"url"];
                                } else {
                                    url = path[@"thumb"];
                                }
                                break;

                            case IMImojiObjectRenderSizeFullResolution:
                                if (animated) {
                                    url = path[@"1200"][@"url"];
                                } else {
                                    url = path[@"full"];
                                }
                                break;

                            case IMImojiObjectRenderSize320:
                                if (animated) {
                                    url = path[@"320"][@"url"];
                                } else {
                                    url = path[@"320"];
                                }
                                break;

                            case IMImojiObjectRenderSize512:
                                if (animated) {
                                    url = path[@"512"][@"url"];
                                } else {
                                    url = path[@"512"];
                                }
                                break;
                        }
                    } else {
                        if (renderingOptions.imageFormat == IMImojiObjectImageFormatAnimatedGif || renderingOptions.imageFormat == IMImojiObjectImageFormatAnimatedWebp) {
                            path = imagesDictionary[@"animated"];
                        } else if (renderingOptions.borderStyle == IMImojiObjectBorderStyleNone) {
                            path = imagesDictionary[@"unbordered"];
                        } else if (renderingOptions.borderStyle == IMImojiObjectBorderStyleSticker) {
                            path = imagesDictionary[@"bordered"];
                        }

                        if (!path || ![path isKindOfClass:[NSDictionary class]]) {
                            imageUrls[renderingOptions] = fileSizes[renderingOptions] = dimensions[renderingOptions] = nullValue;
                            continue;
                        }

                        switch (renderingOptions.imageFormat) {
                            case IMImojiObjectImageFormatPNG:
                                path = path[@"png"];
                                break;
                            case IMImojiObjectImageFormatWebP:
                            case IMImojiObjectImageFormatAnimatedWebp:
                                path = path[@"webp"];
                                break;
                            case IMImojiObjectImageFormatAnimatedGif:
                                path = path[@"gif"];
                                break;
                            default:
                                path = nil;
                                break;
                        }

                        switch (renderingOptions.renderSize) {
                            case IMImojiObjectRenderSizeThumbnail:
                                path = path[@"150"];
                                break;

                            case IMImojiObjectRenderSizeFullResolution:
                                path = path[@"1200"];
                                break;

                            case IMImojiObjectRenderSize320:
                                path = path[@"320"];
                                break;

                            case IMImojiObjectRenderSize512:
                                path = path[@"512"];
                                break;
                        }

                        if (!path || ![path isKindOfClass:[NSDictionary class]]) {
                            imageUrls[renderingOptions] = fileSizes[renderingOptions] = dimensions[renderingOptions] = nullValue;
                            continue;
                        }

                        url = path[@"url"];
                        width = path[@"width"];
                        height = path[@"height"];
                        fileSize = path[@"fileSize"];
                    }

                    if ([url isKindOfClass:[NSString class]]) {
                        imageUrls[renderingOptions] = [NSURL URLWithString:url];
                    } else {
                        imageUrls[renderingOptions] = nullValue;
                    }

                    if ([width isKindOfClass:[NSNumber class]] && [height isKindOfClass:[NSNumber class]]) {
                        NSNumber *widthValue = (NSNumber *) width;
                        NSNumber *heightValue = (NSNumber *) height;
                        if (widthValue.floatValue > 0 && heightValue.floatValue > 0) {
                            dimensions[renderingOptions] = [NSValue valueWithCGSize:CGSizeMake(widthValue.floatValue, heightValue.floatValue)];
                        } else {
                            dimensions[renderingOptions] = nullValue;
                        }
                    } else {
                        dimensions[renderingOptions] = nullValue;
                    }

                    if ([fileSize isKindOfClass:[NSNumber class]] && ((NSNumber *) fileSize).longValue > 0) {
                        fileSizes[renderingOptions] = fileSize;
                    } else {
                        fileSizes[renderingOptions] = nullValue;
                    }
                }
            }
        }

        return [IMMutableImojiObject imojiWithIdentifier:imojiId
                                                    tags:tags
                                                    urls:imageUrls
                                         imageDimensions:dimensions
                                               fileSizes:fileSizes
                                            licenseStyle:licenseStyle];
    } else {
        return nil;
    }
}

- (nonnull IMCategoryAttribution *)readAttribution:(nonnull NSDictionary *)attributionDictionary {
    static NSDictionary *urlCategoryMappings;
    static dispatch_once_t token;

    dispatch_once(&token, ^{
        urlCategoryMappings = @{
                @"website" : @(IMAttributionURLCategoryWebsite),
                @"video" : @(IMAttributionURLCategoryVideo),
                @"instagram" : @(IMAttributionURLCategoryInstagram),
                @"twitter" : @(IMAttributionURLCategoryTwitter),
                @"app store" : @(IMAttributionURLCategoryAppStore)
        };
    });

    IMAttributionURLCategory urlCategory = IMAttributionURLCategoryWebsite;
    NSString *urlCategoryString = [attributionDictionary im_checkedStringForKey:@"packURLCategory"];
    if (urlCategoryString && urlCategoryMappings[urlCategoryString]) {
        urlCategory = (IMAttributionURLCategory) ((NSNumber *) urlCategoryMappings[urlCategoryString]).unsignedIntegerValue;
    }

    NSString *attributionIdentifier = [attributionDictionary im_checkedStringForKey:@"packId"];
    NSArray *relatedTags = [attributionDictionary im_checkedArrayForKey:@"relatedTags" defaultValue:@[]];

    IMArtist *artist = nil;
    if (attributionDictionary[@"id"]) {
        artist = [IMMutableArtist artistWithIdentifier:[attributionDictionary im_checkedStringForKey:@"id"]
                                                  name:[attributionDictionary im_checkedStringForKey:@"name"]
                                               summary:[attributionDictionary im_checkedStringForKey:@"description"]
                                          previewImoji:[self readImojiObject:attributionDictionary]];
    }


    NSURL *attributionURL;
    if (attributionDictionary[@"packURL"]) {
        attributionURL = [[NSURL alloc] initWithString:[attributionDictionary im_checkedStringForKey:@"packURL"]];
    }

    IMImojiObjectLicenseStyle licenseStyle = IMImojiObjectLicenseStyleNonCommercial;
    if (attributionDictionary[@"licenseStyle"] && [@"commercialPrint" isEqualToString:attributionDictionary[@"licenseStyle"]]) {
        licenseStyle = IMImojiObjectLicenseStyleCommercialPrint;
    }

    return [IMMutableCategoryAttribution attributionWithIdentifier:attributionIdentifier
                                                            artist:artist
                                                               URL:attributionURL
                                                       urlCategory:urlCategory
                                                       relatedTags:relatedTags
                                                      licenseStyle:licenseStyle];
}

#pragma mark Imoji Reading/Writing

- (BFTask *)writeImoji:(IMImojiObject *)imoji
      renderingOptions:(IMImojiObjectRenderingOptions *)renderingOptions
         imageContents:(NSData *)imageContents
           synchronous:(BOOL)synchronous {

    return [[BFTask taskWithDelay:0] continueWithExecutor:synchronous ? [BFExecutor mainThreadExecutor] : [BFTask im_concurrentBackgroundExecutor]
                                                withBlock:^id(BFTask *task) {
                                                    NSString *fullImojiPath = [self filePathFromImoji:imoji renderingOptions:renderingOptions];
                                                    NSError *error;

                                                    [imageContents writeToFile:fullImojiPath options:NSDataWritingAtomic error:&error];

                                                    NSURL *pathUrl = [NSURL fileURLWithPath:fullImojiPath];
                                                    [pathUrl setResourceValue:@YES
                                                                       forKey:NSURLIsExcludedFromBackupKey
                                                                        error:&error];

                                                    return nil;
                                                }];
}

- (void)removeImoji:(IMImojiObject *)imoji
   renderingOptions:(IMImojiObjectRenderingOptions *)renderingOptions {
    NSString *fullImojiPath = [self filePathFromImoji:imoji renderingOptions:renderingOptions];
    [self removeFile:fullImojiPath];
}

- (NSString *)filePathFromImoji:(IMImojiObject *)imoji renderingOptions:(IMImojiObjectRenderingOptions *)renderingOptions {
    return [NSString stringWithFormat:@"%@/%@-%@-%@.%@",
                                      self.storagePolicy.cachePath.path,
                                      @(renderingOptions.renderSize),
                                      @(renderingOptions.borderStyle),
                                      imoji.identifier,
                                      @(renderingOptions.imageFormat)
    ];
}

- (void)removeFile:(NSString *)path {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    }
}

@end
