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


@interface XMPPMessageArchiveManagement (private)
@end

@implementation XMPPMessageArchiveManagement

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
        
        NSString* startTimeStr = [startTime xmppDateTimeString];
        NSString* endTimeStr = [endTime xmppDateTimeString];
        NSString* maxResultNumberStr = [NSString stringWithFormat:@"%ld",(long)maxResultNumber];
        
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
                       timeout:60.0];
        
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
