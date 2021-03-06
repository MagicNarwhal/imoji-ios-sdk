//
//  ImojiSDK
//
//  Created by Alex Hoang
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

#import "IMCategoryAttribution.h"
#import "IMArtist.h"

@implementation IMCategoryAttribution

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _identifier = [coder decodeObjectForKey:@"identifier"];
        _URL = [coder decodeObjectForKey:@"URL"];
        _artist = [coder decodeObjectForKey:@"artist"];
        self.urlCategory = (IMAttributionURLCategory) [coder decodeIntegerForKey:@"urlCategory"];
        self.relatedTags = [coder decodeObjectForKey:@"relatedTags"];
        self.licenseStyle = (IMImojiObjectLicenseStyle) [coder decodeIntegerForKey:@"licenseStyle"];
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.identifier forKey:@"identifier"];
    [coder encodeObject:self.artist forKey:@"artist"];
    [coder encodeObject:self.URL forKey:@"URL"];
    [coder encodeInteger:self.urlCategory forKey:@"urlCategory"];
    [coder encodeObject:self.relatedTags forKey:@"relatedTags"];
    [coder encodeInteger:self.licenseStyle forKey:@"licenseStyle"];
}

- (BOOL)isEqual:(id)other {
    if (other == self)
        return YES;
    if (!other || ![[other class] isEqual:[self class]])
        return NO;
    
    return [self isEqualToObject:other];
}

- (BOOL)isEqualToObject:(IMCategoryAttribution *)object {
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

@end
