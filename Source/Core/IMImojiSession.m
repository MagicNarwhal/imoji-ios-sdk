//
//  ImojiSDK
//
//  Created by Nima Khoshini
//  Copyright (C) 2015 Imoji
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

#import <Bolts/BFTaskCompletionSource.h>
#import <Bolts/BFTask.h>
#import <Bolts/BFExecutor.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <ImageIO/ImageIO.h>
#import <YYImage/YYImage.h>
#import "ImojiSDK.h"
#import "NSDictionary+Utils.h"
#import "IMMutableImojiObject.h"
#import "UIImage+Extensions.h"
#import "IMImojiSession+Private.h"
#import "IMMutableCategoryAttribution.h"
#import "IMCategoryFetchOptions.h"

#if IMMessagesFrameworkSupported
#import <Messages/Messages.h>
#import "BFTask+Utils.h"
#endif

NSString *const IMImojiSessionErrorDomain = @"IMImojiSessionErrorDomain";

@implementation IMImojiSession

@synthesize sessionState = _sessionState;

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupWithStoragePolicy:[IMImojiSessionStoragePolicy temporaryDiskStoragePolicy]];
    }

    return self;
}

- (instancetype)initWithStoragePolicy:(IMImojiSessionStoragePolicy *)storagePolicy {
    self = [super init];
    if (self) {
        [self setupWithStoragePolicy:storagePolicy];
    }

    return self;
}

- (void)setupWithStoragePolicy:(IMImojiSessionStoragePolicy *)storagePolicy {
    _sessionState = IMImojiSessionStateNotConnected;
    _storagePolicy = storagePolicy;

    self->_urlSession = [NSURLSession sessionWithConfiguration:[_storagePolicy generateURLSessionConfiguration]];

    [self readAuthenticationCredentials];
}

- (BFTask *)downloadImojiContents:(IMMutableImojiObject *)imoji
                  renderingOtions:(IMImojiObjectRenderingOptions *)renderingOptions
                cancellationToken:cancellationToken {
    __block BFTaskCompletionSource *taskCompletionSource = [BFTaskCompletionSource taskCompletionSource];
    [[self validateSession] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *task) {
        if (task.error) {
            taskCompletionSource.error = task.error;
        } else {
            if (!imoji.urls) {
                taskCompletionSource.error = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                                 code:IMImojiSessionErrorCodeImojiDoesNotExist
                                                             userInfo:@{
                                                                     NSLocalizedDescriptionKey : [NSString stringWithFormat:@"unable to download imoji %@", imoji.identifier]
                                                             }];
            } else {
                [[self downloadImojiImageAsync:imoji
                              renderingOptions:renderingOptions
                                    imojiIndex:0
                             cancellationToken:cancellationToken] continueWithExecutor:[BFExecutor mainThreadExecutor]
                                                                             withBlock:^id(BFTask *downloadTask) {
                                                                                 if (downloadTask.error) {
                                                                                     taskCompletionSource.error = downloadTask.error;
                                                                                 } else {
                                                                                     taskCompletionSource.result = downloadTask.result;
                                                                                 }

                                                                                 return nil;
                                                                             }];
            }
        }

        return nil;
    }];

    return taskCompletionSource.task;
}

#pragma mark Public Methods

- (nonnull NSOperation *)getImojiCategoriesWithClassification:(IMImojiSessionCategoryClassification)classification
                                                     callback:(nonnull IMImojiSessionImojiCategoriesResponseCallback)callback {
    return [self getImojiCategoriesWithOptions:[IMCategoryFetchOptions optionsWithClassification:classification] callback:callback];
}

