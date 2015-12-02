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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import "IMImojiObjectRenderingOptions.h"

@class IMImojiObject, IMImojiSessionStoragePolicy;
@protocol IMImojiSessionDelegate;

/**
* @abstract The error domain used within NSError objects generated by IMImojiSession
*/
extern NSString *__nonnull const IMImojiSessionErrorDomain;

/**
* @abstract Error codes used by errors returned within IMImojiSession
*/
typedef NS_ENUM(NSUInteger, IMImojiSessionState) {
    /**
    * @abstract The session is not currently connected with the imoji server
    */
            IMImojiSessionStateNotConnected,

    /**
    * @abstract The session is connected with the server but not synchronized with a user account
    */
            IMImojiSessionStateConnected,

    /**
    * @abstract The session is connected with the server and synchronized with a user account
    */
            IMImojiSessionStateConnectedSynchronized
};

/**
* @abstract Error codes used by errors returned within IMImojiSession
*/
typedef NS_ENUM(NSUInteger, IMImojiSessionErrorCode) {
    /**
    * @abstract Used when the supplied client id and api token are not recognized by the server
    */
            IMImojiSessionErrorCodeInvalidCredentials,
    /**
    * @abstract Used as a fallback when the server returns an error and no other specific error code exists
    */
            IMImojiSessionErrorCodeServerError,
    /**
    * @abstract Used when the consumer supplies a corrupt IMImojiObject to IMImojiSession for rendering
    */
            IMImojiSessionErrorCodeImojiDoesNotExist,
    /**
    * @abstract Used whenever the consumer sends a bad argument to any method in IMImojiSession
    */
            IMImojiSessionErrorCodeInvalidArgument,
    /**
    * @abstract Used when IMImojiSession is unable to render the IMImojiObject to a UIImage
    */
            IMImojiSessionErrorCodeInvalidImage,
    /**
    * @abstract Used when IMImojiSession is unable to fetch a users set of imojis because the session is not synchronized
    */
            IMImojiSessionErrorCodeSessionNotSynchronized,
    /**
    * @abstract Used when IMImojiSession is unable to authenticate a session with a user
    */
            IMImojiSessionErrorCodeUserAuthenticationFailed,
    /**
    * @abstract Used when IMImojiSession is unable to carry a request because the Imoji application is not installed
    */
            IMImojiSessionErrorCodeImojiApplicationNotInstalled,
    /**
    * @abstract Used when IMImojiSession is unable to render the IMImojiObject
    */
            IMImojiSessionErrorCodeImojiRenderingUnavailable
};

/**
* @abstract Defines a high level grouping of category types
*/
typedef NS_ENUM(NSUInteger, IMImojiSessionCategoryClassification) {
    /**
    * @abstract Allows for the caller to obtain all trending and time sensitive categories
    * (ex: sporting events, holidays, etc).
    */
            IMImojiSessionCategoryClassificationTrending,

    /**
    * @abstract Allows for the caller to obtain categories of imojis that are not time sensitive
    * (ex: emotions, locations, people, etc).
    */
            IMImojiSessionCategoryClassificationGeneric,

    /**
    * @abstract Allows for the caller to obtain all categories containing artist content
    */

            IMImojiSessionCategoryClassificationArtist,

    /**
     * @abstract Allows for the caller to obtain all categories.
     */
            IMImojiSessionCategoryClassificationNone
};

/**
* @abstract Callback used for triggering when the server has loaded a result set
* @param resultCount Number of results returned by the server. This can never be nil.
* @param followUpSearchTerm A string representing a relevant search term for lookup. Value is nil when resultCount is 0.
* @param error An error with code equal to an IMImojiSessionErrorCode value or nil if the request succeeded
*/
typedef void (^IMImojiSessionResultSetResponseCallback)(NSNumber *__nullable resultCount, NSString *__nullable followUpSearchTerm, NSError *__nullable error);

/**
* @abstract Callback used for generic asynchronous requests
* @param imoji The fetched IMImojiObject
* @param index Position in the results set the imoji belongs to
* @param error An error with code equal to an IMImojiSessionErrorCode value or nil if the request succeeded
*/
typedef void (^IMImojiSessionImojiFetchedResponseCallback)(IMImojiObject *__nullable imoji, NSUInteger index, NSError *__nullable error);

/**
* @abstract Callback used for generic asynchronous requests
* @param imojiCategories An array of IMImojiCategoryObject's
* @param error An error with code equal to an IMImojiSessionErrorCode value or nil if the request succeeded
*/
typedef void (^IMImojiSessionImojiCategoriesResponseCallback)(NSArray *__nullable imojiCategories, NSError *__nullable error);

/**
* @abstract Callback triggered when an imoji has been rendered as an UIImage
* @param image UIImage representation of the IMImojiObject
* @param error An error with code equal to an IMImojiSessionErrorCode value or nil if the request succeeded
*/
typedef void (^IMImojiSessionImojiRenderResponseCallback)(UIImage *__nullable image, NSError *__nullable error);

