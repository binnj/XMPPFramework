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

// XMPP Incoming File Upload State
typedef NS_ENUM(int, XMPPMessageUploadFileState) {
    XMPPMessageUploadFileStateDiscoDiscoveryRequest,
    XMPPMessageUploadFileStateFoundUploadService,
    XMPPMessageUploadFileStateNotFoundUploadService,
    XMPPMessageUploadFileStateUploadServiceDiscoDiscoveryService,
    XMPPMessageUploadFileStateUploadServiceXMLNS
};

@interface XMPPHttpFileUpload()
{
    BOOL hasRequestedServices;
    BOOL hasRequestedUploadServices;
    BOOL hasRequestedSlot;
    BOOL hasUploadService;
    NSString* uploadServiceJid;
    NSString* uploadFileName;
    long uploadFileSize;
    NSString* uploadContentType;
}
@end

@implementation XMPPHttpFileUpload
@synthesize getURL;
@synthesize putURL;

- (id)initWithDispatchQueue:(dispatch_queue_t)queue
{
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
        [xmppIDTracker removeAllIDs];
        xmppIDTracker = nil;
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
#pragma mark request for file upload permission
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)requestFileUpload:(NSString*)fileName fileSize:(long)fileSize contentType:(NSString*)contentType
{
    uploadFileName = fileName;
    uploadFileSize = fileSize;
    uploadContentType = contentType;
    
    
    dispatch_block_t block = ^{ @autoreleasepool {
        if (!hasRequestedServices) [self discoverServices];
        else if (!hasRequestedUploadServices) [self discoverUploadService];
        else [self requestSlotForFile:uploadFileName fileSize:uploadFileSize contentType:uploadContentType];
        
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
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
    // This is a public method, so it may be invoked on any thread/queue.
    
    dispatch_block_t block = ^{ @autoreleasepool {
        if (hasRequestedServices) return; // We've already requested services
        
        NSString *toStr = xmppStream.myJID.domain;
        NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                      xmlns:XMPPDiscoItemsNamespace];
        XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                     to:[XMPPJID jidWithString:toStr]
                              elementID:[xmppStream generateUUID]
                                  child:query];
        
        [xmppIDTracker addElement:iq
                           target:self
                         selector:@selector(handleDiscoverServicesQueryIQ:withInfo:)
                          timeout:60];
        
        [xmppStream sendElement:iq];
        hasRequestedServices = YES;
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Server replies to service discovery request
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method handles the response received (or not received) after calling discoverServices.
 */

//<iq from='montague.tld'
//    id='step_01'
//    to='romeo@montague.tld/garden'
//  <query xmlns='http://jabber.org/protocol/disco#items'>
//    <item jid='upload.montague.tld' name='HTTP File Upload' />
//    <item jid='conference.montague.tld' name='Chatroom Service' />
//  </query>
//</iq>
- (void)handleDiscoverServicesQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t block = ^{ @autoreleasepool {
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
        
        NSXMLElement *query = [iq elementForName:@"query"
                                           xmlns:XMPPDiscoItemsNamespace];
        
        NSArray *items = [query elementsForName:@"item"];
        for (NSXMLElement* item in items){
            if ([[item name] isEqualToString:@"HTTP File Upload"]) {
                uploadServiceJid = [[item attributeForName:@"jid"] stringValue];
                [self discoverUploadService];
                break;
            }
        }
        hasRequestedServices = NO; // Set this back to NO to allow for future requests
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
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
    // This is a public method, so it may be invoked on any thread/queue.
    
    dispatch_block_t block = ^{ @autoreleasepool {
        if (hasRequestedUploadServices) return; // We've already requested services
        
        NSString *toStr = uploadServiceJid;
        NSXMLElement *query = [NSXMLElement elementWithName:@"query"
                                                      xmlns:XMPPDiscoItemsNamespace];
        XMPPIQ *iq = [XMPPIQ iqWithType:@"get"
                                     to:[XMPPJID jidWithString:toStr]
                              elementID:[xmppStream generateUUID]
                                  child:query];
        
        [xmppIDTracker addElement:iq
                           target:self
                         selector:@selector(handleDiscoverUploadServicesQueryIQ:withInfo:)
                          timeout:60];
        
        [xmppStream sendElement:iq];
        hasRequestedUploadServices = YES;
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Upload service replies to service discovery request
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method handles the response received (or not received) after calling discoverServices.
 */

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
- (void)handleDiscoverUploadServicesQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t block = ^{ @autoreleasepool {
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
        
        NSXMLElement *query = [iq elementForName:@"query"
                                           xmlns:XMPPDiscoItemsNamespace];
        
        NSArray *features = [query elementsForName:@"feature"];
        for (NSXMLElement* feature in features){
            if ([XMLNS_XMPP_HTTP_FILE_UPLOAD isEqualToString:[[feature attributeForName:@"var"] stringValue]]) {
                [self requestSlotForFile:uploadFileName fileSize:uploadFileSize contentType:uploadContentType];
            }
        }
        hasRequestedUploadServices = NO; // Set this back to NO to allow for future requests
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
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
    
    dispatch_block_t block = ^{ @autoreleasepool {
        
        NSString *toStr = uploadServiceJid;
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
        
        [xmppIDTracker addElement:iq
                           target:self
                         selector:@selector(handleSlotRequestQueryIQ:withInfo:)
                          timeout:60];
        
        [xmppStream sendElement:iq];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark The upload service responsd with a slot
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method handles the response received (or not received) after calling discoverServices.
 */

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
- (void)handleSlotRequestQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)info
{
    dispatch_block_t block = ^{ @autoreleasepool {
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
        if (putURLStr) putURL = [NSURL URLWithString:putURLStr];
        if (getURLStr) getURL = [NSURL URLWithString:getURLStr];
    }};
    
    if (dispatch_get_specific(moduleQueueTag))
        block();
    else
        dispatch_async(moduleQueue, block);
}

@end