- (nonnull NSOperation *)getImojiCategoriesWithOptions:(IMCategoryFetchOptions *)options
                                              callback:(nonnull IMImojiSessionImojiCategoriesResponseCallback)callback {
    __block NSOperation *cancellationToken = self.cancellationTokenOperation;
    __block NSString *classificationParameter = [IMImojiSession categoryClassifications][@(options.classification)];

    NSMutableDictionary *parameters = [NSMutableDictionary new];

    parameters[@"classification"] = classificationParameter;
    if (options.contextualSearchPhrase != nil) {
        parameters[@"contextualSearchPhrase"] = options.contextualSearchPhrase;

        if (options.contextualSearchLocale && options.contextualSearchLocale.localeIdentifier) {
            parameters[@"locale"] = options.contextualSearchLocale.localeIdentifier;
        }
    }

    if (options.licenseStyles) {
        parameters[@"licenseStyles"] = options.licenseStyles;
    }

    [[self runValidatedGetTaskWithPath:@"/imoji/categories/fetch"
                         andParameters:parameters]
            continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        NSDictionary *results = getTask.result;

        __block NSError *error;
        [self validateServerResponse:results error:&error];
        if (error) {
            callback(nil, error);
        } else {
            NSArray *categories = results[@"categories"];
            if (callback) {
                if ([categories isEqual:[NSNull null]]) {
                    callback(nil, nil);
                } else {
                    callback([self readCategories:categories], nil);
                }
            }
        }

        return nil;
    }];

    return cancellationToken;
}

- (NSOperation *)searchImojisWithTerm:(NSString *)searchTerm
                               offset:(NSNumber *)offset
                      numberOfResults:(NSNumber *)numberOfResults
            resultSetResponseCallback:(IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    return [self searchImojisWithTerm:searchTerm offset:offset contributingImojiId:nil numberOfResults:numberOfResults resultSetResponseCallback:resultSetResponseCallback imojiResponseCallback:imojiResponseCallback];
}

- (NSOperation *)searchImojisWithTerm:(NSString *)searchTerm
                               offset:(NSNumber *)offset
                  contributingImojiId:(NSString *)contributingImojiId
                      numberOfResults:(NSNumber *)numberOfResults
            resultSetResponseCallback:(IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    __block NSOperation *cancellationToken = self.cancellationTokenOperation;

    if (numberOfResults && numberOfResults.integerValue <= 0) {
        numberOfResults = nil;
    }

    if (offset && offset.integerValue < 0) {
        offset = nil;
    }

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
            @"query" : searchTerm != nil ? searchTerm : @"",
            @"numResults" : numberOfResults != nil ? numberOfResults : [NSNull null],
            @"offset" : offset != nil ? offset : @0
    }];

    if (contributingImojiId) {
        parameters[@"contributingImojiId"] = contributingImojiId;
    }

    [[self runValidatedGetTaskWithPath:@"/imoji/search" andParameters:parameters] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        NSDictionary *results = getTask.result;

        NSError *error;
        [self validateServerResponse:results error:&error];
        if (error) {
            resultSetResponseCallback(nil, error);
        } else {
            [self handleImojiFetchResponse:[self convertServerDataSetToImojiArray:results]
                         relatedSearchTerm:[results im_checkedStringForKey:@"followupSearchTerm"]
                         relatedCategories:[self readCategories:[results im_checkedArrayForKey:@"relatedCategories" defaultValue:@[]]]
                         cancellationToken:cancellationToken
                    searchResponseCallback:resultSetResponseCallback
                     imojiResponseCallback:imojiResponseCallback];
        }

        return nil;
    }];

    return cancellationToken;
}

- (NSOperation *)getFeaturedImojisWithNumberOfResults:(NSNumber *)numberOfResults
                            resultSetResponseCallback:(IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                                imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    __block NSOperation *cancellationToken = self.cancellationTokenOperation;

    id numResultsValue;
    if (numberOfResults && numberOfResults.integerValue <= 0) {
        numResultsValue = [NSNull null];
    } else {
        numResultsValue = numberOfResults != nil ? numberOfResults : [NSNull null];
    }

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
            @"numResults" : numResultsValue
    }];

    [[self runValidatedGetTaskWithPath:@"/imoji/featured/fetch" andParameters:parameters] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        if (cancellationToken.cancelled) {
            return [BFTask cancelledTask];
        }

        if (getTask.error) {
            resultSetResponseCallback(nil, getTask.error);
            return nil;
        }

        NSDictionary *results = getTask.result;
        NSError *error;
        [self validateServerResponse:results error:&error];

        if (error) {
            resultSetResponseCallback(nil, error);
        } else {
            [self handleImojiFetchResponse:[self convertServerDataSetToImojiArray:results]
                         relatedSearchTerm:[results im_checkedStringForKey:@"followupSearchTerm"]
                         relatedCategories:[self readCategories:[results im_checkedArrayForKey:@"relatedCategories" defaultValue:@[]]]
                         cancellationToken:cancellationToken
                    searchResponseCallback:resultSetResponseCallback
                     imojiResponseCallback:imojiResponseCallback];
        }

        return nil;
    }];

    return cancellationToken;
}

