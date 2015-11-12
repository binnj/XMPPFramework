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

@implementation XMPPMessageArchiveManagement

- (id)init
{
    // This will cause a crash - it's designed to.
    // Only the init methods listed in XMPPMessageArchiving.h are supported.
    
    return [self initWithMessageArchivingStorage:nil dispatchQueue:NULL];
}

- (id)initWithDispatchQueue:(dispatch_queue_t)queue
{
    // This will cause a crash - it's designed to.
    // Only the init methods listed in XMPPMessageArchiving.h are supported.
    
    return [self initWithMessageArchivingStorage:nil dispatchQueue:queue];
}

- (id)initWithMessageArchivingStorage:(id <XMPPMessageArchivingStorage>)storage
{
    return [self initWithMessageArchivingStorage:storage dispatchQueue:NULL];
}

- (id)initWithMessageArchivingStorage:(id <XMPPMessageArchivingStorage>)storage dispatchQueue:(dispatch_queue_t)queue
{
    NSParameterAssert(storage != nil);
    
    if ((self = [super initWithDispatchQueue:queue]))
    {
        if ([storage configureWithParent:self queue:moduleQueue])
        {
            xmppMessageArchivingStorage = storage;
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
    
    // Reserved for future potential use
    
    [super deactivate];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id <XMPPMessageArchivingStorage>)xmppMessageArchivingStorage
{
    // Note: The xmppMessageArchivingStorage variable is read-only (set in the init method)
    
    return xmppMessageArchivingStorage;
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
        
        preferences = [newPreferences copy];
        
        // Update storage
        
        if ([xmppMessageArchivingStorage respondsToSelector:@selector(setPreferences:forUser:)])
        {
            XMPPJID *myBareJid = [[xmppStream myJID] bareJID];
            
            [xmppMessageArchivingStorage setPreferences:preferences forUser:myBareJid];
        }
        
        //  - Send new pref to server
        XMPPIQ *iq = [XMPPIQ iqWithType:@"set" to:nil elementID:nil child:preferences];
        [xmppStream sendElement:iq];
        
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
    
    if ([xmppMessageArchivingStorage respondsToSelector:@selector(preferencesForUser:)])
    {
        XMPPJID *myBareJid = [[xmppStream myJID] bareJID];
        
        preferences = [xmppMessageArchivingStorage preferencesForUser:myBareJid];
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
        if (pref)
        {
            [self setPreferences:pref];
        }
    }
    return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void) syncLocalMessageArchiveWithServerMessageArchive
{
    dispatch_block_t block = ^{ @autoreleasepool {
        [self syncLocalMessageArchiveWithServerMessageArchiveWithBareJid:nil startTime:nil endTime:nil maxResultNumber:nil];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

- (void) syncLocalMessageArchiveWithServerMessageArchiveWithBareJid: (NSString*)withBareJid startTime:(NSDate*)startTime endTime:(NSDate*)endTime maxResultNumber: (NSInteger*)maxResultNumber
{
    dispatch_block_t block = ^{ @autoreleasepool {
        [self fetchArchivedMessagesWithBareJid:withBareJid startTime:startTime endTime:endTime maxResultNumber:maxResultNumber];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
    
}

- (void) fetchArchivedMessagesWithBareJid: (NSString*)withBareJid startTime:(NSDate*)startTime endTime:(NSDate*)endTime maxResultNumber: (NSInteger*)maxResultNumber
{
    dispatch_block_t block = ^{ @autoreleasepool {
        
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
        
        NSString *fetchID = [xmppStream generateUUID];
        
        // creating x item
        NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:@"urn:xmpp:mam:1"];
        NSXMLElement *x = [NSXMLElement elementWithName:@"x" xmlns:@"jabber:x:data"];
        [x addAttributeWithName:@"type" stringValue:@"submit"];
        
        NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
        [field addAttributeWithName:@"var" stringValue:@"FORM_TYPE"];
        [field addAttributeWithName:@"type" stringValue:@"hidden"];
        
        NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:@"urn:xmpp:mam:1"];
        
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
        
        //creating set otem
        if (maxResultNumber && maxResultNumber > 0) {
            NSXMLElement *set = [NSXMLElement elementWithName:@"set" xmlns:@"http://jabber.org/protocol/rsm"];
            NSXMLElement *max = [NSXMLElement elementWithName:@"value" stringValue:maxResultNumberStr];
            [set addChild:max];
            [x addChild:set];
        }
        
        XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:fetchID child:query];
        
        [xmppStream sendElement:iq];
        
        [responseTracker addID:fetchID
                        target:self
                      selector:@selector(handleFetchArchivedMessageResponse:withInfo:)
                       timeout:600.0];
        
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
    
}

- (void)handleFetchArchivedMessageResponse:(XMPPIQ *)iq withInfo:(id <XMPPTrackingInfo>)info
{
    XMPPLogTrace();
    
    if ([[iq type] isEqualToString:@"result"])
    {
    }
    else
    {
    }
}

@end
