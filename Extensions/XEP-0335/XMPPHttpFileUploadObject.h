//
//  XMPPHttpFileUploadObject.h
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-19.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface XMPPHttpFileUploadObject : NSObject

@property (nonatomic,strong) NSString* fileName;
@property (nonatomic) long fileSize;
@property (nonatomic,strong) NSString* contentType;
@property (nonatomic,strong) NSURL* getURL;
@property (nonatomic,strong) NSURL* putURL;

@end