- (NSOperation *)fetchImojisByIdentifiers:(NSArray *)imojiObjectIdentifiers
                  fetchedResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)fetchedResponseCallback {
    __block NSOperation *cancellationToken = self.cancellationTokenOperation;
    if (!imojiObjectIdentifiers || imojiObjectIdentifiers.count == 0) {
        fetchedResponseCallback(nil, NSUIntegerMax, [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                                        code:IMImojiSessionErrorCodeInvalidArgument
                                                                    userInfo:@{
                                                                            NSLocalizedDescriptionKey : @"imojiObjectIdentifiers is either nil or empty"
                                                                    }]);
        return cancellationToken;
    }
    BOOL validArray = YES;
    for (id objectIdentifier in imojiObjectIdentifiers) {
        if (!objectIdentifier || ![objectIdentifier isKindOfClass:[NSString class]]) {
            validArray = NO;
            break;
        }
    }

    if (!validArray) {
        fetchedResponseCallback(nil, NSUIntegerMax, [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                                        code:IMImojiSessionErrorCodeInvalidArgument
                                                                    userInfo:@{
                                                                            NSLocalizedDescriptionKey : @"imojiObjectIdentifiers must contain NSString objects only"
                                                                    }]);
        return cancellationToken;
    }

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
            @"ids" : [imojiObjectIdentifiers componentsJoinedByString:@","]
    }];

    [[self runValidatedPostTaskWithPath:@"/imoji/fetchMultiple" andParameters:parameters] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        if (cancellationToken.cancelled) {
            return [BFTask cancelledTask];
        }

        NSDictionary *results = getTask.result;
        NSError *error;
        [self validateServerResponse:results error:&error];

        if (error) {
            fetchedResponseCallback(nil, NSUIntegerMax, error);
        } else {
            NSMutableArray *imojiObjects = [NSMutableArray arrayWithArray:[self convertServerDataSetToImojiArray:results]];

            [self handleImojiFetchResponse:imojiObjects
                         relatedSearchTerm:[results im_checkedStringForKey:@"followupSearchTerm"]
                         relatedCategories:[self readCategories:[results im_checkedArrayForKey:@"relatedCategories" defaultValue:@[]]]
                         cancellationToken:cancellationToken
                    searchResponseCallback:nil
                     imojiResponseCallback:fetchedResponseCallback];
        }

        return nil;
    }];

    return cancellationToken;
}

- (NSOperation *)searchImojisWithSentence:(NSString *)sentence
                          numberOfResults:(NSNumber *)numberOfResults
                resultSetResponseCallback:(IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                    imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    __block NSOperation *cancellationToken = self.cancellationTokenOperation;

    if (numberOfResults && numberOfResults.integerValue <= 0) {
        numberOfResults = nil;
    }

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
            @"sentence" : sentence,
            @"numResults" : numberOfResults != nil ? numberOfResults : [NSNull null]
    }];

    [[self runValidatedGetTaskWithPath:@"/imoji/search" andParameters:parameters] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        NSDictionary *results = getTask.result;

        NSError *error;
        [self validateServerResponse:results error:&error];
        if (error) {
            resultSetResponseCallback(nil, error);
        } else {
            [self handleImojiFetchResponse:[self convertServerDataSetToImojiArray:results]
                         relatedSearchTerm:[results im_checkedStringForKey:@"followupSearchTerm"]
                         relatedCategories:[self readCategories:[results im_checkedArrayForKey:@"relatedCategories" defaultValue:@[]]]
                         cancellationToken:cancellationToken
                    searchResponseCallback:resultSetResponseCallback
                     imojiResponseCallback:imojiResponseCallback];
        }

        return nil;
    }];

    return cancellationToken;
}

