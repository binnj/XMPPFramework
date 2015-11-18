//
//  XMPPHttpFileUpload.h
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-18.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import "XMPP.h"
#import "XMPPIDTracker.h"

@class XMPPIDTracker;

/**
 *This class provide support for protocol to request permissions from another entity to upload a file to a specific path on an HTTP server and at the same time receive a URL from which that file can later be downloaded again.
 * The functionality is formalized in XEP-0363.
 **/
@interface XMPPHttpFileUpload : XMPPModule
{
    XMPPIDTracker *xmppIDTracker;
}

@property (readonly,strong) NSURL* putURL;
@property (readonly,strong) NSURL* getURL;

/**
 * This method will attempt to discover existing services for the domain found in xmppStream.myJID.
 *
 * @see xmppMUC:didDiscoverServices:
 * @see xmppMUCFailedToDiscoverServices:withError:
 */
- (void)requestFileUpload:(NSString*)fileName fileSize:(long)fileSize contentType:(NSString*)contentType;
@end
