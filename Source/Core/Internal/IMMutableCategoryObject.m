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

#import "IMMutableCategoryObject.h"
#import "IMImojiObject.h"
#import "../IMCategoryAttribution.h"


@implementation IMMutableCategoryObject {

}

- (instancetype)initWithIdentifier:(NSString *)identifier
                             order:(NSUInteger)order
                     previewImojis:(NSArray *)previewImojis
                          priority:(NSUInteger)priority
                             title:(NSString *)title
                       attribution:(IMCategoryAttribution *)attribution {
    self = [super init];
    if (self) {
        _identifier = identifier;
        _order = order;
        _previewImojis = previewImojis;
        _priority = priority;
        _title = title;
        _attribution = attribution;
    }

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _identifier = [coder decodeObjectForKey:@"identifier"];
        _title = [coder decodeObjectForKey:@"title"];
        _previewImojis = [coder decodeObjectForKey:@"previewImojis"];
        _order = (NSUInteger) [coder decodeIntegerForKey:@"order"];
        _priority = (NSUInteger) [coder decodeIntegerForKey:@"priority"];
        _attribution = [coder decodeObjectForKey:@"attribution"];
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_identifier forKey:@"identifier"];
    [coder encodeObject:_title forKey:@"title"];
    [coder encodeObject:_previewImojis forKey:@"previewImojis"];
    [coder encodeInteger:_order forKey:@"order"];
    [coder encodeInteger:_priority forKey:@"priority"];
    [coder encodeObject:_attribution forKey:@"attribution"];
}

- (NSString *)identifier {
    return _identifier;
}

- (NSUInteger)order {
    return _order;
}

- (IMImojiObject *)previewImoji {
    return _previewImojis.firstObject;
}

- (NSArray *)previewImojis {
    return _previewImojis;
}

- (NSUInteger)priority {
    return _priority;
}

- (NSString *)title {
    return _title;
}

- (IMCategoryAttribution *)attribution {
    return _attribution;
}

+ (instancetype)objectWithIdentifier:(NSString *)identifier
                               order:(NSUInteger)order
                       previewImojis:(NSArray *)previewImojis
                            priority:(NSUInteger)priority
                               title:(NSString *)title
                         attribution:(IMCategoryAttribution *)attribution {
    return [[self alloc] initWithIdentifier:identifier
                                      order:order
                              previewImojis:previewImojis
                                   priority:priority
                                      title:title
                                attribution:attribution];
}

@end