- (NSOperation *)addImojiToUserCollection:(IMImojiObject *)imojiObject
                                 callback:(IMImojiSessionAsyncResponseCallback)callback {
    __block NSOperation *cancellationToken = self.cancellationTokenOperation;

    [[self runValidatedPostTaskWithPath:@"/user/imoji/collection/add" andParameters:@{
            @"imojiId" : imojiObject.identifier
    }] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        if (cancellationToken.cancelled) {
            return [BFTask cancelledTask];
        }

        NSDictionary *results = getTask.result;
        NSError *error;
        [self validateServerResponse:results error:&error];

        if (error) {
            callback(NO, error);
        } else {
            callback(YES, nil);
        }

        return nil;
    }];

    return cancellationToken;
}

- (NSOperation *)getImojisForAuthenticatedUserWithResultSetResponseCallback:(IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                                                      imojiResponseCallback:(IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    return [self fetchCollectedImojisWithType:IMImojiCollectionTypeAll
                    resultSetResponseCallback:resultSetResponseCallback
                        imojiResponseCallback:imojiResponseCallback];
}

- (nonnull NSOperation *)fetchCollectedImojisWithType:(IMImojiCollectionType)collectionType
                            resultSetResponseCallback:(nonnull IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                                imojiResponseCallback:(nonnull IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback {
    NSOperation *cancellationToken = self.cancellationTokenOperation;
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:1];
    switch (collectionType) {
        case IMImojiCollectionTypeRecents:
            params[@"collectionType"] = @"recents";
            break;
        case IMImojiCollectionTypeCreated:
            params[@"collectionType"] = @"created";
            break;
        case IMImojiCollectionTypeLiked:
            params[@"collectionType"] = @"liked";
            break;
        case IMImojiCollectionTypeAll:
            break;
    }

    [[self runValidatedGetTaskWithPath:@"/user/imoji/fetch" andParameters:params] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        if (cancellationToken.cancelled) {
            return [BFTask cancelledTask];
        }

        NSDictionary *results = getTask.result;
        NSError *error;
        [self validateServerResponse:results error:&error];

        if (error) {
            resultSetResponseCallback(nil, error);
        } else {
            [self handleImojiFetchResponse:[self convertServerDataSetToImojiArray:results]
                         relatedSearchTerm:[results im_checkedStringForKey:@"followupSearchTerm"]
                         relatedCategories:[self readCategories:[results im_checkedArrayForKey:@"relatedCategories" defaultValue:@[]]]
                         cancellationToken:cancellationToken
                    searchResponseCallback:resultSetResponseCallback
                     imojiResponseCallback:imojiResponseCallback];
        }

        return nil;
    }];

    return cancellationToken;
}

#pragma mark Imoji Modification

- (NSOperation *)createImojiWithRawImage:(UIImage *)image
                           borderedImage:(UIImage *)borderedImage
                                    tags:(NSArray *)tags
                     beginUploadCallback:(nonnull IMImojiSessionCreationResponseCallback)beginUploadCallback
                    finishUploadCallback:(nonnull IMImojiSessionCreationResponseCallback)finishUploadCallback {
    NSOperation *cancellationToken = self.cancellationTokenOperation;

    __block NSString *imojiId;
    __block IMImojiObject *localImoji;
    [[[[[self createLocalImojiWithRawImage:image
                             borderedImage:borderedImage
                                      tags:tags]
            continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *task) {
                if (task.error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        beginUploadCallback(nil, task.error);
                    });

                    return [BFTask taskWithError:task.error];
                }

                localImoji = task.result;

                // trigger completion of the temporary imoji
                beginUploadCallback(localImoji, nil);

                // call the server to create a new imoji
                return [self runValidatedPostTaskWithPath:@"/imoji/create" andParameters:@{
                        @"tags" : tags != nil ? tags : [NSNull null]
                }];
            }]
            continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
                if (getTask.error) {
                    return [BFTask taskWithError:getTask.error];
                }

                if (cancellationToken.cancelled) {
                    return [BFTask cancelledTask];
                }

                NSDictionary *results = getTask.result;
                NSError *error;
                [self validateServerResponse:results error:&error];

                if (error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        finishUploadCallback(nil, error);
                    });

                    return error;
                }

                return results;
            }]
            continueWithSuccessBlock:^id(BFTask *task) {
                NSDictionary *response = (NSDictionary *) task.result;
                NSString *fullImageUrl = response[@"fullImageUrl"];

                imojiId = response[@"imojiId"];

                CGSize maxDimensions = CGSizeMake(
                        [(NSNumber *) response[@"fullImageResizeWidth"] floatValue],
                        [(NSNumber *) response[@"fullImageResizeHeight"] floatValue]
                );

                // start the upload
                return [self uploadImageInBackgroundWithRetries:[image im_resizedImageToFitInSize:maxDimensions scaleIfSmaller:NO]
                                                      uploadUrl:[NSURL URLWithString:fullImageUrl]
                                                     retryCount:3];
            }]
            continueWithBlock:
                    ^id(BFTask *task) {
                        if (task.error) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                finishUploadCallback(nil, [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                                              code:IMImojiSessionErrorCodeServerError
                                                                          userInfo:@{
                                                                                  NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Unable to upload imoji image"]
                                                                          }]);
                            });

                            return task.error;
                        }

                        // call the server once more to get the generated URL's for the new Imoji ID
                        [self fetchImojisByIdentifiers:@[imojiId]
                               fetchedResponseCallback:^(IMImojiObject *imoji, NSUInteger index, NSError *error) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       finishUploadCallback(imoji, error);
                                   });
                               }];

                        return nil;
                    }];

    return cancellationToken;
}

