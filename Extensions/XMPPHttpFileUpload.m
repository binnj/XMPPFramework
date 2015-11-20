//
//  XMPPHttpFileUpload.m
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-18.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import "XMPPHttpFileUpload.h"
#import "XMPPLogging.h"
#import "XMPPNamespaces.h"

#if DEBUG
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN; // | XMPP_LOG_FLAG_TRACE;
#else
static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

#define XMLNS_XMPP_HTTP_FILE_UPLOAD @"urn:xmpp:http:upload"
NSString *const XMPPFileUploadErrorDomain = @"XMPPFileUploadErrorDomain";

@class XMPPIDTracker;

@interface XMPPHttpFileUpload()
{
    XMPPIDTracker *xmppIDTracker;
    
    BOOL hasRequestedServices;
    BOOL hasRequestedUploadServices;
    BOOL hasRequestedSlot;
    
    NSString* requestedServiceId;
    NSString* requestedUploadServiceId;
    NSString* requestedSlotId;
    
    BOOL hasService;
    BOOL hasUploadService;
    
    NSString* uploadServiceJid;
    
    XMPPHttpFileUploadObject* httpFileUploadObject;
}
@end

@implementation XMPPHttpFileUpload

- (id)init
{
    // This will cause a crash - it's designed to.
    return [self initWithDispatchQueue:dispatch_get_main_queue()];
}
- (id)initWithDispatchQueue:(dispatch_queue_t)queue
{
    self = [super initWithDispatchQueue:queue];
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
#pragma mark request for file upload permission
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) requestFileUpload:(NSString*)fileName fileSize:(long)fileSize contentType:(NSString*)contentType
{
    if (!hasService) [self discoverServices];
    else if (!hasUploadService) [self discoverUploadService];
    else [self requestSlotForFile:fileName fileSize:fileSize contentType:contentType];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Client sends service discovery request to server
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * <iq from='hag66@shakespeare.lit/pda'
 *       id='h7ns81g'
 *       to='shakespeare.lit'
 *     type='get'>
 *   <query xmlns='http://jabber.org/protocol/disco#items'/>
 * </iq>
 */
- (void)discoverServices
{
    if (hasRequestedServices) return; // We've already requested services
    
    NSString *toStr = xmppStream.myJID.domain;
    requestedServiceId = [xmppStream generateUUID];
    NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                  xmlns:XMPPDiscoItemsNamespace];
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                 to:[XMPPJID jidWithString:toStr]
                          elementID:requestedServiceId
                              child:query];
    
    [xmppStream sendElement:iq];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Server replies to service discovery request
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//<iq from='montague.tld'
//    id='step_01'
//    to='romeo@montague.tld/garden'
//  <query xmlns='http://jabber.org/protocol/disco#items'>
//    <item jid='upload.montague.tld' name='HTTP File Upload' />
//    <item jid='conference.montague.tld' name='Chatroom Service' />
//  </query>
//</iq>
- (void)handleDiscoverServicesQueryIQ:(XMPPIQ *)iq
{
    NSXMLElement *errorElem = [iq elementForName:@"error"];
    hasRequestedServices = NO; // Set this back to NO to allow for future requests
    
    if (errorElem) {
        NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
        NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
        NSError *error = [NSError errorWithDomain:XMPPFileUploadErrorDomain
                                             code:[errorElem attributeIntegerValueForName:@"code"
                                                                         withDefaultValue:0]
                                         userInfo:dict];
        //what to do in case of error?
        return;
    }
    
    NSXMLElement *query = [iq elementForName:@"query"
                                       xmlns:XMPPDiscoItemsNamespace];
    
    NSArray *items = [query elementsForName:@"item"];
    for (NSXMLElement* item in items){
        if ([[[item attributeForName:@"jid"] stringValue] isEqualToString:[NSString stringWithFormat:@"upload.%@",xmppStream.hostName]]) {
            uploadServiceJid = [[item attributeForName:@"jid"] stringValue];
            hasService = YES;
            [self discoverUploadService];
            break;
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  service discorvey request to upload service
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * <iq from='romeo@montague.tld/garden
 *     id='step_02'
 *     to='upload.montague.tld'
 *     type='get'>
 *   <query xmlns='http://jabber.org/protocol/disco#info'/>
 * </iq>
 */
- (void)discoverUploadService
{
    if (hasRequestedUploadServices) return; // We've already requested services
    
    NSString *toStr = uploadServiceJid;
    requestedUploadServiceId = [xmppStream generateUUID];
    NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                  xmlns:XMPPDiscoItemsNamespace];
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                 to:[XMPPJID jidWithString:toStr]
                          elementID:requestedUploadServiceId
                              child:query];
    
    [xmppStream sendElement:iq];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Upload service replies to service discovery request
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*
 *    <iq from='upload.montague.tld
 *        id='step_02'
 *        to='romeo@montague.tld/garden'
 *        type='result'>
 *      <query xmlns='http://jabber.org/protocol/disco#info'>
 *        <identity category='store'
 *                  type='file'
 *                  name='HTTP File Upload' />
 *        <feature var='urn:xmpp:http:upload' />
 *      </query>
 *    </iq>
 */
- (void)handleDiscoverUploadServicesQueryIQ:(XMPPIQ *)iq
{
    NSXMLElement *errorElem = [iq elementForName:@"error"];
    hasRequestedUploadServices = NO; // Set this back to NO to allow for future requests
    
    if (errorElem) {
        NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
        NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
        NSError *error = [NSError errorWithDomain:XMPPFileUploadErrorDomain
                                             code:[errorElem attributeIntegerValueForName:@"code"
                                                                         withDefaultValue:0]
                                         userInfo:dict];
        //what to do in case of error?
        return;
    }
    
    NSXMLElement *query = [iq elementForName:@"query"
                                       xmlns:XMPPDiscoItemsNamespace];
    
    NSArray *features = [query elementsForName:@"feature"];
    for (NSXMLElement* feature in features){
        if ([XMLNS_XMPP_HTTP_FILE_UPLOAD isEqualToString:[[feature attributeForName:@"var"] stringValue]]) {
            [self requestSlotForFile:httpFileUploadObject.fileName fileSize:httpFileUploadObject.fileSize contentType:httpFileUploadObject.contentType];
            hasUploadService = YES;
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark  Client requests a slot on the upload service
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 *
 * <iq from='romeo@montague.tld/garden
 *     id='step_03'
 *     to='upload.montague.tld'
 *     type='get'>
 *   <request 'urn:xmpp:http:upload'>
 *     <filename>my_juliet.png</filename>
 *     <size>23456</size>
 *     <content-type>image/jpeg</content-type>
 *   </request>
 * </iq>
 */
- (void)requestSlotForFile:(NSString*)fileName fileSize:(long)fileSize contentType:(NSString*)contentType
{
    // This is a public method, so it may be invoked on any thread/queue.
    
    httpFileUploadObject = [[XMPPHttpFileUploadObject alloc]init];
    httpFileUploadObject.fileName = fileName;
    httpFileUploadObject.fileSize = fileSize;
    httpFileUploadObject.contentType = contentType;
    
    NSString *toStr = uploadServiceJid;
    requestedSlotId = [xmppStream generateUUID];
    NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                  xmlns:XMPPDiscoItemsNamespace];
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                 to:[XMPPJID jidWithString:toStr]
                          elementID:[xmppStream generateUUID]
                              child:query];
    
    NSXMLElement* request = [NSXMLElement elementWithName:@"request" xmlns:XMLNS_XMPP_HTTP_FILE_UPLOAD];
    NSXMLElement* filename = [NSXMLElement elementWithName:@"filename" stringValue:fileName];
    NSXMLElement* filesize = [NSXMLElement elementWithName:@"size" stringValue:[NSString stringWithFormat:@"%ld",fileSize]];
    NSXMLElement* contenttype = [NSXMLElement elementWithName:@"content-type" stringValue:contentType];
    [request addChild:filename];
    [request addChild:filesize];
    [request addChild:contenttype];
    
    [iq addChild:request];
    
    [xmppStream sendElement:iq];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark The upload service responsd with a slot
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*
 *    <iq from='upload.montague.tld
 *       id='step_03'
 *       to='romeo@montague.tld/garden
 *       type='result'>
 *     <slot xmlns='urn:xmpp:http:upload'>
 *       <put>https://upload.montague.tld/4a771ac1-f0b2-4a4a-9700-f2a26fa2bb67/my_juliet.png</put>
 *       <get>https://download.montague.tld/4a771ac1-f0b2-4a4a-9700-f2a26fa2bb67/my_juliet.png</get>
 *     </slot>
 *    </iq>
 */
- (void)handleSlotRequestQueryIQ:(XMPPIQ *)iq
{
    NSXMLElement *errorElem = [iq elementForName:@"error"];
    
    if (errorElem) {
        NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
        NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
        NSError *error = [NSError errorWithDomain:XMPPFileUploadErrorDomain
                                             code:[errorElem attributeIntegerValueForName:@"code"
                                                                         withDefaultValue:0]
                                         userInfo:dict];
        //what to do in case of error?
        return;
    }
    
    NSXMLElement *slot = [iq elementForName:@"slot" xmlns:XMLNS_XMPP_HTTP_FILE_UPLOAD];
    
    NSString* getURLStr;
    NSString* putURLStr;
    
    for (NSXMLElement* child in [slot children]) {
        if ([[child name] isEqualToString:@"put"]) putURLStr = [child stringValue];
        if ([[child name] isEqualToString:@"get"]) getURLStr = [child stringValue];
    }
    
    if (putURLStr) httpFileUploadObject.putURL = [NSURL URLWithString:putURLStr];
    if (getURLStr) httpFileUploadObject.getURL = [NSURL URLWithString:getURLStr];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
    if ([[iq elementID] isEqualToString:requestedServiceId]) {
        [self handleDiscoverServicesQueryIQ:iq];
        return YES;
    }
    else if ([[iq elementID] isEqualToString:requestedUploadServiceId]) {
        [self handleDiscoverUploadServicesQueryIQ:iq];
        return YES;
    }
    else if ([[iq elementID] isEqualToString:requestedSlotId]) {
        [self handleSlotRequestQueryIQ:iq];
        return YES;
    }
    
    return NO;
}

- (void)xmppStream:(XMPPStream *)sender didSendIQ:(XMPPIQ *)iq
{
    if ([[iq elementID] isEqualToString:requestedServiceId]) {
        hasRequestedServices = YES;
    }
    else if ([[iq elementID] isEqualToString:requestedUploadServiceId]) {
        hasRequestedUploadServices = YES;
    }
    else if ([[iq elementID] isEqualToString:requestedSlotId]) {
        hasRequestedSlot = YES;
    }
}

@end
