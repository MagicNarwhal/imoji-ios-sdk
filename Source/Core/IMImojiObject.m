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

#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
#import "IMImojiObject.h"

@implementation IMImojiObject {

}

- (BOOL)isEqual:(id)other {
    if (other == self)
        return YES;
    if (!other || ![[other class] isEqual:[self class]])
        return NO;

    return [self isEqualToObject:other];
}

- (BOOL)isEqualToObject:(IMImojiObject *)object {
    if (self == object)
        return YES;
    if (object == nil)
        return NO;
    if (self.identifier != object.identifier && ![self.identifier isEqualToString:object.identifier])
        return NO;
    return YES;
}

- (NSUInteger)hash {
    return [self.identifier hash];
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
    [description appendFormat:@"self.identifier=%@", self.identifier];
    [description appendString:@">"];
    return description;
}

- (nullable NSURL *)getUrlForRenderingOptions:(nonnull IMImojiObjectRenderingOptions *)renderingOptions {
    id url = self.urls[renderingOptions];

    if (url && [url isKindOfClass:[NSURL class]]) {
        return url;
    }

    return nil;
}

@end
