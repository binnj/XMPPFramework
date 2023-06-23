//
//  XMPPHttpFileUpload.m
//  supDawg
//
//  Created by binnj, inc. on 2015-11-18.
//  Copyright © 2015 binnj, inc. All rights reserved.
//

#import "XMPPHttpFileUpload.h"
#import "XMPPLogging.h"
#import "XMPPConstants.h"

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
    
    BOOL hasService;
    BOOL hasUploadService;
    
    NSString* uploadServiceJid;
}
@property (nonatomic, strong) NSMutableDictionary* httpFileUploadObjs;

@end

@implementation XMPPHttpFileUpload
@synthesize httpFileUploadObjs;

- (id)init
{
    // This will cause a crash - it's designed to.
    return [self initWithDispatchQueue:dispatch_get_main_queue()];
}
- (id)initWithDispatchQueue:(dispatch_queue_t)queue
{
    httpFileUploadObjs = [[NSMutableDictionary alloc]init];
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
- (void) requestFileUpload:(XMPPHttpFileUploadObject*) httpFileUploadObject
{
    NSString* requestedId = [xmppStream generateUUID];
    httpFileUploadObjs [requestedId] = httpFileUploadObject;
    httpFileUploadObject.status = XMPPHttpFileUploadStatusNone;
    
    if (!hasService) [self discoverServices:requestedId];
//    else if (!hasUploadService) [self discoverUploadService:requestedId];
    else [self requestSlotForFile:requestedId];
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
- (void)discoverServices: (NSString*) requestId
{
    XMPPHttpFileUploadObject* httpFileUploadObject = httpFileUploadObjs [requestId];
    if (httpFileUploadObject.status == XMPPHttpFileUploadStatusServiceRequestedSent || httpFileUploadObject.status == XMPPHttpFileUploadStatusServiceRequested) return;
    
    httpFileUploadObject.status = XMPPHttpFileUploadStatusServiceRequestedSent;
    
    NSString *toStr = xmppStream.myJID.domain;
    NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                  xmlns:XMPPDiscoItemsNamespace];
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                 to:[XMPPJID jidWithString:toStr]
                          elementID:requestId
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
    XMPPHttpFileUploadObject* httpFileUploadObject = httpFileUploadObjs [[iq elementID]];
    
    if (errorElem) {
        NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
        NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
        NSError *error = [NSError errorWithDomain:XMPPFileUploadErrorDomain
                                             code:[errorElem attributeIntegerValueForName:@"code"
                                                                         withDefaultValue:0]
                                         userInfo:dict];
        httpFileUploadObject.status = XMPPHttpFileUploadStatusNoService;
        [multicastDelegate xmppHttpFileUpload:self didNotReceiveURL:httpFileUploadObject withError:error];
        return;
    }
    
    NSXMLElement *query = [iq elementForName:@"query"
                                       xmlns:XMPPDiscoItemsNamespace];
    
    NSArray *items = [query elementsForName:@"item"];
    for (NSXMLElement* item in items){
        if ([[[item attributeForName:@"jid"] stringValue] isEqualToString:[NSString stringWithFormat:@"upload.%@",xmppStream.hostName]]) {
            uploadServiceJid = [[item attributeForName:@"jid"] stringValue];
            hasService = YES;
            httpFileUploadObject.status = XMPPHttpFileUploadStatusHasService;
            //[self discoverUploadService:[iq elementID]];
            [self requestSlotForFile:[iq elementID]];
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
- (void)discoverUploadService: (NSString*) requestId
{
    XMPPHttpFileUploadObject* httpFileUploadObject = httpFileUploadObjs [requestId];
    if (httpFileUploadObject.status == XMPPHttpFileUploadStatusUploadServiceRequestedSent || httpFileUploadObject.status == XMPPHttpFileUploadStatusUploadServiceRequested) return;
    
    httpFileUploadObject.status = XMPPHttpFileUploadStatusUploadServiceRequestedSent;
    
    NSString *toStr = uploadServiceJid;
    NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                  xmlns:XMPPDiscoItemsNamespace];
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                 to:[XMPPJID jidWithString:toStr]
                          elementID:requestId
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
    XMPPHttpFileUploadObject* httpFileUploadObject = httpFileUploadObjs [[iq elementID]];
    
    if (errorElem) {
        NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
        NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
        NSError *error = [NSError errorWithDomain:XMPPFileUploadErrorDomain
                                             code:[errorElem attributeIntegerValueForName:@"code"
                                                                         withDefaultValue:0]
                                         userInfo:dict];
        httpFileUploadObject.status = XMPPHttpFileUploadStatusNoUploadService;
        [httpFileUploadObjs removeObjectForKey:[iq elementID]];
        [multicastDelegate xmppHttpFileUpload:self didNotReceiveURL:httpFileUploadObject withError:error];
        return;
    }
    
    NSXMLElement *query = [iq elementForName:@"query"
                                       xmlns:XMPPDiscoItemsNamespace];
    
    NSArray *features = [query elementsForName:@"feature"];
    for (NSXMLElement* feature in features){
        if ([XMLNS_XMPP_HTTP_FILE_UPLOAD isEqualToString:[[feature attributeForName:@"var"] stringValue]]) {
            [self requestSlotForFile:[iq elementID]];
            hasUploadService = YES;
            httpFileUploadObject.status = XMPPHttpFileUploadStatusHasUploadService;
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
- (void)requestSlotForFile: (NSString*) requestId
{
    XMPPHttpFileUploadObject* httpFileUploadObject = httpFileUploadObjs [requestId];
    if (httpFileUploadObject.status == XMPPHttpFileUploadStatusUploadSlotRequestedSent || httpFileUploadObject.status == XMPPHttpFileUploadStatusUploadSlotRequested) return;
    
    httpFileUploadObject.status = XMPPHttpFileUploadStatusUploadSlotRequestedSent;
    
    XMPPHttpFileUploadObject* httpFileUploadObj = httpFileUploadObjs [requestId];
    
    NSString *toStr = uploadServiceJid;
    NSXMLElement* request = [NSXMLElement elementWithName:@"request" xmlns:XMLNS_XMPP_HTTP_FILE_UPLOAD];
    NSXMLElement* filename = [NSXMLElement elementWithName:@"filename" stringValue:httpFileUploadObj.fileName];
    NSXMLElement* filesize = [NSXMLElement elementWithName:@"size" stringValue:[NSString stringWithFormat:@"%ld",httpFileUploadObj.fileSize]];
    NSXMLElement* contentType = [NSXMLElement elementWithName:@"content-type" stringValue:httpFileUploadObj.contentType];
    [request addChild:filename];
    [request addChild:filesize];
    [request addChild:contentType];
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                 to:[XMPPJID jidWithString:toStr]
                          elementID:requestId
                              child:request];
    
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
    
    XMPPHttpFileUploadObject* httpFileUploadObject = httpFileUploadObjs [[iq elementID]];
    
    if (errorElem) {
        NSString *errMsg = [errorElem.children componentsJoinedByString:@", "];
        NSDictionary *dict = @{NSLocalizedDescriptionKey : errMsg};
        NSError *error = [NSError errorWithDomain:XMPPFileUploadErrorDomain
                                             code:[errorElem attributeIntegerValueForName:@"code"
                                                                         withDefaultValue:0]
                                         userInfo:dict];
        httpFileUploadObject.status = XMPPHttpFileUploadStatusNoUploadSlot;
        [httpFileUploadObjs removeObjectForKey:[iq elementID]];
        [multicastDelegate xmppHttpFileUpload:self didNotReceiveURL:httpFileUploadObject withError:error];
        return;
    }
    
    NSXMLElement *slot = [iq elementForName:@"slot" xmlns:XMLNS_XMPP_HTTP_FILE_UPLOAD];
    
    NSString* getURLStr;
    NSString* putURLStr;
    
    for (NSXMLElement* child in [slot children]) {
        if ([[child name] isEqualToString:@"put"]) putURLStr = [child stringValue];
        if ([[child name] isEqualToString:@"get"]) getURLStr = [child stringValue];
    }
    
    httpFileUploadObject.status = XMPPHttpFileUploadStatusCompleted;
    [httpFileUploadObjs removeObjectForKey:[iq elementID]];
    httpFileUploadObject.putURL = [NSURL URLWithString:putURLStr];
    httpFileUploadObject.getURL = [NSURL URLWithString:getURLStr];
    
    [multicastDelegate xmppHttpFileUpload:self didReceiveURL: httpFileUploadObject];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
    if (httpFileUploadObjs[[iq elementID]]) {
        
        XMPPHttpFileUploadObject* httpFileUploadObject = httpFileUploadObjs [[iq elementID]];
        if (httpFileUploadObject.status == XMPPHttpFileUploadStatusServiceRequested) {
            [self handleDiscoverServicesQueryIQ:iq];
            return YES;
        }
        else if (httpFileUploadObject.status == XMPPHttpFileUploadStatusUploadServiceRequested)
        {
            [self handleDiscoverUploadServicesQueryIQ:iq];
            return YES;
        }
        else if (httpFileUploadObject.status == XMPPHttpFileUploadStatusUploadSlotRequested)
        {
            [self handleSlotRequestQueryIQ:iq];
            return YES;
        }
    }
    
    return NO;
}

- (void)xmppStream:(XMPPStream *)sender didSendIQ:(XMPPIQ *)iq
{
    if (httpFileUploadObjs[[iq elementID]]) {
        XMPPHttpFileUploadObject* httpFileUploadObject = httpFileUploadObjs [[iq elementID]];
        
        if (httpFileUploadObject.status == XMPPHttpFileUploadStatusServiceRequestedSent) {
            httpFileUploadObject.status = XMPPHttpFileUploadStatusServiceRequested;
        }
        else if (httpFileUploadObject.status == XMPPHttpFileUploadStatusUploadServiceRequestedSent){
            httpFileUploadObject.status = XMPPHttpFileUploadStatusUploadServiceRequested;
        }
        else if (httpFileUploadObject.status == XMPPHttpFileUploadStatusUploadSlotRequestedSent){
            httpFileUploadObject.status = XMPPHttpFileUploadStatusUploadSlotRequested;
        }
    }
}

@end
