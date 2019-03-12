//
//  XMPPHttpFileUploadObject.h
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-23.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import <Foundation/Foundation.h>

// XMPP Incoming File Upload State
typedef NS_ENUM(int, XMPPHttpFileUploadStatus) {
    XMPPHttpFileUploadStatusNone,
    XMPPHttpFileUploadStatusServiceRequestedSent,
    XMPPHttpFileUploadStatusServiceRequested,
    XMPPHttpFileUploadStatusHasService,
    XMPPHttpFileUploadStatusNoService,
    XMPPHttpFileUploadStatusUploadServiceRequestedSent,
    XMPPHttpFileUploadStatusUploadServiceRequested,
    XMPPHttpFileUploadStatusHasUploadService,
    XMPPHttpFileUploadStatusNoUploadService,
    XMPPHttpFileUploadStatusUploadSlotRequestedSent,
    XMPPHttpFileUploadStatusUploadSlotRequested,
    XMPPHttpFileUploadStatusNoUploadSlot,
    XMPPHttpFileUploadStatusCompleted
};

@interface XMPPHttpFileUploadObject : NSObject

@property (nonatomic,strong) NSString* recipientJid;
@property (nonatomic,strong) NSString* uploadInfo;
@property (nonatomic,strong) NSString* fileName;
@property (nonatomic) long fileSize;
@property (nonatomic,strong) NSData* fileData;
@property (nonatomic,strong) NSString* contentType;
@property (nonatomic,strong) NSURL* getURL;
@property (nonatomic,strong) NSURL* putURL;
@property (nonatomic) XMPPHttpFileUploadStatus status;


@end