/**
* @abstract Callback used for generic asynchronous requests
* @param successful Whether or not the operation succeed
* @param error An error with code equal to an IMImojiSessionErrorCode value or nil if the request succeeded
*/
typedef void (^IMImojiSessionAsyncResponseCallback)(BOOL successful, NSError *__nullable error);

/**
* @abstract Callback used for creating new Imojis
* @param imoji Reference to the newly created Imoji, nil if an error occurred
* @param error An error with code equal to an IMImojiSessionErrorCode value or nil if the request succeeded
*/
typedef void (^IMImojiSessionCreationResponseCallback)(IMImojiObject *__nullable imoji, NSError *__nullable error);

@interface IMImojiSession : NSObject {
    IMImojiSessionState _sessionState;
}

/**
* @abstract Creates a imoji session object.
* @param storagePolicy The storage policy to use for persisting imojis.
*/
- (nonnull instancetype)initWithStoragePolicy:(nonnull IMImojiSessionStoragePolicy *)storagePolicy;

/**
* @abstract Creates a imoji session object with a default temporary file system storage policy.
*/
+ (nonnull instancetype)imojiSession;

/**
* @abstract Creates a imoji session object.
* @param storagePolicy The storage policy to use for persisting imojis.
*/
+ (nonnull instancetype)imojiSessionWithStoragePolicy:(nonnull IMImojiSessionStoragePolicy *)storagePolicy;

/**
* @abstract The current state of the session
*/
@property(readonly) IMImojiSessionState sessionState;

/**
* @abstract An optional session delegate to receive notifications when session information changes
*/
@property(nonatomic, strong, nullable) id <IMImojiSessionDelegate> delegate;

/**
* @abstract An optional cache instance to be used for optimizing rendering calls
*/
@property(nonatomic, strong, nullable) NSCache *contentCache;

/**
 * @abstract The storage policy used for determining how to store Imojis on the local file store.
 */
@property(nonatomic, readonly, nonnull) IMImojiSessionStoragePolicy *storagePolicy;

/**
 * @abstract The default rendering options that are used to render Imoji's in IMImojiSessionImojiFetchedResponseCallback.
 */
@property(nonatomic, nonnull) IMImojiObjectRenderingOptions *fetchRenderingOptions;

@end

/**
* @abstract Main session object for making requests that require server access with the Imoji server.
*/
@interface IMImojiSession (ImojiFetching)

/**
* @abstract Fetches top level imoji categories given a classification type.
* @param classification Type of category classification to retrieve
* @param callback Block callback to call when categories have been downloaded.
* @return An operation reference that can be used to cancel the request.
*/
- (nonnull NSOperation *)getImojiCategoriesWithClassification:(IMImojiSessionCategoryClassification)classification
                                                     callback:(nonnull IMImojiSessionImojiCategoriesResponseCallback)callback;

