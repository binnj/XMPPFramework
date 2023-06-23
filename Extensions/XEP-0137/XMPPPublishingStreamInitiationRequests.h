//
//  XMPPPublishingStreamInitiationRequests.h
//  Dollarama
//
//  Created by binnj, inc. on 2017-02-03.
//  Copyright © 2017 binnj, inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPP.h"

typedef enum {
    XMPPPublishingSIRequestsStateNone,
    XMPPPublishingSIRequestsStateSending,
    XMPPPublishingSIRequestsStateReceiving
} XMPPPublishingSIRequestsState;

@interface XMPPPublishingStreamInitiationRequests : XMPPModule {
    XMPPPublishingSIRequestsState state;
    NSMutableData *receivedData;
    XMPPJID *senderJID;
    XMPPJID *receiverJID;
}

/**
 * We need to keep track of the sid (the id of the <sipub> element. When a negotation is received,
 * we will either receive a set iq or send a set iq with a particular sid.  This sid is used
 * again when the file is sent or received, and must match.
 **/
@property (nonatomic, strong) NSString *sid;

@end
