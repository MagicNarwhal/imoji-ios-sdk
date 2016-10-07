# Imoji SDK Changes

### Version 2.3.4

* Adds hooks for developers to publish demographic information for campaigns.

### Version 2.3.3

* NSURLSessionConfiguration for IMImojiSession now uses defaultSessionConfiguration over ephemeralSessionConfiguration.
* Fixed a bug in which archiving mutable versions of IMImojiObject's, IMArtist's or IMCategoryAttribution's would double encode the property values.

### Version 2.3.2

* Adds new object type IMImojiImageReference.
* Adds new argument contributingImojiId to method searchImojisWithTerm. When contributingImojiId is not nil, the server returns a set of imojis with the contributing imoji as the first result.
* Deprecated searchImojisWithTerm without the contributingImojiId argument. It is still supported.
* Support reading local webp stored images.
* Support falling back to smaller sizes if the requested Rendering Option size is unavailable.
* Support falling back to PNG if WebP Rendering Option image format is unavailable.
* Allow for specifying maximum file size for downloaded Imoji stickers.
* Avoid downloading the image if the file size is larger than what the server will send.

### Version 2.3.1

* Expose initWithCachePath:persistentPath: in IMImojiSessionStoragePolicy for overriding
* Fixes #18 - Adds core headers that were missing in ImojiSDK.h

### Version 2.3.0