/**
* @abstract Searches the imojis database with a given search term. The resultSetResponseCallback block is called once the results are available.
* Imoji contents are downloaded individually and imojiResponseCallback is called once the thumbnail of that imoji has been downloaded.
* @param searchTerm Search term to find imojis with. If nil or empty, the server will typically returned the featured set of imojis (this is subject to change).
* @param offset The result offset from a previous search. This may be nil.
* @param numberOfResults Number of results to fetch. This can be nil.
* @param resultSetResponseCallback Callback triggered when the search results are available or if an error occurred.
* @param imojiResponseCallback Callback triggered when an imoji is available to render.
* @return An operation reference that can be used to cancel the request.
*/
- (nonnull NSOperation *)searchImojisWithTerm:(nullable NSString *)searchTerm
                                       offset:(nullable NSNumber *)offset
                              numberOfResults:(nullable NSNumber *)numberOfResults
                    resultSetResponseCallback:(nonnull IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                        imojiResponseCallback:(nonnull IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback;

/**
* @abstract Gets a random set of featured imojis. The resultSetResponseCallback block is called once the results are available.
* Imoji contents are downloaded individually and imojiResponseCallback is called once the thumbnail of that imoji has been downloaded.
* @param numberOfResults Number of results to fetch. This can be nil.
* @param resultSetResponseCallback Callback triggered when the featured results are available or if an error occurred.
* @param imojiResponseCallback Callback triggered when an imoji is available to render.
* @return An operation reference that can be used to cancel the request.
*/
- (nonnull NSOperation *)getFeaturedImojisWithNumberOfResults:(nullable NSNumber *)numberOfResults
                                    resultSetResponseCallback:(nonnull IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                                        imojiResponseCallback:(nonnull IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback;

/**
* @abstract Gets corresponding IMImojiObject's for one or more imoji identifiers as NSString's
* Imoji contents are downloaded individually and fetchedResponseCallback is called once the thumbnail of that imoji has been downloaded.
* @param imojiObjectIdentifiers An array of NSString's representing the identifiers of the imojis to fetch
* @param fetchedResponseCallback Callback triggered when an imoji is available to render
* @return An operation reference that can be used to cancel the request.
*/
- (nonnull NSOperation *)fetchImojisByIdentifiers:(nonnull NSArray *)imojiObjectIdentifiers
                          fetchedResponseCallback:(nonnull IMImojiSessionImojiFetchedResponseCallback)fetchedResponseCallback;

/**
 * @abstract Searches the imojis database with a complete sentence. The service performs keyword parsing to find best matched imojis.
 * @param sentence Full sentence to parse.
 * @param numberOfResults Number of results to fetch. This can be nil.
 * @param resultSetResponseCallback Callback triggered when the search results are available or if an error occurred.
 * @param imojiResponseCallback Callback triggered when an imoji is available to render.
 * @return An operation reference that can be used to cancel the request.
 */
- (nonnull NSOperation *)searchImojisWithSentence:(nonnull NSString *)sentence
                                  numberOfResults:(nullable NSNumber *)numberOfResults
                        resultSetResponseCallback:(nonnull IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                            imojiResponseCallback:(nonnull IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback;

@end


@interface IMImojiSession (ImojiDisplaying)

/**
* @abstract Renders an imoji object into a image with a specified border and shadow.
* The imoji image is scaled to fit the specified target size. This may make a server call depending on the availability
* of the imoji with the session storage policy.
* @param imoji The imoji to render.
* @param options Set of options to render the imoji with
* @param callback Called once the imoji UIImage has been rendered
* @return An operation reference that can be used to cancel the request.
*/
- (nonnull NSOperation *)renderImoji:(nonnull IMImojiObject *)imoji
                             options:(nonnull IMImojiObjectRenderingOptions *)options
                            callback:(nonnull IMImojiSessionImojiRenderResponseCallback)callback;

@end

@interface IMImojiSession (SynchronizedUserActions)

/**
* @abstract Gets imojis associated to the synchronized user account. The sessionState must be IMImojiSessionStateConnectedSynchronized
* in order to receive user imojis.
* @param resultSetResponseCallback Callback triggered when the results are available or if an error occurred.
* @param imojiResponseCallback Callback triggered when an imoji is available to render.
* @return An operation reference that can be used to cancel the request.
*/
- (nonnull NSOperation *)getImojisForAuthenticatedUserWithResultSetResponseCallback:(nonnull IMImojiSessionResultSetResponseCallback)resultSetResponseCallback
                                                              imojiResponseCallback:(nonnull IMImojiSessionImojiFetchedResponseCallback)imojiResponseCallback;

/**
* @abstract Adds a given IMImojiObject to a users collection which is also synchronized with their account.
* The sessionState must be IMImojiSessionStateConnectedSynchronized in order to receive user imojis.
* @param imojiObject The Imoji object to save to the users collection
* @param callback Called once the save operation is complete
* @return An operation reference that can be used to cancel the request.
*/
- (nonnull NSOperation *)addImojiToUserCollection:(nonnull IMImojiObject *)imojiObject
                                         callback:(nonnull IMImojiSessionAsyncResponseCallback)callback;

@end

@interface IMImojiSession (ImojiModification)

/**
 * @abstract Adds an Imoji sticker to the database
 * @param image The Imoji sticker image
 * @param tags An array of NSString tags or nil if there are none
 * @param beginUploadCallback Called once the uploading of the image has started. A temporary Imoji is passed back
 * to the caller which can be used as a filler while the upload is taking place.
 * @param finishUploadCallback Called once the save operation is complete
 * @return An operation reference that can be used to cancel the request.
 */
- (nonnull NSOperation *)createImojiWithRawImage:(nonnull UIImage *)image
                                   borderedImage:(nonnull UIImage *)borderedImage
                                            tags:(nullable NSArray *)tags
                             beginUploadCallback:(nonnull IMImojiSessionCreationResponseCallback)beginUploadCallback
                            finishUploadCallback:(nonnull IMImojiSessionCreationResponseCallback)finishUploadCallback;


/**
 * @abstract Removes an Imoji sticker that was created by the user with createImojiWithImage:tags:callback:
 * @param imojiObject The added Imoji object
 * @param callback Called once the save operation is complete
 * @return An operation reference that can be used to cancel the request.
 */
- (nonnull NSOperation *)removeImoji:(nonnull IMImojiObject *)imojiObject
                            callback:(nonnull IMImojiSessionAsyncResponseCallback)callback;

/**
 * @abstract Reports an Imoji sticker as abusive. You may expose this method in your application in order for users to have the ability to flag
 * content as not appropriate. Reported Imojis are not removed instantly but are reviewed internally before removal.
 * @param imojiObject The Imoji object to report
 * @param reason Optional text describing the reason why the content is being reported
 * @param callback Called once the save operation is complete
 * @return An operation reference that can be used to cancel the request.
 */
- (nonnull NSOperation *)reportImojiAsAbusive:(nonnull IMImojiObject *)imojiObject
                                       reason:(nullable NSString *)reason
                                     callback:(nonnull IMImojiSessionAsyncResponseCallback)callback;

@end

/**
* @abstract Delegate protocol for IMImojiSession
*/
@protocol IMImojiSessionDelegate <NSObject>

@optional

/**
* @abstract Triggered when the session state changes
* @param session The session in use
* @param newState The current state
* @param oldState The previous state
*/
- (void)imojiSession:(nonnull IMImojiSession *)session stateChanged:(IMImojiSessionState)newState fromState:(IMImojiSessionState)oldState;

@end
