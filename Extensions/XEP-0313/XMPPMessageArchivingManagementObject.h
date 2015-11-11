//
//  XMPPMessageArchivingManagementObject.h
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-11.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPP.h"

@interface XMPPMessageArchivingManagementObject : NSObject

@property (nonatomic, strong) XMPPMessage * message;
@property (nonatomic, strong) NSString * messageStr;

@property (nonatomic, strong) NSString * messageId;

@property (nonatomic, strong) XMPPJID * fromBareJid;
@property (nonatomic, strong) NSString * fromBareJidStr;

@property (nonatomic, strong) XMPPJID * toBareJid;
@property (nonatomic, strong) NSString * toBareJidStr;

@property (nonatomic, strong) NSString * body;

@property (nonatomic, strong) NSDate * timestamp;

@end