- (NSOperation *)removeImoji:(IMImojiObject *)imojiObject
                    callback:(IMImojiSessionAsyncResponseCallback)callback {

    __block NSOperation *cancellationToken = self.cancellationTokenOperation;

    [[self runValidatedDeleteTaskWithPath:@"/imoji/remove" andParameters:@{
            @"imojiId" : imojiObject.identifier
    }] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        if (cancellationToken.cancelled) {
            return [BFTask cancelledTask];
        }

        NSDictionary *results = getTask.result;
        NSError *error;
        [self validateServerResponse:results error:&error];

        if (error) {
            callback(NO, error);
        } else {
            callback(YES, nil);
        }

        return nil;
    }];

    return cancellationToken;
}

- (nonnull NSOperation *)reportImojiAsAbusiveWithIdentifier:(nonnull NSString *)imojiIdentifier
                                                     reason:(nullable NSString *)reason
                                                   callback:(nonnull IMImojiSessionAsyncResponseCallback)callback {
    __block NSOperation *cancellationToken = self.cancellationTokenOperation;

    [[self runValidatedPostTaskWithPath:@"/imoji/reportAbusive" andParameters:@{
            @"imojiId" : imojiIdentifier,
            @"reason" : reason
    }] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *getTask) {
        if (cancellationToken.cancelled) {
            return [BFTask cancelledTask];
        }

        NSDictionary *results = getTask.result;
        NSError *error;
        [self validateServerResponse:results error:&error];

        if (error) {
            callback(NO, error);
        } else {
            callback(YES, nil);
        }

        return nil;
    }];

    return cancellationToken;
}

#pragma mark Analytics

- (void)markImojiUsageWithIdentifier:(nonnull NSString *)imojiIdentifier
                    originIdentifier:(nullable NSString *)originIdentifier {
    if (originIdentifier && originIdentifier.length > 40) {
        NSLog(@"WARNING: truncating originIdentifier '%@' to 40 characters.", originIdentifier);
        originIdentifier = [originIdentifier substringToIndex:40];
    }

    [[self runValidatedGetTaskWithPath:@"/analytics/imoji/sent" andParameters:@{
            @"imojiId" : imojiIdentifier,
            @"originIdentifier" : originIdentifier ? originIdentifier : [NSNull null]
    }]
            continueWithExecutor:[BFExecutor mainThreadExecutor]
                       withBlock:^id(BFTask *task) {
                           return nil;
                       }];
}

