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

NSString *const XMPPMucSubDiscoInfo = @"http://jabber.org/protocol/disco#info";
NSString *const XMPPMucSubErrorDomain = @"XMPPMUCSUBErrorDomain";
NSString *const XMPPMucSubNamespace = @"urn:xmpp:mucsub:0";
NSString *const XMPPPubSubEventNamespace = @"http://jabber.org/protocol/pubsub#event";
NSString *const XMPPMucSubMessageNamespace = @"urn:xmpp:mucsub:nodes:messages";
NSString *const XMPPMucSubPresenceNamespace = @"urn:xmpp:mucsub:nodes:presence";
NSString *const XMPPMucSubSubscribeNamespace = @"urn:xmpp:mucsub:nodes:subscribe";
NSString *const XMPPMucSubUnsubscribeNamespace = @"urn:xmpp:mucsub:nodes:unsubscribe";

NSString *const XMPPSubscribeEventPresence = @"urn:xmpp:mucsub:nodes:presence";
NSString *const XMPPSubscribeEventMessages = @"urn:xmpp:mucsub:nodes:messages";
NSString *const XMPPSubscribeEventAffiliations = @"urn:xmpp:mucsub:nodes:affiliations";
NSString *const XMPPSubscribeEventSubscribers = @"urn:xmpp:mucsub:nodes:subscribers";
NSString *const XMPPSubscribeEventConfig = @"urn:xmpp:mucsub:nodes:config";
NSString *const XMPPSubscribeEventSubject = @"urn:xmpp:mucsub:nodes:subject";
NSString *const XMPPSubscribeEventSystem = @"urn:xmpp:mucsub:nodes:system";

