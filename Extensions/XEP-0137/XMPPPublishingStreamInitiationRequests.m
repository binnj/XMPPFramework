//
//  XMPPPublishingStreamInitiationRequests.m
//  Mortgage
//
//  Created by binnj, inc. on 2017-02-03.
//  Copyright © 2017 binnj, inc. All rights reserved.
//

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#import "XMPPPublishingStreamInitiationRequests.h"
#import "XMPPLogging.h"

#if DEBUG
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN; // | XMPP_LOG_FLAG_TRACE;
#else
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

@interface XMPPPublishingStreamInitiationRequests()
@property (nonatomic, readwrite) NSUInteger recvFileSize;
@property (nonatomic, readwrite) NSUInteger sendFileSize;
@property (nonatomic, strong) NSData *fileToSend;
@property (nonatomic, strong) NSString *fileRecipient;
@end

@implementation XMPPPublishingStreamInitiationRequests
@synthesize sid;
@synthesize recvFileSize;
@synthesize fileToSend;

- (id)init {
    return [self initWithDispatchQueue:NULL];
}

- (id)initWithDispatchQueue:(dispatch_queue_t)queue {
    if ((self = [super initWithDispatchQueue:queue])) {
        state = XMPPPublishingSIRequestsStateNone;
        receivedData = [[NSMutableData alloc] init];
    }
    return self;
}

- (BOOL)activate:(XMPPStream *)aXmppStream {
    if ([super activate:aXmppStream]) {
        return YES;
    }
    return NO;
}

- (void)deactivate {
    XMPPLogTrace();
    
    [super deactivate];
}


#pragma mark XMPPStream Delegate
/**
 <iq type='result'
 id='sipub-request-0'
 from='romeo@montague.net/pda'
 to='juliet@capulet.com/balcony'>
 <starting xmlns='http://jabber.org/protocol/sipub'
 sid='session-87651234'/>
 </iq>
 **/
- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)inIq
{
    NSString *type = [inIq type];
    if ([@"set" isEqualToString:type]) {
    }
    else if ([@"result" isEqualToString:type]) {
        NSXMLElement *starting = [inIq elementForName:@"starting"];
        if (starting != nil) {
            if ([@"http://jabber.org/protocol/sipub" isEqualToString:[starting xmlns]]) {
                //
            }
        }
    }
    
    return NO;
}


- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message {
    // imessage file transfer format
    NSXMLElement *x = [message elementForName:@"x"];
    if (x != nil) {
        NSXMLElement *attachment = [x elementForName:@"attachment"];
        if (attachment != nil) {
            NSXMLElement *sipub = [attachment elementForName:@"sipub"];
            if (sipub != nil) {
                if (sipub != nil) {
                    if ([@"http://jabber.org/protocol/sipub" isEqualToString:[sipub xmlns]]) {
                        NSXMLElement *file = [sipub elementForName:@"file"];
                        if ([@"http://jabber.org/protocol/si/profile/file-transfer" isEqualToString:[file xmlns]]) {
                            // sid is an important value, which will be used throughtout.
                            // It will be referred back to by other IQs involving file tranfers.
                            sid = [[sipub attributeForName:@"id"] stringValue];
                            recvFileSize = (NSUInteger)[[[file attributeForName:@"size"] stringValue] integerValue];
                            senderJID = [message from];
                            receiverJID = [message to];
                            
                            // Triggering the Stream Initiation Request
                            [self sendStreamStartRequest];
                            
                        }
                    }
                }
            }
        }
    }
}

/*
 <iq type='get'
 id='sipub-request-0'
 from='juliet@capulet.com/balcony'
 to='romeo@montague.net/pda'>
 <start xmlns='http://jabber.org/protocol/sipub'
 id='publish-0123'/>
 </iq>
 */
- (void)sendStreamStartRequest {
    
    NSString *uuid = [xmppStream generateUUID];
    NSXMLElement *child = [NSXMLElement elementWithName:@"start" xmlns:@"http://jabber.org/protocol/sipub"];
    [child addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:sid]];

    XMPPIQ *iq = [XMPPIQ iqWithType:@"get" elementID:uuid child:child];
    [iq addAttributeWithName:@"to" stringValue:[senderJID full]];
    [iq addAttributeWithName:@"from" stringValue:[[xmppStream myJID] full]];
    [xmppStream sendElement:iq];
}

@end