- (void)setUserDemographicsData:(nullable NSString *)gender
                       latitute:(nullable NSNumber *)latitude
                      longitude:(nullable NSNumber *)longitude
                    dateOfBirth:(nullable NSDate *)dateOfBirth {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];

    if (gender) {
        if ([@"male" isEqualToString:gender] || [@"female" isEqualToString:gender]) {
            values[@"gender"] = gender;
        } else {
            NSLog(@"WARNING: Unknown value '%@' sent for gender. Possible values are 'male' or 'female'", gender);
        }
    }

    if (latitude && longitude) {
        values[@"latitude"] = latitude;
        values[@"longitude"] = longitude;
    }

    if (dateOfBirth) {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"MM-dd-yyyy"];
        values[@"dateOfBirth"] = [dateFormatter stringFromDate:dateOfBirth];
    }

    if (values.count > 0) {
        [[self runValidatedPostTaskWithPath:@"/analytics/demographics" andParameters:values]
                continueWithExecutor:[BFExecutor mainThreadExecutor]
                           withBlock:^id(BFTask *task) {
                               return nil;
                           }];
    }
}

#pragma mark Attribution

- (nonnull NSOperation *)fetchAttributionByImojiIdentifiers:(nonnull NSArray *)imojiObjectIdentifiers
                                                   callback:(nonnull IMImojiSessionImojiAttributionResponseCallback)callback {

    __block NSOperation *cancellationToken = self.cancellationTokenOperation;
    if (!imojiObjectIdentifiers || imojiObjectIdentifiers.count == 0) {
        callback(nil, [NSError errorWithDomain:IMImojiSessionErrorDomain
                                          code:IMImojiSessionErrorCodeInvalidArgument
                                      userInfo:@{
                                              NSLocalizedDescriptionKey : @"imojiObjectIdentifiers is either nil or empty"
                                      }]);
        return cancellationToken;
    }
    BOOL validArray = YES;
    for (id objectIdentifier in imojiObjectIdentifiers) {
        if (!objectIdentifier || ![objectIdentifier isKindOfClass:[NSString class]]) {
            validArray = NO;
            break;
        }
    }

    if (!validArray) {
        callback(nil, [NSError errorWithDomain:IMImojiSessionErrorDomain
                                          code:IMImojiSessionErrorCodeInvalidArgument
                                      userInfo:@{
                                              NSLocalizedDescriptionKey : @"imojiObjectIdentifiers must contain NSString objects only"
                                      }]);
        return cancellationToken;
    }

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
            @"imojiIds" : [imojiObjectIdentifiers componentsJoinedByString:@","]
    }];

    [[self runValidatedGetTaskWithPath:@"/imoji/attribution" andParameters:parameters]
            continueWithExecutor:[BFExecutor mainThreadExecutor]
                       withBlock:^id(BFTask *getTask) {
                           if (cancellationToken.cancelled) {
                               return [BFTask cancelledTask];
                           }

                           NSDictionary *results = getTask.result;
                           NSError *error;
                           [self validateServerResponse:results error:&error];

                           NSMutableDictionary *converted = [NSMutableDictionary dictionary];
                           if ([results[@"attribution"] isKindOfClass:[NSDictionary class]]) {
                               NSDictionary *attributionMap = results[@"attribution"];
                               for (NSString *imojiId in [attributionMap allKeys]) {
                                   converted[imojiId] = [self readAttribution:attributionMap[imojiId]];
                               }
                           }

                           if (error) {
                               callback(nil, error);
                           } else {
                               callback([NSDictionary dictionaryWithDictionary:converted], nil);
                           }

                           return nil;
                       }];

    return cancellationToken;
}


#pragma mark Rendering

- (NSOperation *)renderImoji:(IMImojiObject *)imoji
                     options:(IMImojiObjectRenderingOptions *)options
                    callback:(IMImojiSessionImojiRenderResponseCallback)callback {
    __block NSOperation *cancellationToken = self.cancellationTokenOperation;

    if (!imoji || !imoji.identifier) {
        NSError *error = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                             code:IMImojiSessionErrorCodeImojiDoesNotExist
                                         userInfo:@{
                                                 NSLocalizedDescriptionKey : @"Imoji is invalid"
                                         }];

        callback(nil, error);

        return cancellationToken;
    } else if (![imoji isKindOfClass:[IMMutableImojiObject class]]) {
        [self fetchImojisByIdentifiers:@[imoji.identifier]
               fetchedResponseCallback:^(IMImojiObject *internalImoji, NSUInteger index, NSError *error) {
                   if (cancellationToken.cancelled) {
                       return;
                   }

                   [self renderImoji:(IMMutableImojiObject *) internalImoji
                             options:options
                            callback:callback
                   cancellationToken:cancellationToken];
               }];
    } else {
        [self renderImoji:(IMMutableImojiObject *) imoji
                  options:options callback:callback
        cancellationToken:cancellationToken];
    }

    return cancellationToken;
}

