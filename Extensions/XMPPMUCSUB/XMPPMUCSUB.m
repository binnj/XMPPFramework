//
//  XMPPMUCSUB.m
//  Dollarama
//
//  Created by Besat Zardosht on 2019-05-15.
//  Copyright © 2019 binnj. All rights reserved.
//
#import "XMPPMUCSUB.h"
#import "XMPPFramework.h"
#import "XMPPLogging.h"
#import "XMPPIDTracker.h"

#if DEBUG
static const int xmppLogLevel = XMPP_LOG_LEVEL_VERBOSE;
#else
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

NSString *const XMPPMUCSUBDiscoInfo = @"http://jabber.org/protocol/disco#info";
NSString *const XMPPMUCSUBErrorDomain = @"XMPPMUCSUBErrorDomain";
NSString *const XMPPMUCSUBNamespace = @"urn:xmpp:mucsub:0";

@interface XMPPMUCSUB()
{
    BOOL hasRequestedFeatures;
    NSMutableDictionary *hasRequestedFeaturesForRoom;
}

@end

@implementation XMPPMUCSUB

- (id)initWithDispatchQueue:(dispatch_queue_t)queue
{
    if ((self = [super initWithDispatchQueue:queue])) {
        rooms = [NSMutableSet new];
        hasRequestedFeaturesForRoom = [NSMutableDictionary new];
    }
    return self;
}

- (BOOL)activate:(XMPPStream *)aXmppStream
{
    if ([super activate:aXmppStream])
    {
        XMPPLogVerbose(@"%@: Activated", THIS_FILE);
        
        xmppIDTracker = [[XMPPIDTracker alloc] initWithStream:xmppStream
                                                dispatchQueue:moduleQueue];
        
#ifdef _XMPP_CAPABILITIES_H
        [xmppStream autoAddDelegate:self
                      delegateQueue:moduleQueue
                   toModulesOfClass:[XMPPCapabilities class]];
#endif
        return YES;
    }
    
    return NO;
}

