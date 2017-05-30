//
//  XMPPMessageArchiveManagement.m
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-11.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import "XMPPMessageArchiveManagement.h"
#import "XMPPLogging.h"
#import "XMPPDateTimeProfiles.h"

#if DEBUG
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN; // | XMPP_LOG_FLAG_TRACE;
#else
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

#define XMLNS_XMPP_ARCHIVE @"urn:xmpp:mam:1"

// XMPP Incoming File Transfer State
typedef NS_ENUM(int, XMPPMessageArchiveSyncState) {
    XMPPMessageArchiveSyncStateNone,
    XMPPMessageArchiveSyncStateWaitingForSyncResponse,
    XMPPMessageArchiveSyncStateSyncing
};

@interface XMPPMessageArchiveManagement()
{
    XMPPMessageArchiveSyncState _syncState;
    NSString* syncId;
}

@end

@implementation XMPPMessageArchiveManagement

- (id)init
{
    // This will cause a crash - it's designed to.
    // Only the init methods listed in XMPPMessageArchiving.h are supported.
    _syncState = XMPPMessageArchiveSyncStateNone;
    return [self initWithMessageArchivingManagementStorage:nil dispatchQueue:NULL];
}

- (id)initWithDispatchQueue:(dispatch_queue_t)queue
{
    // This will cause a crash - it's designed to.
    // Only the init methods listed in XMPPMessageArchiving.h are supported.
    
    _syncState = XMPPMessageArchiveSyncStateNone;
    return [self initWithMessageArchivingManagementStorage:nil dispatchQueue:queue];
}

- (id)initWithMessageArchivingManagementStorage:(id <XMPPMessageArchivingManagementStorage>)storage
{
    _syncState = XMPPMessageArchiveSyncStateNone;
    return [self initWithMessageArchivingManagementStorage:storage dispatchQueue:NULL];
}

- (id)initWithMessageArchivingManagementStorage:(id <XMPPMessageArchivingManagementStorage>)storage dispatchQueue:(dispatch_queue_t)queue
{
    NSParameterAssert(storage != nil);
    
    if ((self = [super initWithDispatchQueue:queue]))
    {
        if ([storage configureWithParent:self queue:moduleQueue])
        {
            xmppMessageArchivingManagementStorage = storage;
        }
        else
        {
            XMPPLogError(@"%@: %@ - Unable to configure storage!", THIS_FILE, THIS_METHOD);
        }
        
//          <prefs xmlns='urn:xmpp:mam:1' default='always'>
//          </prefs>
        
        NSXMLElement *pref = [NSXMLElement elementWithName:@"pref" xmlns:XMLNS_XMPP_ARCHIVE];
        [pref addAttributeWithName:@"default" stringValue:@"always"];
        
        preferences = pref;
    }
    _syncState = XMPPMessageArchiveSyncStateNone;
    return self;
}

- (BOOL)activate:(XMPPStream *)aXmppStream
{
    XMPPLogTrace();
    
    if ([super activate:aXmppStream])
    {
        XMPPLogVerbose(@"%@: Activated", THIS_FILE);
        
        // Reserved for future potential use
        
        return YES;
    }
    
    return NO;
}

- (void)deactivate
{
    XMPPLogTrace();
    
    if (_syncState != XMPPMessageArchiveSyncStateNone) {
        XMPPLogWarn(@"%@: Deallocating prior to completion or cancellation.", THIS_FILE);
    }
    
    // Reserved for future potential use
    
    [super deactivate];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id <XMPPMessageArchivingManagementStorage>)xmppMessageArchivingManagementStorage
{
    // Note: The xmppMessageArchivingManagementStorage variable is read-only (set in the init method)
    
    return xmppMessageArchivingManagementStorage;
}

- (NSXMLElement *)preferences
{
    __block NSXMLElement *result = nil;
    
    dispatch_block_t block = ^{
        
        result = [preferences copy];
    };
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_sync(moduleQueue, block);
    
    return result;
}