- (nonnull NSOperation *)renderImojiForExport:(nonnull IMImojiObject *)imoji
                                      options:(nonnull IMImojiObjectRenderingOptions *)options
                                     callback:(nonnull IMImojiSessionExportedImageResponseCallback)callback {
    return [self renderImoji:imoji options:options callback:^(UIImage *image, NSError *error) {

        if (error) {
            callback(nil, nil, nil, error);
        } else {
            NSData *attachmentData = nil;
            NSError *exportError = nil;
            NSString *typeIdentifier = nil;

            if (imoji.supportsAnimation && options.renderAnimatedIfSupported) {
                if ([image isKindOfClass:[YYImage class]]) {
                    YYImage *yyImage = (YYImage *) image;

                    if (yyImage.animatedImageType == YYImageTypeGIF) {
                        attachmentData = yyImage.animatedImageData;
                        typeIdentifier = (NSString *) kUTTypeGIF;
                    } else if (yyImage.animatedImageType == YYImageTypeWebP) {
                        // YYImage animatedImageData gives back the full webp data which is unusable for exporting
                        // manually convert it here using a simple method to convert animated frames to NSData adapted from:
                        // https://github.com/mattt/AnimatedGIFImageSerialization/blob/master/AnimatedGIFImageSerialization/AnimatedGIFImageSerialization.m

                        NSUInteger frameCount = yyImage.animatedImageFrameCount;
                        NSMutableData *mutableData = [NSMutableData data];
                        CGImageDestinationRef destination =
                                CGImageDestinationCreateWithData((__bridge CFMutableDataRef) mutableData, kUTTypeGIF, frameCount, NULL);

                        NSDictionary *imageProperties = @{(__bridge NSString *) kCGImagePropertyGIFDictionary : @{
                                (__bridge NSString *) kCGImagePropertyGIFLoopCount : @(yyImage.animatedImageLoopCount)
                        }};
                        CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef) imageProperties);

                        for (NSUInteger i = 0; i < frameCount; i++) {
                            NSDictionary *frameProperties = @{(__bridge NSString *) kCGImagePropertyGIFDictionary : @{
                                    (__bridge NSString *) kCGImagePropertyGIFUnclampedDelayTime : @([yyImage animatedImageDurationAtIndex:i]),
                                    (__bridge NSString *) kCGImagePropertyGIFDelayTime : @([yyImage animatedImageDurationAtIndex:i])
                            }};
                            CGImageDestinationAddImage(destination, [[yyImage animatedImageFrameAtIndex:i] CGImage], (__bridge CFDictionaryRef) frameProperties);
                        }

                        BOOL success = CGImageDestinationFinalize(destination);
                        CFRelease(destination);

                        if (!success) {
                            exportError = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                              code:IMImojiSessionErrorCodeImojiRenderingUnavailable
                                                          userInfo:@{
                                                                  NSLocalizedDescriptionKey : @"Unable to export WEBP to GIF"
                                                          }];
                        } else {
                            attachmentData = mutableData;
                            typeIdentifier = (NSString *) kUTTypeGIF;
                        }

                    } else {
                        exportError = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                          code:IMImojiSessionErrorCodeImojiRenderingUnavailable
                                                      userInfo:@{
                                                              NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Unsupported YYImageType %@", @(yyImage.animatedImageType)]
                                                      }];
                    }
                } else {
                    exportError = [NSError errorWithDomain:IMImojiSessionErrorDomain
                                                      code:IMImojiSessionErrorCodeImojiRenderingUnavailable
                                                  userInfo:@{
                                                          NSLocalizedDescriptionKey : @"Unsupported animated image! Only YYImage references are currently supported."
                                                  }];
                }
            } else {
                attachmentData = UIImagePNGRepresentation(image);
                typeIdentifier = (NSString *) kUTTypePNG;
            }

            callback(image, attachmentData, typeIdentifier, exportError);
        }
    }];
}

