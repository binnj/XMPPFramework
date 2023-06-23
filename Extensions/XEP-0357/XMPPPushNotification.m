//
//  XMPPPushNotification.m
//  Dollarama
//
//  Created by binnj, inc. on 2016-02-11.
//  Copyright © 2016 binnj, inc. All rights reserved.
//

#import "XMPPPushNotification.h"
#import "XMPPLogging.h"
#import "XMPPConstants.h"

#if DEBUG
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN; // | XMPP_LOG_FLAG_TRACE;
#else
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

#define XMLNS_XMPP_PUSH_NOTIFICATION @"http://jabber.org/protocol/commands"
NSString *const XMPPPushNotificationErrorDomain = @"XMPPPushNotifacationErrorDomain";



@class XMPPIDTracker;

@implementation XMPPPushNotification

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)getServerConfigurationForPushNotifications
{
    NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:@"http://jabber.org/protocol/disco#info"];
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get" to:[xmppStream myJID].bareJID elementID:nil child:query];
    
    [xmppStream sendElement:iq];
}

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
    return YES;
}

- (void)processDiscoInfoResponse:(XMPPIQ *)iq
{
    XMPPLogTrace();
    
    /**
     <iq from='bill@example.net' to='bill@example.net/Home' id='x13' type='result'>
        <query xmlns='http://jabber.org/protocol/disco#info'>
            <x xmlns='jabber:x:data' type='result'>
                <field type='hidden' var='FORM_TYPE'><value>urn:xmpp:push:options</value></field>
                <field type='boolean' var='include-senders'><value>0</value></field>
                <field type='boolean' var='include-message-count'><value>1</value></field>
                <field type='boolean' var='include-subscription-count'><value>1</value></field>
                <field type='boolean' var='include-message-bodies'><value>0</value></field>
            </x>
            <identity category='account' type='registered'/>
            <feature var='http://jabber.org/protocol/disco#info'/>
            <feature var='urn:xmpp:push:0'/>
        </query>
     </iq>
     **/
    
    NSXMLElement *query = [iq elementForName:@"query" xmlns:@"http://jabber.org/protocol/disco#info"];
    NSArray *identities = [query elementsForName:@"identity"];
    
    BOOL found = NO;
    
    NSUInteger i;
    for(i = 0; i < [identities count] && !found; i++)
    {
        NSXMLElement *identity = identities[i];
        
        NSString *category = [[identity attributeForName:@"category"] stringValue];
        NSString *type = [[identity attributeForName:@"type"] stringValue];
        
        if([category isEqualToString:@"proxy"] && [type isEqualToString:@"bytestreams"])
        {
            found = YES;
        }
    }
    
    if(found)
    {
    }
    else
    {
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)setServerConfigurationForPushNotification
{
    
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/**
 <iq type='set' id='x43'>
    <enable xmlns='urn:xmpp:push:0' jid='push.myserver.com' node='yxs32uqsflafdk3iuqo'>
        <x xmlns='jabber:x:data'>
            <field var='FORM_TYPE'><value>http://jabber.org/protocol/pubsub#publish-options</value></field>
            <field var='secret'><value>eruio234vzxc2kla-91<value></field>
        </x>
    </enable>
</iq>
 **/
- (void)enablePushNotification
{
    NSString* host = [xmppStream hostName];
    NSString* pushHost = [NSString stringWithFormat:@"push.%@",host];
    
    NSXMLElement *enable = [NSXMLElement elementWithName:@"enable" xmlns:@"urn:xmpp:push:0"];
    [enable addAttributeWithName:@"jid" stringValue:pushHost];
    [enable addAttributeWithName:@"node" stringValue:@""];
    
    NSXMLElement *x = [NSXMLElement elementWithName:@"x" xmlns:@"jabber:x:data"];
    
    NSXMLElement *field1 = [NSXMLElement elementWithName:@"field"];
    [field1 addAttributeWithName:@"var" stringValue:@"FORM_TYPE"];
    NSXMLElement *value1 = [NSXMLElement elementWithName:@"value" stringValue:@"http://jabber.org/protocol/pubsub#publish-options"];
    
    NSXMLElement *field2 = [NSXMLElement elementWithName:@"field"];
    [field2 addAttributeWithName:@"var" stringValue:@"secret"];
    NSXMLElement *value2 = [NSXMLElement elementWithName:@"value" stringValue:@""];
    
    [field1 addChild: value1];
    [field2 addChild: value2];
    [x addChild: field1];
    [x addChild:field2];
    [enable addChild:x];
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"set" child:enable];
    [xmppStream sendElement:iq];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark request for device token registration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 <iq type='set' to='example.net' id='exec1'>
    <command xmlns='http://jabber.org/protocol/commands'
        node='register-push-apns'
        action='execute'>
    <x xmlns='jabber:x:data' type='submit'>
        <field var='token'>
            <value>r3qpHKmzZHjYKYbG7yI4fhY+DWKqFZE5ZJEM8P+lDDo=</value>
        </field>
        <field var='device-name'>
            <value>Home</value>
        </field>
    </x>
    </command>
 </iq>
 **/

- (void)registerPushNotificationForDeviceToken:(NSString*)deviceToken deviceName:(NSString*)deviceName
{
    NSXMLElement *command = [NSXMLElement elementWithName:@"command" xmlns:XMLNS_XMPP_PUSH_NOTIFICATION];
    [command addAttributeWithName:@"node" stringValue:@"register-push-apns"];
    [command addAttributeWithName:@"action" stringValue:@"execute"];
    
    NSXMLElement *x = [NSXMLElement elementWithName:@"x" xmlns:@"jabber:x:data"];
    [x addAttributeWithName:@"type" stringValue:@"submit"];
    
    NSXMLElement *field = [NSXMLElement elementWithName:@"field"];
    [field addAttributeWithName:@"var" stringValue:@"token"];
    NSXMLElement *value = [NSXMLElement elementWithName:@"value" stringValue:deviceToken];
    
    NSXMLElement *field2 = [NSXMLElement elementWithName:@"field"];
    [field2 addAttributeWithName:@"var" stringValue:@"device-name"];
    NSXMLElement *value2 = [NSXMLElement elementWithName:@"value" stringValue:deviceName];
    
    [field addChild: value];
    [field2 addChild: value2];
    [x addChild: field];
    [x addChild:field2];
    [command addChild:x];
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"set" to:[XMPPJID jidWithString:[xmppStream hostName]] elementID:nil child:command];
    [xmppStream sendElement:iq];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark request for device token unregistration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)unregisterPushNotificationForDeviceToken:(NSString*)deviceToken deviceName:(NSString*)deviceName
{
    
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSArray*)getRegisteredDeviceList
{
    return nil;
}

@end