NSString *const kXMPPCode = @"code";
NSString *const kXMPPConference = @"conference";
NSString *const kXMPPError = @"error";
NSString *const kXMPPEvent = @"event";
NSString *const kXMPPFeature = @"feature";
NSString *const kXMPPFrom = @"from";
NSString *const kXMPPGet = @"get";
NSString *const kXMPPItem = @"item";
NSString *const kXMPPItems = @"items";
NSString *const kXMPPJid = @"jid";
NSString *const kXMPPMessage = @"message";
NSString *const kXMPPNick = @"nick";
NSString *const kXMPPNode = @"node";
NSString *const kXMPPPassword = @"password";
NSString *const kXMPPPresence = @"presence";
NSString *const kXMPPQuery = @"query";
NSString *const kXMPPResult = @"result";
NSString *const kXMPPSet = @"set";
NSString *const kXMPPSubscribe = @"subscribe";
NSString *const kXMPPSubscriptions = @"subscriptions";
NSString *const kXMPPUnsubscribe = @"unsubscribe";
NSString *const kXMPPVar = @"var";

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
        hasRequestedFeaturesForRoom = [NSMutableDictionary new];
        hasRequestedFeatures = NO;
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
    
    dispatch_block_t deactivateBlock = ^{ @autoreleasepool {
        [self->xmppIDTracker removeAllIDs];
        self->xmppIDTracker = nil;
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        deactivateBlock();
    else
        dispatch_sync(moduleQueue, deactivateBlock);
    
#ifdef _XMPP_CAPABILITIES_H
    [xmppStream removeAutoDelegate:self delegateQueue:moduleQueue fromModulesOfClass:[XMPPCapabilities class]];
#endif
    
    [super deactivate];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
    
    dispatch_block_t discoverFeaturesBlock = ^{ @autoreleasepool {
        if (self->hasRequestedFeatures) return; // We've already requested services
        
        NSString *mucService = [NSString stringWithFormat:@"%@.%@", kXMPPConference, self->xmppStream.myJID.domain];
        NSXMLElement *query = [NSXMLElement elementWithName:kXMPPQuery
                                                      xmlns:XMPPMucSubDiscoInfo];
        XMPPIQ *iq = [XMPPIQ iqWithType:kXMPPGet
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
        discoverFeaturesBlock();
    else
        dispatch_async(moduleQueue, discoverFeaturesBlock);
}

/**
 * This method provides functionality of Discovering muc-sub features for Room
 *
 * @link {https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/#discovering-support-on-a-specific-muc}
 *
 * Example: Entity Queries muc-sub Service for Rooms
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
    
    dispatch_block_t discoverFeaturesForRoomJIDBlock = ^{ @autoreleasepool {
        if (self->hasRequestedFeaturesForRoom[roomJID.bare]) return; // We've already requested rooms
        
        NSXMLElement *query = [NSXMLElement elementWithName:kXMPPQuery
                                                      xmlns:XMPPMucSubDiscoInfo];
        XMPPIQ *iq = [XMPPIQ iqWithType:kXMPPGet
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
        discoverFeaturesForRoomJIDBlock();
    else
        dispatch_async(moduleQueue, discoverFeaturesForRoomJIDBlock);
    
    return YES;
}

/**
 * User can subscribe to the following events, by subscribing to specific nodes:
 * urn:xmpp:mucsub:nodes:presence
 * urn:xmpp:mucsub:nodes:messages
 * urn:xmpp:mucsub:nodes:affiliations
 * urn:xmpp:mucsub:nodes:subscribers
 * urn:xmpp:mucsub:nodes:config
 * urn:xmpp:mucsub:nodes:subject
 * urn:xmpp:mucsub:nodes:system
 *
 * @link {https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/#subscribing-to-muc-sub-events}
 *
 * Example: User Subscribes to MUC/Sub events
 *
 * <iq from="hag66@shakespeare.example" to="coven@muc.shakespeare.example" type="set" id="E6E10350-76CF-40C6-B91B-1EA08C332FC7">
 *     <subscribe xmlns="urn:xmpp:mucsub:0" nick="mynick" password="roompassword">
 *         <event node="urn:xmpp:mucsub:nodes:messages" />
 *         <event node="urn:xmpp:mucsub:nodes:affiliations" />
 *         <event node="urn:xmpp:mucsub:nodes:subject" />
 *         <event node="urn:xmpp:mucsub:nodes:config" />
 *     </subscribe>
 * </iq>
 */
- (void)subscribeToEvents:(NSArray<XMPPSubscribeEvent> *)events roomJID:(XMPPJID *)roomJID userJID:(XMPPJID *)userJID withNick:(NSString *)nickName passwordForRoom:(NSString *)password {
    
    // This is a public method, so it may be invoked on any thread/queue.
    
    if (roomJID.bare.length == 0)
        return;
    
    dispatch_block_t subscribeToEventsBlock = ^{ @autoreleasepool {
       
        NSXMLElement *subscribe = [NSXMLElement elementWithName:kXMPPSubscribe xmlns:XMPPMucSubNamespace];
        if (nickName.length > 0) {
            [subscribe addAttributeWithName:kXMPPNick stringValue:nickName];
        }
        if (password.length > 0) {
            [subscribe addAttributeWithName:kXMPPPassword stringValue:password];
        }
        if (userJID) {
            [subscribe addAttributeWithName:kXMPPJid stringValue:userJID.bare];
        }
        for (XMPPSubscribeEvent xmppSubscribeEvent in events) {
            NSXMLElement *event = [NSXMLElement elementWithName:kXMPPEvent];
            [event addAttributeWithName:kXMPPNode stringValue:xmppSubscribeEvent];
            [subscribe addChild:event];
        }
        XMPPIQ *iq = [XMPPIQ iqWithType:kXMPPSet
                                     to:roomJID
                              elementID:[self->xmppStream generateUUID]
                                  child:subscribe];
        
        [self->xmppIDTracker addElement:iq
                                 target:self
                               selector:@selector(handleSubscribeToRoom:withInfo:)
                                timeout:60];
        
        [self->xmppStream sendElement:iq];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        subscribeToEventsBlock();
    else
        dispatch_async(moduleQueue, subscribeToEventsBlock);
    
}

/**
 * At any time a user can unsubscribe from MUC Room events.
 *
 * @link {https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/#unsubscribing-from-a-muc-room}
 *
 * Example: User unsubscribes from a MUC Room
 *
 * <iq from='hag66@shakespeare.example' to='coven@muc.shakespeare.example' type='set' id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
 *     <unsubscribe xmlns='urn:xmpp:mucsub:0' />
 * </iq>
 *
 *
 * Example: Room moderator unsubscribes another room user
 *
 * <iq from='king@shakespeare.example' to='coven@muc.shakespeare.example' type='set' id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
 *     <unsubscribe xmlns='urn:xmpp:mucsub:0' jid='hag66@shakespeare.example'/>
 * </iq>
 */
- (void)unsubscribeFromRoomJID:(XMPPJID *)roomJID userJID:(XMPPJID *)userJID {
    
    // This is a public method, so it may be invoked on any thread/queue.
    
    if (roomJID.bare.length == 0)
        return;
    
    dispatch_block_t unsubscribeFromRoomJIDBlock = ^{ @autoreleasepool {
        
        NSXMLElement *unsubscribe = [NSXMLElement elementWithName:kXMPPUnsubscribe xmlns:XMPPMucSubNamespace];
        
        if (userJID) {
            [unsubscribe addAttributeWithName:kXMPPJid stringValue:userJID.bare];
        }
        XMPPIQ *iq = [XMPPIQ iqWithType:kXMPPSet
                                     to:roomJID
                              elementID:[self->xmppStream generateUUID]
                                  child:unsubscribe];
        
        [self->xmppIDTracker addElement:iq
                                 target:self
                               selector:@selector(handleUnsubscribeFromRoom:withInfo:)
                                timeout:60];
        
        [self->xmppStream sendElement:iq];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        unsubscribeFromRoomJIDBlock();
    else
        dispatch_async(moduleQueue, unsubscribeFromRoomJIDBlock);
    
}

/**
 * A user can query the MUC service to get their list of subscriptions.
 *
 * @link {https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/#list-of-subscriptions}
 *
 * Example: User asks for subscriptions list
 *
 * <iq from='hag66@shakespeare.example' to='muc.shakespeare.example' type='get' id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
 *     <subscriptions xmlns='urn:xmpp:mucsub:0' />
 * </iq>
 */
- (void)fetchSubscriptionList {
    
    // This is a public method, so it may be invoked on any thread/queue.
    
    dispatch_block_t fetchSubscriptionListBlock = ^{ @autoreleasepool {
        
        NSXMLElement *subscriptions = [NSXMLElement elementWithName:kXMPPSubscriptions xmlns:XMPPMucSubNamespace];
        XMPPJID *mucServiceJID = [XMPPJID jidWithString:[NSString stringWithFormat:@"%@.%@", kXMPPConference, self->xmppStream.myJID.domain]];
        
        XMPPIQ *iq = [XMPPIQ iqWithType:kXMPPGet
                                     to: mucServiceJID
                              elementID:[self->xmppStream generateUUID]
                                  child:subscriptions];
        
        [self->xmppIDTracker addElement:iq
                                 target:self
                               selector:@selector(handleFetchSubscriptionList:withInfo:)
                                timeout:60];
        
        [self->xmppStream sendElement:iq];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        fetchSubscriptionListBlock();
    else
        dispatch_async(moduleQueue, fetchSubscriptionListBlock);
    
}

/**
 * A room moderator can get the list of subscribers by sending <subscriptions/> request directly to the room JID.
 *
 * @link {https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/#list-of-subscriptions}
 *
 * Example: Moderator asks for subscribers list
 *
 * <iq from='hag66@shakespeare.example' to='coven@muc.shakespeare.example' type='get' id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
 *    <subscriptions xmlns='urn:xmpp:mucsub:0' />
 * </iq>
 */
- (void)fetchSubscribersListForRoom:(XMPPJID *)roomJID {
    
    // This is a public method, so it may be invoked on any thread/queue.
    
    if (roomJID.bare.length == 0)
        return;
    
    dispatch_block_t fetchSubscribersListForRoomBlock = ^{ @autoreleasepool {
        
        NSXMLElement *subscriptions = [NSXMLElement elementWithName:kXMPPSubscriptions xmlns:XMPPMucSubNamespace];
        
        XMPPIQ *iq = [XMPPIQ iqWithType:kXMPPGet
                                     to: roomJID
                              elementID:[self->xmppStream generateUUID]
                                  child:subscriptions];
        
        [self->xmppIDTracker addElement:iq
                                 target:self
                               selector:@selector(handleFetchSubscribersList:withInfo:)
                                timeout:60];
        
        [self->xmppStream sendElement:iq];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        fetchSubscribersListForRoomBlock();
    else
        dispatch_async(moduleQueue, fetchSubscribersListForRoomBlock);
    
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPIDTracker
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method handles the response received (or not received) after calling discoverServices.
 *
 * MUC service will show a feature of type 'urn:xmpp:mucsub:0' to the response if the feature is supported and enabled
 *
 * <iq from="muc.shakespeare.example" to="hag66@shakespeare.example/pda" type="result" id="ik3vs715">
 *     <query xmlns="http://jabber.org/protocol/disco#info">
 *         <identity category="conference" type="text" name="Chatrooms" />
 *         ...
 *         <feature var="urn:xmpp:mucsub:0" />
 *         ...
 *     </query>
 * </iq>
 */
- (void)handleDiscoverFeaturesQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t discoverFeaturesQueryIQBlock = ^{ @autoreleasepool {
        NSXMLElement *errorElem = [iq elementForName:kXMPPError];
        
        if (errorElem) {
            NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
            NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain
                                                 code:[errorElem attributeIntegerValueForName:kXMPPCode
                                                                             withDefaultValue:0]
                                             userInfo:dict];
            
            [self->multicastDelegate xmppMUCSUB:self failedToDiscoverFeaturesWithError:error];
            return;
        }
        
        NSXMLElement *query = [iq elementForName:kXMPPQuery
                                           xmlns:XMPPMucSubDiscoInfo];
        
        NSArray<NSXMLElement *> *features = [query elementsForName:kXMPPFeature];
        [self->multicastDelegate xmppMUCSUB:self didDiscoverFeatures:features];
        self->hasRequestedFeatures = NO; // Set this back to NO to allow for future requests
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        discoverFeaturesQueryIQBlock();
    else
        dispatch_async(moduleQueue, discoverFeaturesQueryIQBlock);
}

/**
 * This method handles the response received (or not received) after calling discoverMUCSUBForRoom:.
 *
 * A conference MUST add 'urn:xmpp:mucsub:0' to the response if the feature is supported and enabled
 *
 * <iq from='coven@muc.shakespeare.example' to='hag66@shakespeare.example/pda' type='result' id='ik3vs715'>
 *     <query xmlns='http://jabber.org/protocol/disco#info'>
 *         <identity category='conference' name='A Dark Cave' type='text' />
 *         <feature var='http://jabber.org/protocol/muc' />
 *         ...
 *         <feature var='urn:xmpp:mucsub:0' />
 *         ...
 *     </query>
 * </iq>
 */
- (void)handleDiscoverFeaturesForRoomQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t discoverFeaturesForRoomQueryIQBlock = ^{ @autoreleasepool {
        NSXMLElement *errorElem = [iq elementForName:kXMPPError];
        XMPPJID *roomJID = [XMPPJID jidWithString:[iq attributeStringValueForName:kXMPPFrom withDefaultValue:@""]];
        if (!roomJID) {
            NSString *errMsg = @"roomJID is nil.";
            NSDictionary *info = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain code:XMPPStreamInvalidParameter userInfo:info];
            [self->multicastDelegate xmppMUCSUB:self failedToDiscoverFeaturesForRoomJID:roomJID withError:error];
            return;
        }
        
        if (errorElem) {
            NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
            NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain
                                                 code:[errorElem attributeIntegerValueForName:kXMPPCode
                                                                             withDefaultValue:0]
                                             userInfo:dict];
            [self->multicastDelegate xmppMUCSUB:self failedToDiscoverFeaturesForRoomJID:roomJID withError:error];
            return;
        }
        
        NSXMLElement *query = [iq elementForName:kXMPPQuery xmlns:XMPPMucSubDiscoInfo];
        
        NSArray<NSXMLElement *> *features = [query elementsForName:kXMPPFeature];
        [self->multicastDelegate xmppMUCSUB:self didDiscoverFeatures:features forRoomJID:roomJID];
        self->hasRequestedFeaturesForRoom[roomJID.bare] = @NO; // Set this back to NO to allow for future requests
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        discoverFeaturesForRoomQueryIQBlock();
    else
        dispatch_async(moduleQueue, discoverFeaturesForRoomQueryIQBlock);
}

/**
 * This method handles the response received (or not received) after calling subscribeToEvents:roomJID:userJID:withNick:password.
 *
 * Example: Server replies with success
 * <iq from='coven@muc.shakespeare.example' to='hag66@shakespeare.example' type='result' id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
 *     <subscribe xmlns='urn:xmpp:mucsub:0'>
 *         <event node='urn:xmpp:mucsub:nodes:messages' />
 *         <event node='urn:xmpp:mucsub:nodes:affiliations' />
 *         <event node='urn:xmpp:mucsub:nodes:subject' />
 *         <event node='urn:xmpp:mucsub:nodes:config' />
 *     </subscribe>
 * </iq>
 *
 */
- (void)handleSubscribeToRoom:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t subscribeToRoomBlock = ^{ @autoreleasepool {
        NSXMLElement *errorElem = [iq elementForName:kXMPPError];
        XMPPJID *roomJID = [XMPPJID jidWithString:[iq attributeStringValueForName:kXMPPFrom withDefaultValue:@""]];
        if (!roomJID) {
            NSString *errMsg = @"roomJID is nil.";
            NSDictionary *info = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain code:XMPPStreamInvalidParameter userInfo:info];
            [self->multicastDelegate xmppMUCSUB:self failedToSubscribeToRoomJID:roomJID withError:error];
            return;
        }
        
        if (errorElem) {
            NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
            NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain
                                                 code:[errorElem attributeIntegerValueForName:kXMPPCode
                                                                             withDefaultValue:0]
                                             userInfo:dict];
            [self->multicastDelegate xmppMUCSUB:self failedToSubscribeToRoomJID:roomJID withError:error];
            return;
        }
        
        NSXMLElement *subscribe = [iq elementForName:kXMPPSubscribe xmlns:XMPPMucSubNamespace];
        
        NSArray *events = [subscribe elementsForName:kXMPPEvent];
        NSMutableArray<XMPPSubscribeEvent> *subscribedEvents = [NSMutableArray new];
        for (NSXMLElement *event in events) {
            [subscribedEvents addObject:[[event attributeForName:kXMPPNode] stringValue]];
        }
        [self->multicastDelegate xmppMUCSUB:self didSubscribeToEvents:subscribedEvents roomJID:roomJID];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        subscribeToRoomBlock();
    else
        dispatch_async(moduleQueue, subscribeToRoomBlock);
}

/**
 * This method handles the response received (or not received) after calling unsubscribeFromRoomJID:.
 *
 * Example: A MUC Room responds to unsubscribe request
 * <iq  from='coven@muc.shakespeare.example' to='hag66@shakespeare.example' type='result' id='E6E10350-76CF-40C6-B91B-1EA08C332FC7' />
 *
 */
- (void)handleUnsubscribeFromRoom:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t unsubscribeFromRoomBlock = ^{ @autoreleasepool {
        NSXMLElement *errorElem = [iq elementForName:kXMPPError];
        
        XMPPJID *roomJID = [XMPPJID jidWithString:[iq attributeStringValueForName:kXMPPFrom withDefaultValue:@""]];
        if (!roomJID) {
            NSString *errMsg = @"roomJID is nil.";
            NSDictionary *info = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain code:XMPPStreamInvalidParameter userInfo:info];
            [self->multicastDelegate xmppMUCSUB:self failedToUnsubscribeFromRoomJID:roomJID withError:error];
            return;
        }
        
        if (errorElem) {
            NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
            NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain
                                                 code:[errorElem attributeIntegerValueForName:kXMPPCode
                                                                             withDefaultValue:0]
                                             userInfo:dict];
            [self->multicastDelegate xmppMUCSUB:self failedToUnsubscribeFromRoomJID:roomJID withError:error];
            return;
        }
        [self->multicastDelegate xmppMUCSUB:self didUnsubscribeFromRoomJID:roomJID];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        unsubscribeFromRoomBlock();
    else
        dispatch_async(moduleQueue, unsubscribeFromRoomBlock);
}

/**
 * This method handles the response received (or not received) after calling fetchSubscriptionList.
 *
 * Example: Server replies with subscriptions list
 *
 * <iq from='muc.shakespeare.example' to='hag66@shakespeare.example' type='result' id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
 *     <subscriptions xmlns='urn:xmpp:mucsub:0'>
 *         <subscription jid='coven@muc.shakespeare.example'>
 *             <event node='urn:xmpp:mucsub:nodes:messages'/>
 *             <event node='urn:xmpp:mucsub:nodes:affiliations'/>
 *             <event node='urn:xmpp:mucsub:nodes:subject'/>
 *             <event node='urn:xmpp:mucsub:nodes:config'/>
 *         </subscription>
 *         <subscription jid='chat@muc.shakespeare.example'>
 *             <event node='urn:xmpp:mucsub:nodes:messages'/>
 *         </subscription>
 *     </subscriptions>
 * </iq>
 *
 */
- (void)handleFetchSubscriptionList:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t fetchSubscriptionListBlock = ^{ @autoreleasepool {
        NSXMLElement *errorElem = [iq elementForName:kXMPPError];
        NSXMLElement *subscriptions = [iq elementForName:kXMPPSubscriptions];
        
        if (errorElem) {
            NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
            NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain
                                                 code:[errorElem attributeIntegerValueForName:kXMPPCode
                                                                             withDefaultValue:0]
                                             userInfo:dict];
            [self->multicastDelegate xmppMUCSUB:self failedToFetchSubscriptionListWithError:error];
            return;
        }
        
        [self->multicastDelegate xmppMUCSUB:self didFetchSubscriptionList:subscriptions];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        fetchSubscriptionListBlock();
    else
        dispatch_async(moduleQueue, fetchSubscriptionListBlock);
}

/**
 * This method handles the response received (or not received) after calling fetchSubscribersListForRoom:.
 *
 * Example: Server replies with subscribers list
 *
 * <iq from='coven@muc.shakespeare.example' to='hag66@shakespeare.example' type='result' id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
 *     <subscriptions xmlns='urn:xmpp:mucsub:0'>
 *         <subscription jid='juliet@shakespeare.example'>
 *             <event node='urn:xmpp:mucsub:nodes:messages'/>
 *             <event node='urn:xmpp:mucsub:nodes:affiliations'/>
 *         </subscription>
 *         <subscription jid='romeo@shakespeare.example'>
 *             <event node='urn:xmpp:mucsub:nodes:messages'/>
 *         </subscription>
 *     </subscriptions>
 * </iq>
 */
- (void)handleFetchSubscribersList:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t fetchSubscribersListBlock = ^{ @autoreleasepool {
        NSXMLElement *errorElem = [iq elementForName:kXMPPError];
        XMPPJID *roomJID = [XMPPJID jidWithString:[iq attributeStringValueForName:kXMPPFrom withDefaultValue:@""]];
        if (!roomJID) {
            NSString *errMsg = @"roomJID is nil.";
            NSDictionary *info = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain code:XMPPStreamInvalidParameter userInfo:info];
            [self->multicastDelegate xmppMUCSUB:self failedToFetchSubscribersListWithError:error];
            return;
        }
        NSXMLElement *subscriptions = [iq elementForName:kXMPPSubscriptions];
        
        if (errorElem) {
            NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
            NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
            NSError *error = [NSError errorWithDomain:XMPPMucSubErrorDomain
                                                 code:[errorElem attributeIntegerValueForName:kXMPPCode
                                                                             withDefaultValue:0]
                                             userInfo:dict];
            [self->multicastDelegate xmppMUCSUB:self failedToFetchSubscribersListWithError:error];
            return;
        }
        [self->multicastDelegate xmppMUCSUB:self didFetchSubscribersList:subscriptions forRoomJID:roomJID];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        fetchSubscribersListBlock();
    else
        dispatch_async(moduleQueue, fetchSubscribersListBlock);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    /*
     * @link {https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/#receiving-events}
     */
    
    /*
     *
     * Here is as an example message received by a subscriber when a message is posted to a MUC room when subscriber is subscribed to node urn:xmpp:mucsub:nodes:messages:
     *
     * <message from="coven@muc.shakespeare.example" to="hag66@shakespeare.example/pda">
     *     <event xmlns="http://jabber.org/protocol/pubsub#event">
     *         <items node="urn:xmpp:mucsub:nodes:messages">
     *             <item id="18277869892147515942">
     *                 <message xmlns="jabber:client" from="coven@muc.shakespeare.example/secondwitch" to="hag66@shakespeare.example/pda" type="groupchat">
     *                     <archived xmlns="urn:xmpp:mam:tmp" by="muc.shakespeare.example" id="1467896732929849" />
     *                     <stanza-id xmlns="urn:xmpp:sid:0" by="muc.shakespeare.example" id="1467896732929849" />
     *                     <body>Hello from the MUC room !</body>
     *                 </message>
     *             </item>
     *        </items>
     *     </event>
     * </message>
     */
    
    /*
     * Presence changes in the MUC room are received wrapped in the same way by subscribers which subscribed to node urn:xmpp:mucsub:nodes:presence:
     *
     * <message from="coven@muc.shakespeare.example" to="hag66@shakespeare.example/pda">
     *     <event xmlns="http://jabber.org/protocol/pubsub#event">
     *         <items node="urn:xmpp:mucsub:nodes:presences">
     *             <item id="8170705750417052518">
     *                 <presence xmlns="jabber:client" from="coven@muc.shakespeare.example/secondwitch" type="unavailable" to="hag66@shakespeare.example/pda">
     *                     <x xmlns="http://jabber.org/protocol/muc#user">
     *                         <item affiliation="none" role="none" />
     *                     </x>
     *                 </presence>
     *             </item>
     *         </items>
     *     </event>
     * </message>
     */
    
    /*
     * If subscriber is subscribed to node urn:xmpp:mucsub:nodes:subscribers, message will be sent for every mucsub subscription change. When a user becomes a subscriber:
     *
     * <message from="coven@muc.shakespeare.example" to="hag66@shakespeare.example/pda">
     *     <event xmlns="http://jabber.org/protocol/pubsub#event">
     *         <items node="urn:xmpp:mucsub:nodes:subscribers">
     *             <item id="17895981155977588737">
     *                 <subscribe xmlns="urn:xmpp:mucsub:0" jid="bob@server.com" nick="bob"/>
     *             </item>
     *         </items>
     *     </event>
     * </message>
     */
    
    /*
     * When a user lost its subscription:
     *
     * <message from="coven@muc.shakespeare.example" to="hag66@shakespeare.example/pda">
     *     <event xmlns="http://jabber.org/protocol/pubsub#event">
     *         <items node="urn:xmpp:mucsub:nodes:subscribers">
     *             <item id="10776102417321261057">
     *                 <unsubscribe xmlns="urn:xmpp:mucsub:0" jid="bob@server.com" nick="bob"/>
     *             </item>
     *         </items>
     *     </event>
     * </message>
     */
    
    NSXMLElement *event = [message elementForName:kXMPPEvent xmlns:XMPPPubSubEventNamespace];
    NSXMLElement *items = [event elementForName:kXMPPItems];
    
    if (items) {
        NSXMLElement *item = [items elementForName:kXMPPItem];
        NSString *node = [[items attributeForName:kXMPPNode] stringValue];
        if ([node isEqualToString:XMPPMucSubMessageNamespace]) {
            NSXMLElement *messageElement = [item elementForName:kXMPPMessage];
            if (messageElement) {
                XMPPMessage *mucSubMessage = [XMPPMessage messageFromElement:messageElement];
                [multicastDelegate xmppMUCSUB:self didReceiveMessage:mucSubMessage];
            }
        }
        else if ([node isEqualToString:XMPPMucSubPresenceNamespace]) {
            NSXMLElement *presenceElement = [item elementForName:kXMPPPresence];
            if (presenceElement) {
                XMPPPresence *mucSubPresence = [XMPPPresence presenceFromElement:presenceElement];
                [multicastDelegate xmppMUCSUB:self didReceivePresence:mucSubPresence];
            }
        }
        else if ([node isEqualToString:XMPPMucSubSubscribeNamespace]) {
            NSXMLElement *subscribeElement = [item elementForName:kXMPPSubscribe];
            if (subscribeElement) {
                [multicastDelegate xmppMUCSUB:self didSubscribe:subscribeElement];
            }
        }
        else if ([node isEqualToString:XMPPMucSubUnsubscribeNamespace]) {
            NSXMLElement *unsubscribeElement = [item elementForName:kXMPPUnsubscribe];
            if (unsubscribeElement) {
                [multicastDelegate xmppMUCSUB:self didUnsubscribe:unsubscribeElement];
            }
        }
    }
}

- (BOOL)xmppStream:(XMPPStream *)stream didReceiveIQ:(XMPPIQ *)iq
{
    NSString *type = [iq type];
    
    if ([type isEqualToString:kXMPPResult] || [type isEqualToString:kXMPPError]) {
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
    /*
     * This method is invoked on our moduleQueue.
     *
     * <query xmlns="http://jabber.org/protocol/disco#info">
     *     ...
     *     <feature var='urn:xmpp:mucsub:0'/>
     *     ...
     * </query>
     */
    
    NSXMLElement *feature = [NSXMLElement elementWithName:kXMPPFeature];
    [feature addAttributeWithName:kXMPPVar stringValue:XMPPMucSubNamespace];
    
    [query addChild:feature];
}
#endif

@end
