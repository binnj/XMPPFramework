//
//  XMPPPushNotification.h
//  supDawg
//
//  Created by 8707839 CANADA INC. on 2016-02-11.
//  Copyright © 8707839 CANADA INC. All rights reserved.
//

#import "XMPPModule.h"
#import "XMPP.h"

/**
 *The purpose of push notifications is to inform users of new messages or other pertinent information even when they have no XMPP clients online.
 
 Typically, these notifications are delivered to a user's mobile device, displaying a notice that can trigger opening an XMPP client to continue a conversation or answer a Jingle session request.
 **/

@interface XMPPPushNotification : XMPPModule

- (void) enablePushNotification;

- (void)getServerConfigurationForPushNotifications;
- (void)setServerConfigurationForPushNotification;

- (void)registerPushNotificationForDeviceToken:(NSString*)deviceToken deviceName:(NSString*)deviceName;
- (void)unregisterPushNotificationForDeviceToken:(NSString*)deviceToken deviceName:(NSString*)deviceName;

- (NSArray*)getRegisteredDeviceList;

@end
