//
//  XMPPHttpFileUploadObject.h
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-23.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface XMPPHttpFileUploadObject : NSObject

@property (nonatomic,strong) NSString* recipientJid;
@property (nonatomic,strong) NSString* fileName;
@property (nonatomic) long fileSize;
@property (nonatomic,strong) NSData* fileData;
@property (nonatomic,strong) NSString* contentType;
@property (nonatomic,strong) NSURL* getURL;
@property (nonatomic,strong) NSURL* putURL;
@property (nonatomic) int status;

@end