* Adds support for rendering Imoji stickers as MSStickers for iOS 10! See [https://developer.apple.com/reference/messages/mssticker](https://developer.apple.com/reference/messages/mssticker)
* Addresses an issue with exporting non gif images as PNG
* Make sure renderAnimatedIfSupported is set to true for [IMImojiObjectRenderingOptions optionsWithAnimationAndRenderSize]

### Version 2.2.1

* Adds **relatedCategories** to search results. Clients can use this to show multiple related terms instead of just one (relatedSearchTerm).
* For developers using targetSize or aspectRatio, we're now processing the resize request on the server to avoid having the client do too much work. As a result, your app will not have to worry about memory issues when creating for example, a resized animated image. 
* Removes deprecated methods reportImojiAsAbusive and markImojiUsage
* Removes deprecated contentCache
* Fixes a bug in which some animated gifs where exporting with animation speeds that were too fast.

### Version 2.2.0

* Adds **licenseStyle** metadata to CategoryAttribution and Imoji objects. Developers can use this to determine which content can or cannot be used for commerical purposes (arrangements need to be made with Imoji prior to integrating)
* Deprecate reportImojiAsAbusive and markImojiUsage in favor of reportImojiAsAbusiveWithIdentifier and markImojiUsageWithIdentifier.
* Removes Sync subspec, functionality is no longer supported
* Ability to filter categories by license styles

### Version 2.1.1

* Adds the ability to get attribution for an individual Imoji object
* Expands attribution and adds url category (either video, twitter, instagram, etc)
* Adds the ability for developers to send contextual search phrases to category fetching in order to retrieve results relevant to the search phrase
* Deprecated fetchRenderingOptions because it is no longer being used.
* Bring in webp depedency from YYImage

### Version 2.1.0

* Adds analytics endpoints for tracking when an Imoji sticker was used by the user. This helps us adjust the weighting of the content in search results appropriately.
* Brings in YYImage as a pod dependency. Developers should now import their YYImage rom YYImage rather than ImojiSDK.

### Version 2.0.6

* Adopt new server version of 2.1.0 which will send down a more unified JSON result set for images
* Expose image dimensions and file sizes in IMImojiObject

### Version 2.0.5

* Guarded imoji upload task to handle nil values returned from image resizing.

### Version 2.0.4

* Add a new render method for getting exportable NSData contents of an Imoji image. Ensures that only safe formats like PNG and GIF data are sent back to the user.
* Documentation updates.

### Version 2.0.3

* Fixes issue with webp images not loading in Swift.
* Image download and API NSURLSession tasks switched to data tasks to trigger NSURLCaching. 
* Increased NSURLCache size to 15MB.

### Version 2.0.2

* Using YYImages for rendering animated and non-animated stickers. Users can use YYAnimatedImageView to display the animated contents or any other framework they like. See [http://cocoadocs.org/docsets/YYImage/0.9.2/Classes/YYImage.html](http://cocoadocs.org/docsets/YYImage/0.9.2/Classes/YYImage.html) for more info.
* Animated WebP support for new animated stickers.

### Version 2.0.1

* Animated GIF support :D 
  * Loads in animated content into UIImage's automatically if the Imoji is animated. 
  * Animated UIImages are automatically displayed in UIImageViews.
* API Change: IMImojiSessionResultSetResponseCallback now have a metadata parameter which will contain specifics related to the search made. Result count has been incorporated into that object now instead of being passed by itself.
* Ensure that access tokens get regenerated when fetching a refresh token fails or when the developer changes their client ID
* Avoid using a local disk cache managed by the storage policy and use an NSURLCache instead

### Version 2.0.0

* Adds artist categories to the Imoji SDK! Artist categories can be fetched by sending over IMImojiSessionCategoryClassificationArtist to category fetches. Proper attribution for artist content should be displayed when displaying (see examples in the ImojiSDKUI pod).
* Use proper semantic versioning for ImojiSDK and ImojiSDKUI

### Version 0.2.18

* Updates Imoji creation to trigger a callback when the image has begun uploading and once it has completed uploading. A local only version is created when first triggering the upload and is replaced by the persistent one when uppload completes.

### Version 0.2.17

* Expands IMImojiObject urls property to include both webp and png images as well bordered and unbordered ones. The keys to the urls property is now an IMImojiObjectRenderingOptions object.
* Exposes fetchRenderingOptions which can be set to override the style of images downloaded for any of the fetch requests (ex: searchImojisWithTerm, getFeaturedImojisWithNumberOfResults, etc)

### Version 0.2.16

* Fixes a bug in which the IMIMojiObject returned after creating an Imoji wasn't rendering properly

### Version 0.2.15

* Reads session credentials synchronously upon creation of IMImojiSession to avoid running into cases where callers want to immediately make API calls after session creation
* Minor warning fix IMImojiSession+Sync

### Version 0.2.14

* Addresses crash that occurs when sending nil to searchImojisWithTerm

### Version 0.2.13

* IMImojiSession clearUserSynchronizationStatus callback is actually nullable (thanks @benpious!)
* Bug fix for uploading Imoji images, we were calling the wrong NSURLSession method

### Version 0.2.12

* Adds the following 
  * Adds nonnull nullable annotations to all headers
  * Addresses an error while using BFTask taskFromExecutor from Bolts 1.3
  
### Version 0.2.11

* Adds the following 
  * Sentence parsing - Just send up a full sentence and Imoji will find relevant content :D
  * Creation and Deletion of Imojis - To be used in conjunction with the ImojiSDKUI editor, you can now upload user generated stickers!
  * Flagging Imojis - Add the ability for users to flag Imoji content within your app. Our review team goes through flagged content to make the appropriate action.

### Version 0.2.10

* Adds support for opening Imoji authentication URL's with web links for iOS 9


### Version 0.2.9

* Addresses issue with fetchImojisByIdentifier not properly loading. The results were not being read properly from the server.


### Version 0.2.8

* Split out Imoji User Authentication Code to a separate Pod subspec. Our authentication portion requires app linking to work, which does not play nicely with WatchKit or Keyboard extensions. Add **pod 'ImojiSDK/Core'** to your Podfile to avoid grabbing the authentication code.


### Version 0.2.5

* Open Sources ImojiSDK!
* Consume Imoji images from our [REST API](https://github.com/imojiengineering/imoji-rest-api)



### Version 0.1.21

* Improved performance for rendering imoji images on the simulator
* Convenience initializers for IMImojiObjectRenderingOptions for displaying borderless, shadowless or border and shadowless images
* Ability to send in a content cache object to IMImojiSession to prevent unnecessary rendering operations
* Updated Readme for developers having trouble linking with Bolts for their extension


### Version 0.1.20

* Addresses memory leak issue with border rendering

### Version 0.1.19

* New border rendering mechanism! smoother corners and subtle drop shadows will help make the imojis look better than before.
* Please note that we've now shifted to using OpenGL to render the borders, which will appear slower than the previous mechanism on the simulator. On the device, performance and memory usage is inline with the old method.

### Version 0.1.18

* Addresses issues with user sync status not being read properly upon creation of IMImojiSession

### Version 0.1.17

* Addresses issues with reachability code within IMImojiSession

### Version 0.1.16

* Adds the ability for sdk clients to add imojis to a users account, this is useful for applications that wish to use the users account for synchronizing favorited/liked Imoji's

### Version 0.1.15

* Sets deployment target to iOS 6.0

### Version 0.1.14

* Improved performence for maximumRenderingSize, re-sizes the target image prior to rendering border and shadow instead of afterwards.
* imoji images are automatically removed from file cache after one day of no use to prevent massive buildup of assets prior to the operating system removing them

### Version 0.1.13

* Adds support for maximumRenderingSize. This can be used in conjunction with aspect ratio to curb the growth of the rendered imoji image.

### Version 0.1.12

* Adds category classification parameter to getImojiCategories

### Version 0.1.11

* Addresses issues with session state not being properly persisted on cold app starts
* Fixes inadvertent error returned for getImojisForAuthenticatedUserWithResultSetResponseCallback when the user does not have any imojis

### Version 0.1.10

* Addresses issues with api clients not being able to properly write to storage policy paths
* Documentation updates

### Version 0.1.9

* Allows for specifying storage paths for assets and persistent data

### Version 0.1.8

* Addresses issue with user syncing not working

### Version 0.1.7

* Remove iOS webp and AFNetworking dependencies
* Add aspect ratio setting to rendering options
* Add ability to clear synchronized user information

### Version 0.1.6

* Introduces ability to synchronize a session with a user account created with imoji. This allows SDK users to populated images created by that user into their application
* Introduces sessionState property to IMImojiSession. The state describes whether or not the user is connected and or synchronized with a user account.
* Adds methods for SDK users to add to UIApplicationDelegate to properly close the loop with user synchronization
* Renames searchResponseCallback parameters to resultSetResponseCallback for clarity
* Adds helper methods for downloading the Imoji application.

### Version 0.1.5

* Adds shadow offset
* Removes cocoa lumberjack dependency
* Removes path from session storage
* Better error checking for imoji rendering

### Version 0.1.4

Consolidate all rendering methods to one method with options parameter
Render imoji objects serially rather than concurrently
Shadow blur % and color are now exposed for rendering
Both shadow and border sizes are now specified as % of the images max width or height. This helps achieve consistency between varying Imoji images.

### Version 0.1.3

* Adds documentation for IMImojiSession error codes, different imoji rendering quality settings, IMImojiObject and IMImojiCategoryObject
* Modifies order and priority to be native NSUInteger values rather than NSNumber's for IMImojiCategoryObject
* Removes support for custom IMImojiSessionStoragePolicy paths
* Adds support for fetching IMImojiObject's from identifiers (IMImojiSession fetchImojisByIdentifiers:fetchedResponseCallback)

### Version 0.1.2

* Expand render methods to encapsulate both downloading and rendering the imoji images
* Add asynchronous callback function to the render methods that are called once the image is ready or an error had occurred
* Have render methods return an NSOperation instance which callers can use to cancel the request if need be

### Version 0.1.1

* Documentation Updates

### Version 0.1.0

* It all begins here :D 



