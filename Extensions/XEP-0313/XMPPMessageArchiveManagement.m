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
#define XMLNS_XMPP_RSM @"http://jabber.org/protocol/rsm"

// XMPP Incoming File Transfer State
typedef NS_ENUM(int, XMPPMessageArchiveSyncState) {
    XMPPMessageArchiveSyncStateNone,
    XMPPMessageArchiveSyncStateWaitingForSyncResponse,
    XMPPMessageArchiveSyncStateSyncing
};

@interface XMPPMessageArchiveManagement()
{
    XMPPMessageArchiveSyncState _syncState;
    NSString *_syncId;
    NSString *_userBareJid;
    NSDate *_syncStartDate;
    NSDate *_syncEndDate;
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
        
        result = [self->preferences copy];
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
        if (![newPreferences.XMLString isEqualToString:self->preferences.XMLString]) {
            
            self->preferences = [newPreferences copy];
            
            // Update storage
            
            if ([self->xmppMessageArchivingManagementStorage respondsToSelector:@selector(setPreferences:forUser:)])
            {
                XMPPJID *myBareJid = [[self->xmppStream myJID] bareJID];
                
                [self->xmppMessageArchivingManagementStorage setPreferences:self->preferences forUser:myBareJid];
            }
            
            //  - Send new pref to server
            XMPPIQ *iq = [XMPPIQ iqWithType:@"set" to:nil elementID:nil child:self->preferences];
            [self->xmppStream sendElement:iq];
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


- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error
{
    _syncState = XMPPMessageArchiveSyncStateNone;
}

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
    /*
     <iq xmlns="jabber:client" lang="en" to="mlalonde@dollarama-ejabberd-test.binnj.com/1435327366947397074538147" from="mlalonde@dollarama-ejabberd-test.binnj.com" type="result" id="D72B705B-F4DC-40DA-AA2A-72BF08960F7A">
         <fin xmlns="urn:xmpp:mam:1" complete="true" queryid="68008622-B324-4CAE-96D3-13D29A86780E">
             <set xmlns="http://jabber.org/protocol/rsm">
                 <count>0</count>
             </set>
         </fin>
     </iq>
     */
    NSString *type = [iq type];
    NSXMLElement *fin = [iq elementForName:@"fin" xmlns:XMLNS_XMPP_ARCHIVE];
    if ([type isEqualToString:@"result"] && fin)
    {
        NSXMLElement *set = [fin elementForName:@"set" xmlns:XMLNS_XMPP_RSM];
        NSInteger count = [[set elementForName:@"count"] stringValueAsInt];
        _syncState = XMPPMessageArchiveSyncStateNone;
        [multicastDelegate syncLocalMessageArchiveWithServerMessageArchiveDidFinishedWithCount:count];
        [self setSyncFromDate:_syncStartDate forUser:_userBareJid];
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
    if (_syncId && [[iq elementID] isEqualToString:_syncId]) {
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
    
    if ([message elementsForName:@"result"].count > 0) {
        NSXMLElement* result = [[message elementsForName:@"result"] firstObject];
        if ([result xmlns] && [[result xmlns] isEqualToString:XMLNS_XMPP_ARCHIVE]) {
            return YES;
        }
    }
    else if ([message elementsForName:@"fin"] && [[[[message elementsForName:@"fin"] firstObject] xmlns] isEqualToString:XMLNS_XMPP_ARCHIVE])
    {
        NSXMLElement *fin = [message elementForName:@"fin" xmlns:XMLNS_XMPP_ARCHIVE];
        NSXMLElement *set = [fin elementForName:@"set" xmlns:XMLNS_XMPP_RSM];
        NSInteger count = [[set elementForName:@"count"] stringValueAsInt];
        _syncState = XMPPMessageArchiveSyncStateNone;
        [multicastDelegate syncLocalMessageArchiveWithServerMessageArchiveDidFinishedWithCount:count];
        [self setSyncFromDate:_syncStartDate forUser:_userBareJid];
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

- (NSDate *)lastSyncDateForUser:(NSString *)userBareJid
{
    NSString *forUser = userBareJid ? [NSString stringWithFormat:@"_%@", userBareJid] : @"";
    NSString* kLastSyncDate = [NSString stringWithFormat:@"LastSyncDate_%@%@", xmppStream.myJID.bare, forUser];
    return [[NSUserDefaults standardUserDefaults] objectForKey:kLastSyncDate];
}

- (void)setSyncFromDate:(NSDate *)syncDate forUser:(NSString *)userBareJid
{
    NSString *forUser = userBareJid ? [NSString stringWithFormat:@"_%@", userBareJid] : @"";
    NSString* kLastSyncDate = [NSString stringWithFormat:@"LastSyncDate_%@%@", xmppStream.myJID.bare, forUser];
    [[NSUserDefaults standardUserDefaults] setObject:syncDate forKey:kLastSyncDate];
}

- (void) syncLocalMessageArchiveWithServerMessageArchive
{
    [self syncLocalMessageArchiveWithServerMessageArchiveWithBareJid:nil startTime:nil endTime:nil];
}

- (void) syncLocalMessageArchiveWithServerMessageArchiveWithBareJid:(NSString*)withBareJid startTime:(NSDate*)startTime endTime:(NSDate*)endTime
{
    [self fetchArchivedMessagesWithBareJid:withBareJid startTime:startTime endTime:endTime];
}

- (void) fetchArchivedMessagesWithBareJid: (NSString*)withBareJid startTime:(NSDate*)startTime endTime:(NSDate*)endTime
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
        
        _syncId = [xmppStream generateUUID];
        _userBareJid = withBareJid;
        _syncEndDate = endTime;
        _syncStartDate = startTime;
        NSString *startTimeStr = startTime ? [startTime xmppDateTimeString] : @"";
        NSString *endTimeStr = endTime ? [endTime xmppDateTimeString] : @"";
        
        NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:XMLNS_XMPP_ARCHIVE];
        [query addAttribute:[DDXMLNode attributeWithName:@"queryid" stringValue:[xmppStream generateUUID]]];
        
        // creating x item
        if (withBareJid.length > 0 || startTimeStr.length > 0 || endTimeStr.length > 0) {
            NSXMLElement *x = [NSXMLElement elementWithName:@"x" xmlns:@"jabber:x:data"];
            [x addAttributeWithName:@"type" stringValue:@"submit"];
            
            NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
            [field addAttributeWithName:@"var" stringValue:@"FORM_TYPE"];
            [field addAttributeWithName:@"type" stringValue:@"hidden"];
            
            NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:XMLNS_XMPP_ARCHIVE];
            
            [field addChild:value];
            [x addChild:field];
            
            if (withBareJid.length > 0) {
                NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
                [field addAttributeWithName:@"var" stringValue:@"with"];
                NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:withBareJid];
                [field addChild:value];
                [x addChild:field];
            }
            if (startTimeStr.length > 0) {
                NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
                [field addAttributeWithName:@"var" stringValue:@"start"];
                NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:startTimeStr];
                [field addChild:value];
                [x addChild:field];
            }
            if (endTimeStr.length > 0) {
                NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
                [field addAttributeWithName:@"var" stringValue:@"end"];
                NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:endTimeStr];
                [field addChild:value];
                [x addChild:field];
            }
            
            [query addChild:x];
        }
        
        XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:_syncId child:query];
        [xmppStream sendElement:iq];
    }
    else
    {
        XMPPLogWarn(@"%@: Message syncing already in progress.", THIS_FILE);
    }
}

@end