- (void)deactivate
{
    XMPPLogTrace();
    
    dispatch_block_t block = ^{ @autoreleasepool {
        [self->xmppIDTracker removeAllIDs];
        self->xmppIDTracker = nil;
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_sync(moduleQueue, block);
    
#ifdef _XMPP_CAPABILITIES_H
    [xmppStream removeAutoDelegate:self delegateQueue:moduleQueue fromModulesOfClass:[XMPPCapabilities class]];
#endif
    
    [super deactivate];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isMUCSUBRoomElement:(XMPPElement *)element
{
    XMPPJID *bareFrom = [[element from] bareJID];
    if (bareFrom == nil)
    {
        return NO;
    }
    
    __block BOOL result = NO;
    
    dispatch_block_t block = ^{ @autoreleasepool {
        
        result = [self->rooms containsObject:bareFrom];
        
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_sync(moduleQueue, block);
    
    return result;
}

- (BOOL)isMUCSUBRoomPresence:(XMPPPresence *)presence
{
    return [self isMUCSUBRoomElement:presence];
}

- (BOOL)isMUCSUBRoomMessage:(XMPPMessage *)message
{
    return [self isMUCSUBRoomElement:message];
}

/**
 * This method provides functionality of Discovering a MUCSUB Service.
 *
 * @link {https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/#discovering-support}
 *
 * Example 1. Entity Queries Server for Associated Services
 *
 * <iq from='hag66@shakespeare.example/pda'
 *       to='muc.shakespeare.example'
 *       type='get'
 *       id='ik3vs715'>
 *   <query xmlns='http://jabber.org/protocol/disco#info'/>
 * </iq>
 */
- (void)discoverFeatures
{
    // This is a public method, so it may be invoked on any thread/queue.
    
    dispatch_block_t block = ^{ @autoreleasepool {
        if (self->hasRequestedFeatures) return; // We've already requested services
        
        NSString *mucService = [NSString stringWithFormat:@"conference.%@", self->xmppStream.myJID.domain];
        NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                      xmlns:XMPPMUCSUBDiscoInfo];
        XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                     to:[XMPPJID jidWithString:mucService]
                              elementID:[self->xmppStream generateUUID]
                                  child:query];
        
        [self->xmppIDTracker addElement:iq
                                 target:self
                               selector:@selector(handleDiscoverFeaturesQueryIQ:withInfo:)
                                timeout:60];
        
        [self->xmppStream sendElement:iq];
        self->hasRequestedFeatures = YES;
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

/**
 * This method provides functionality of Discovering muc-sub features for Room
 *
 * @link {https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/#discovering-support-on-a-specific-muc}
 *
 * Example 5. Entity Queries muc-sub Service for Rooms
 *
 * <iq from='hag66@shakespeare.example/pda'
 *       to='coven@muc.shakespeare.example'
 *       type='get'
 *       id='ik3vs715'>
 *   <query xmlns='http://jabber.org/protocol/disco#info'/>
 * </iq>
 */
- (BOOL)discoverFeaturesForRoomJID:(XMPPJID *)roomJID
{
    // This is a public method, so it may be invoked on any thread/queue.
    
    if (roomJID.bare.length == 0)
        return NO;
    
    dispatch_block_t block = ^{ @autoreleasepool {
        if (self->hasRequestedFeaturesForRoom[roomJID.bare]) return; // We've already requested rooms
        
        NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                      xmlns:XMPPMUCSUBDiscoInfo];
        XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                     to:roomJID
                              elementID:[self->xmppStream generateUUID]
                                  child:query];
        
        [self->xmppIDTracker addElement:iq
                                 target:self
                               selector:@selector(handleDiscoverFeaturesForRoomQueryIQ:withInfo:)
                                timeout:60];
        
        [self->xmppStream sendElement:iq];
        self->hasRequestedFeaturesForRoom[roomJID.bare] = @YES;
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
    
    return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPIDTracker
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method handles the response received (or not received) after calling discoverServices.
 */
- (void)handleDiscoverFeaturesQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t block = ^{ @autoreleasepool {
        NSXMLElement *errorElem = [iq elementForName:@"error"];
        
        if (errorElem) {
            NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
            NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMUCSUBErrorDomain
                                                 code:[errorElem attributeIntegerValueForName:@"code"
                                                                             withDefaultValue:0]
                                             userInfo:dict];
            
            [self->multicastDelegate xmppMUCSUBFailedToDiscoverFeatures:self
                                                              withError:error];
            return;
        }
        
        NSXMLElement *query = [iq elementForName:@"query"
                                           xmlns:XMPPMUCSUBDiscoInfo];
        
        NSArray *features = [query elementsForName:@"feature"];
        [self->multicastDelegate xmppMUCSUB:self didDiscoverFeatures:features];
        self->hasRequestedFeatures = NO; // Set this back to NO to allow for future requests
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

/**
 * This method handles the response received (or not received) after calling discoverMUCSUBForRoom:.
 */
- (void)handleDiscoverFeaturesForRoomQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t block = ^{ @autoreleasepool {
        NSXMLElement *errorElem = [iq elementForName:@"error"];
        NSString *roomName = [iq attributeStringValueForName:@"from" withDefaultValue:@""];
        XMPPJID *roomJID = [XMPPJID jidWithString:roomName];
        
        if (errorElem) {
            NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
            NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMUCSUBErrorDomain
                                                 code:[errorElem attributeIntegerValueForName:@"code"
                                                                             withDefaultValue:0]
                                             userInfo:dict];
            [self->multicastDelegate xmppMUCSUB:self failedToDiscoverFeaturesForRoomJID:roomJID withError:error];
            return;
        }
        
        NSXMLElement *query = [iq elementForName:@"query" xmlns:XMPPMUCSUBDiscoInfo];
        
        NSArray *features = [query elementsForName:@"feature"];
        [self->multicastDelegate xmppMUCSUB:self didDiscoverFeatures:features ForRoomJID:roomJID];
        self->hasRequestedFeaturesForRoom[roomJID.bare] = @NO; // Set this back to NO to allow for future requests
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppStream:(XMPPStream *)sender didRegisterModule:(id)module
{
    if ([module isKindOfClass:[XMPPRoom class]])
    {
        XMPPJID *roomJID = [(XMPPRoom *)module roomJID];
        
        [rooms addObject:roomJID];
    }
}

- (void)xmppStream:(XMPPStream *)sender willUnregisterModule:(id)module
{
    if ([module isKindOfClass:[XMPPRoom class]])
    {
        XMPPJID *roomJID = [(XMPPRoom *)module roomJID];
        
        // It's common for the room to get deactivated and deallocated before
        // we've received the goodbye presence from the server.
        // So we're going to postpone for a bit removing the roomJID from the list.
        // This way the isMUCRoomElement will still remain accurate
        // for presence elements that may arrive momentarily.
        
        double delayInSeconds = 30.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, moduleQueue, ^{ @autoreleasepool {
            
            [self->rooms removeObject:roomJID];
        }});
    }
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    // Examples from XEP-0045:
    //
    //
    // Example 124. Room Sends Invitation to New Member:
    //
    // <message from='darkcave@chat.shakespeare.lit' to='hecate@shakespeare.lit'>
    //   <x xmlns='http://jabber.org/protocol/muc#user'>
    //     <invite from='bard@shakespeare.lit'/>
    //     <password>cauldronburn</password>
    //   </x>
    // </message>
    //
    //
    // Example 125. Service Returns Error on Attempt by Mere Member to Invite Others to a Members-Only Room
    //
    // <message from='darkcave@chat.shakespeare.lit' to='hag66@shakespeare.lit/pda' type='error'>
    //   <x xmlns='http://jabber.org/protocol/muc#user'>
    //     <invite to='hecate@shakespeare.lit'>
    //       <reason>
    //         Hey Hecate, this is the place for all good witches!
    //       </reason>
    //     </invite>
    //   </x>
    //   <error type='auth'>
    //     <forbidden xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>
    //   </error>
    // </message>
    //
    //
    // Example 50. Room Informs Invitor that Invitation Was Declined
    //
    // <message from='darkcave@chat.shakespeare.lit' to='crone1@shakespeare.lit/desktop'>
    //   <x xmlns='http://jabber.org/protocol/muc#user'>
    //     <decline from='hecate@shakespeare.lit'>
    //       <reason>
    //         Sorry, I'm too busy right now.
    //       </reason>
    //     </decline>
    //   </x>
    // </message>
    //
    //
    // Examples from XEP-0249:
    //
    //
    // Example 1. A direct invitation
    //
    // <message from='crone1@shakespeare.lit/desktop' to='hecate@shakespeare.lit'>
    //   <x xmlns='jabber:x:conference'
    //      jid='darkcave@macbeth.shakespeare.lit'
    //      password='cauldronburn'
    //      reason='Hey Hecate, this is the place for all good witches!'/>
    // </message>
    
    NSXMLElement * x = [message elementForName:@"x" xmlns:XMPPMUCUserNamespace];
    NSXMLElement * invite  = [x elementForName:@"invite"];
    NSXMLElement * decline = [x elementForName:@"decline"];
    
    NSXMLElement * directInvite = [message elementForName:@"x" xmlns:@"jabber:x:conference"];
    
    XMPPJID * roomJID = [message from];
    
    if (invite || directInvite)
    {
        [multicastDelegate xmppMUCSUB:self roomJID:roomJID didReceiveInvitation:message];
    }
    else if (decline)
    {
        [multicastDelegate xmppMUCSUB:self roomJID:roomJID didReceiveInvitationDecline:message];
    }
}

- (BOOL)xmppStream:(XMPPStream *)stream didReceiveIQ:(XMPPIQ *)iq
{
    NSString *type = [iq type];
    
    if ([type isEqualToString:@"result"] || [type isEqualToString:@"error"]) {
        return [xmppIDTracker invokeForElement:iq withObject:iq];
    }
    
    return NO;
}


#ifdef _XMPP_CAPABILITIES_H
/**
 * If an XMPPCapabilites instance is used we want to advertise our support for MUCSUB.
 **/
- (void)xmppCapabilities:(XMPPCapabilities *)sender collectingMyCapabilities:(NSXMLElement *)query
{
    // This method is invoked on our moduleQueue.
    
    // <query xmlns="http://jabber.org/protocol/disco#info">
    //   ...
    //   <feature var='urn:xmpp:mucsub:0'/>
    //   ...
    // </query>
    
    NSXMLElement *feature = [NSXMLElement elementWithName:@"feature"];
    [feature addAttributeWithName:@"var" stringValue:XMPPMUCSUBNamespace];
    
    [query addChild:feature];
}
#endif

@end