- (nonnull NSOperation *)renderImojiAsMSSticker:(nonnull IMImojiObject *)imoji
                                        options:(nonnull IMImojiObjectRenderingOptions *)options
                                       callback:(nonnull IMImojiSessionMSStickerResponseCallback)callback {
#if IMMessagesFrameworkSupported
    if (!NSClassFromString(@"MSSticker")) {
        [[NSException exceptionWithName:@"imoji runtime exception"
                                 reason:@"MSSticker rendering only supported with iOS 10 SDK and higher"
                               userInfo:nil] raise];

        return self.cancellationTokenOperation;
    }

    __block NSURL *url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@-%@.%@",
                                                                   NSTemporaryDirectory(),
                                                                   imoji.identifier,
                                                                   @(options.hash),
                                                                   imoji.supportsAnimation ? @"gif" : @"png"
    ]];
    __block void (^stickerCallback)() = ^{
        NSError *stickerError;
        MSSticker *sticker = [[MSSticker alloc] initWithContentsOfFileURL:url
                                                     localizedDescription:imoji.identifier
                                                                    error:&stickerError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (stickerError) {
                callback(nil, stickerError);
            } else {
                callback(sticker, nil);
            }
        });
    };

    if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        [BFTask im_concurrentBackgroundTaskWithBlock:^id(BFTask *task) {
            stickerCallback();
            return nil;
        }];
        
        return self.cancellationTokenOperation;
    }


    return [self renderImojiForExport:imoji
                              options:options
                             callback:^(UIImage *image, NSData *data, NSString *typeIdentifier, NSError *error) {
                                 [BFTask im_concurrentBackgroundTaskWithBlock:^id(BFTask *task) {
                                     if (error) {
                                         callback(nil, error);
                                     } else {
                                         [data writeToURL:url atomically:YES];
                                         stickerCallback();
                                     }
                                     
                                     return nil;
                                 }];
                             }];
#else
    [[NSException exceptionWithName:@"imoji runtime exception"
                            reason:@"MSSticker rendering only supported with iOS 10 SDK and higher"
                          userInfo:nil] raise];
    
    return self.cancellationTokenOperation;
#endif
}

- (void)renderImoji:(IMMutableImojiObject *)imoji
            options:(IMImojiObjectRenderingOptions *)options
           callback:(IMImojiSessionImojiRenderResponseCallback)callback
  cancellationToken:(NSOperation *)cancellationToken {

    IMImojiObjectRenderingOptions *requestedRenderingOptions = options;
    if (imoji.supportsAnimation && options.renderAnimatedIfSupported) {
        requestedRenderingOptions = [imoji supportedAnimatedRenderingOptionFromOption:options];
    }

    [[self downloadImojiContents:imoji
                 renderingOtions:requestedRenderingOptions
               cancellationToken:cancellationToken]
            continueWithBlock:^id(BFTask *task) {
                if (cancellationToken.cancelled) {
                    return [BFTask cancelledTask];
                }

                if (task.error) {
                    callback(nil, task.error);
                } else {
                    callback(task.result, nil);
                }

                return nil;
            }];
}

#pragma mark Static

+ (NSDictionary *)categoryClassifications {
    static NSDictionary *categoryClassifications = nil;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        categoryClassifications = @{
                @(IMImojiSessionCategoryClassificationTrending) : @"trending",
                @(IMImojiSessionCategoryClassificationGeneric) : @"generic",
                @(IMImojiSessionCategoryClassificationArtist) : @"artist",
                @(IMImojiSessionCategoryClassificationNone) : @"none"
        };
    });

    return categoryClassifications;
}

#pragma mark Initializers

+ (instancetype)imojiSession {
    return [[IMImojiSession alloc] init];
}

+ (instancetype)imojiSessionWithStoragePolicy:(IMImojiSessionStoragePolicy *)storagePolicy {
    return [[IMImojiSession alloc] initWithStoragePolicy:storagePolicy];
}

@end