- (void)setPreferences:(NSXMLElement *)newPreferences
{
    dispatch_block_t block = ^{ @autoreleasepool {
        
        // Update cached value
        
        // Update preferences only if it has changed
        if (![newPreferences.XMLString isEqualToString:preferences.XMLString]) {
            
            preferences = [newPreferences copy];
            
            // Update storage
            
            if ([xmppMessageArchivingManagementStorage respondsToSelector:@selector(setPreferences:forUser:)])
            {
                XMPPJID *myBareJid = [[xmppStream myJID] bareJID];
                
                [xmppMessageArchivingManagementStorage setPreferences:preferences forUser:myBareJid];
            }
            
            //  - Send new pref to server
            XMPPIQ *iq = [XMPPIQ iqWithType:@"set" to:nil elementID:nil child:preferences];
            [xmppStream sendElement:iq];
        }
        
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender
{
    XMPPLogTrace();
    
    // Fetch most recent preferences
    
    if ([xmppMessageArchivingManagementStorage respondsToSelector:@selector(preferencesForUser:)])
    {
        XMPPJID *myBareJid = [[xmppStream myJID] bareJID];
        
        preferences = [xmppMessageArchivingManagementStorage preferencesForUser:myBareJid];
    }
    
    // Request archiving preferences from server
    //
    // <iq type='get' id='juliet2'>
    //   <prefs xmlns='urn:xmpp:mam:1'/>
    // </iq>
    
    NSXMLElement *pref = [NSXMLElement elementWithName:@"prefs" xmlns:XMLNS_XMPP_ARCHIVE];
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get" to:nil elementID:nil child:pref];
    
    [sender sendElement:iq];
}

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
    NSString *type = [iq type];
    
    if ([type isEqualToString:@"result"])
    {
        NSXMLElement *pref = [iq elementForName:@"prefs" xmlns:XMLNS_XMPP_ARCHIVE];
        NSXMLElement *fin = [iq elementForName:@"fin" xmlns:XMLNS_XMPP_ARCHIVE];
        if (pref)
        {
            [self setPreferences:pref];
        }
        if (fin) {
            _syncState = XMPPMessageArchiveSyncStateNone;
            [multicastDelegate syncLocalMessageArchiveWithServerMessageArchiveDidFinished];
        }
    }
    return NO;
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    XMPPLogTrace();
    if ([self shouldArchiveMessage:message xmppStream:sender])
    {
        XMPPMessage *messageToSync = [self messageToSyncFromServerResponseMessage:message];
        [xmppMessageArchivingManagementStorage archiveMessage:messageToSync outgoing:[self isOutgoing:messageToSync] xmppStream:sender];
    }
}

- (void)xmppStream:(XMPPStream *)sender didSendIQ:(XMPPIQ *)iq
{
    if ([[iq elementID] isEqualToString:syncId]) {
        _syncState = XMPPMessageArchiveSyncStateWaitingForSyncResponse;
        [multicastDelegate syncLocalMessageArchiveWithServerMessageArchiveDidStarted];
        
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)shouldArchiveMessage:(XMPPMessage *)message xmppStream:(XMPPStream *)xmppStream
{
    // If the message id does not exist in local storage it should be added
    // A sync response message is in this format:
    
    //    <message id='aeb213' to='juliet@capulet.lit/chamber'>
    //      <result xmlns='urn:xmpp:mam:1' queryid='f27' id='28482-98726-73623'>
    //        <forwarded xmlns='urn:xmpp:forward:0'>
    //          <delay xmlns='urn:xmpp:delay' stamp='2010-07-10T23:08:25Z'/>
    //          <message xmlns='jabber:client' from="witch@shakespeare.lit" to="macbeth@shakespeare.lit">
    //            <body>Hail to thee</body>
    //          </message>
    //        </forwarded>
    //      </result>
    //    </message>
    
    //    <message xmlns="jabber:client" from="juliet@capulet.lit" to="juliet@capulet.lit/chamber" id="aeb215">
    //        <fin xmlns="urn:xmpp:mam:0" complete="true">
    //            <set xmlns="http://jabber.org/protocol/rsm">
    //                <first index="0">1</first>
    //                <last>2</last>
    //                <count>2</count>
    //            </set>
    //        </fin>
    //        <no-copy xmlns="urn:xmpp:hints"/>
    //    </message>
    
    if (_syncState == XMPPMessageArchiveSyncStateWaitingForSyncResponse || _syncState == XMPPMessageArchiveSyncStateSyncing) {
        if ([message elementsForName:@"result"].count > 0) {
            NSXMLElement* result = [[message elementsForName:@"result"] firstObject];
            if ([result xmlns] && [[result xmlns] isEqualToString:XMLNS_XMPP_ARCHIVE]) {
                _syncState = XMPPMessageArchiveSyncStateSyncing;
                return YES;
            }
        }
        else if ([message elementsForName:@"fin"] && [[[[message elementsForName:@"fin"] firstObject] xmlns] isEqualToString:XMLNS_XMPP_ARCHIVE])
        {
            _syncState = XMPPMessageArchiveSyncStateNone;
            [multicastDelegate syncLocalMessageArchiveWithServerMessageArchiveDidFinished];
        }
    }
    return NO;
}

- (XMPPMessage*) messageToSyncFromServerResponseMessage:(XMPPMessage *)message
{
    // If the message id does not exist in local storage it should be added
    // A sync response message is in this format:
    
    //    <message id='aeb213' to='juliet@capulet.lit/chamber'>
    //      <result xmlns='urn:xmpp:mam:1' queryid='f27' id='28482-98726-73623'>
    //        <forwarded xmlns='urn:xmpp:forward:0'>
    //          <delay xmlns='urn:xmpp:delay' stamp='2010-07-10T23:08:25Z'/>
    //          <message xmlns='jabber:client' from="witch@shakespeare.lit" to="macbeth@shakespeare.lit">
    //            <body>Hail to thee</body>
    //          </message>
    //        </forwarded>
    //      </result>
    //    </message>
    
    NSXMLElement* result = [[message elementsForName:@"result"] firstObject];
    NSXMLElement* forwarded = [[result elementsForName:@"forwarded"] firstObject];
    NSXMLElement* delay = [[forwarded elementsForName:@"delay"] firstObject];
    NSXMLElement* messageToSync = [[forwarded elementsForName:@"message"] firstObject];
    [messageToSync addChild:delay.copy];
    XMPPMessage* msgToSync = [XMPPMessage messageFromElement:messageToSync];
    return msgToSync;
}

- (BOOL) isOutgoing: (XMPPMessage*)message
{
    NSString* fromStr = [[message attributeForName:@"from"] stringValue];
    NSString* bareFrom = [[XMPPJID jidWithString:fromStr]bare];
    if ([bareFrom isEqualToString:[[xmppStream myJID] bare]]) {
        return YES;
    }
    return NO;
}

- (void) syncLocalMessageArchiveWithServerMessageArchive
{
    [self syncLocalMessageArchiveWithServerMessageArchiveWithBareJid:nil startTime:nil endTime:nil maxResultNumber:nil];
}

- (void) syncLocalMessageArchiveWithServerMessageArchiveWithBareJid: (NSString*)withBareJid startTime:(NSDate*)startTime endTime:(NSDate*)endTime maxResultNumber: (NSInteger*)maxResultNumber
{
    [self fetchArchivedMessagesWithBareJid:withBareJid startTime:startTime endTime:endTime maxResultNumber:maxResultNumber];
}

- (void) fetchArchivedMessagesWithBareJid: (NSString*)withBareJid startTime:(NSDate*)startTime endTime:(NSDate*)endTime maxResultNumber: (NSInteger*)maxResultNumber
{
    if (_syncState == XMPPMessageArchiveSyncStateNone) {
        XMPPLogTrace();
        
        //        <iq type='set' id='q29302'>
        //          <query xmlns='urn:xmpp:mam:1'>
        //            <x xmlns='jabber:x:data' type='submit'>
        //              <field var='FORM_TYPE' type='hidden'>
        //                <value>urn:xmpp:mam:1</value>
        //              </field>
        //              <field var='with'>
        //                <value>juliet@capulet.lit</value>
        //              </field>
        //              <field var='start'>
        //                <value>2010-08-07T00:00:00Z</value>
        //              </field>
        //              <field var='end'>
        //                <value>2010-07-07T13:23:54Z</value>
        //              </field>
        //            </x>
        //            <set xmlns='http://jabber.org/protocol/rsm'>
        //              <max>10</max>
        //            </set>
        //          </query>
        //        </iq>
        
        NSString* startTimeStr = @"";
        NSString* endTimeStr = @"";
        NSString* maxResultNumberStr = @"";
        if (startTime) startTimeStr = [startTime xmppDateTimeString];
        if (endTimeStr)  endTimeStr = [endTime xmppDateTimeString];
        if (maxResultNumberStr)  maxResultNumberStr = [NSString stringWithFormat:@"%ld",(long)maxResultNumber];
        
        syncId = [xmppStream generateUUID];
        
        // creating x item
        NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:XMLNS_XMPP_ARCHIVE];
        
        if (withBareJid || startTime || endTime) {
            NSXMLElement *x = [NSXMLElement elementWithName:@"x" xmlns:@"jabber:x:data"];
            [x addAttributeWithName:@"type" stringValue:@"submit"];
            
            NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
            [field addAttributeWithName:@"var" stringValue:@"FORM_TYPE"];
            [field addAttributeWithName:@"type" stringValue:@"hidden"];
            
            NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:XMLNS_XMPP_ARCHIVE];
            
            [field addChild:value];
            [x addChild:field];
            
            if (withBareJid && ![withBareJid isEqualToString:@""]) {
                NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
                [field addAttributeWithName:@"var" stringValue:@"with"];
                NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:withBareJid];
                [field addChild:value];
                [x addChild:field];
            }
            if (startTimeStr && ![startTimeStr isEqualToString:@""]) {
                NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
                [field addAttributeWithName:@"var" stringValue:@"start"];
                NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:startTimeStr];
                [field addChild:value];
                [x addChild:field];
            }
            if (endTimeStr && ![endTimeStr isEqualToString:@""]) {
                NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
                [field addAttributeWithName:@"var" stringValue:@"end"];
                NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:endTimeStr];
                [field addChild:value];
                [x addChild:field];
            }
            
            [query addChild:x];
            
            if (maxResultNumber && maxResultNumber > 0) {
                NSXMLElement *set = [NSXMLElement elementWithName:@"set" xmlns:@"http://jabber.org/protocol/rsm"];
                NSXMLElement *max = [NSXMLElement elementWithName:@"value" stringValue:maxResultNumberStr];
                [set addChild:max];
                [x addChild:set];
            }
        }
        
        XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:syncId child:query];
        [xmppStream sendElement:iq];
    }
    else
    {
        XMPPLogWarn(@"%@: Message syncing already in progress.", THIS_FILE);
    }
}

@end
