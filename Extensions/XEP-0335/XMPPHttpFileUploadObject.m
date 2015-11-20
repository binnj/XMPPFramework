//
//  XMPPHttpFileUploadObject.m
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-19.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import "XMPPHttpFileUploadObject.h"

@implementation XMPPHttpFileUploadObject

@dynamic fileName;
@dynamic fileSize;
@dynamic contentType;
@dynamic putURL;
@dynamic getURL;

- (void) setContentType:(NSString *)contentType
{
    self.contentType = contentType;
}

- (void) setFileName:(NSString *)fileName
{
    self.fileName = fileName;
}

- (void) setFileSize:(long)fileSize
{
    self.fileSize = fileSize;
}

- (void) setGetURL:(NSURL *)getURL
{
    self.getURL = getURL;
}

- (void) setPutURL:(NSURL *)putURL
{
    self.putURL = putURL;
}

@end
