//
//  XMPPMUCSUB.h
//  Dollarama
//
//  Created by Besat Zardosht on 2019-05-15.
//  Copyright © 2019 binnj. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "XMPP.h"
#import "XMPPRoom.h"

#define _XMPP_MUCSUB_H

@class XMPPIDTracker;

typedef NSString* XMPPSubscribeEvent;
#define XMPPSubscribeEventPresence        @"urn:xmpp:mucsub:nodes:presence"
#define XMPPSubscribeEventMessages        @"urn:xmpp:mucsub:nodes:messages"
#define XMPPSubscribeEventAffiliations    @"urn:xmpp:mucsub:nodes:affiliations"
#define XMPPSubscribeEventSubscribers     @"urn:xmpp:mucsub:nodes:subscribers"
#define XMPPSubscribeEventConfig          @"urn:xmpp:mucsub:nodes:config"
#define XMPPSubscribeEventSubject         @"urn:xmpp:mucsub:nodes:subject"
#define XMPPSubscribeEventSystem          @"urn:xmpp:mucsub:nodes:system"

/**
 * The XMPPMUCSUB module, combined with XMPPRoom, PubSub and associated storage classes,
 * provides an implementation of muc-sub Chat.
 * https://docs.ejabberd.im/developer/xmpp-clients-bots/extensions/muc-sub/
 *
 * The bulk of the code resides in XMPPRoom, which handles the xmpp technical details
 * such as surrounding joining/leaving a room, sending/receiving messages, etc.
 *
 * The XMPPMUCSUB class provides general (but important) tasks relating to MUCSUB:
 *  - It integrates with XMPPCapabilities (if available) to properly advertise support for MUCSUB.
 *  - It monitors active XMPPRoom instances on the xmppStream,
 *    and provides an efficient query to see if a presence or message element is targeted at a room.
 *  - It listens for MUCSUB room invitations sent from other users.
 **/
@interface XMPPMUCSUB : XMPPModule
{
    /*    Inherited from XMPPModule:
     
     XMPPStream *xmppStream;
     
     dispatch_queue_t moduleQueue;
     */
    
    NSMutableSet *rooms;
    
    XMPPIDTracker *xmppIDTracker;
}

/* Inherited from XMPPModule:
 
 - (id)init;
 - (id)initWithDispatchQueue:(dispatch_queue_t)queue;
 
 - (BOOL)activate:(XMPPStream *)xmppStream;
 - (void)deactivate;
 
 @property (readonly) XMPPStream *xmppStream;
 
 - (NSString *)moduleName;
 
 */

- (BOOL)isMUCSUBRoomPresence:(XMPPPresence *)presence;
- (BOOL)isMUCSUBRoomMessage:(XMPPMessage *)message;

/**
 * Discovering support on MUC service
 * You can check if MUC/Sub feature is available on MUC service by sending Disco Info IQ
 * This method will attempt to discover existing services for the domain found in xmppStream.myJID.
 *
 * @see xmppMUCSUB:didDiscoverFeatures:
 * @see xmppMUCSUBFailedToDiscoverFeatures:withError:
 */
- (void)discoverFeatures;

/**
 * This method will attempt to discover support on a specific MUC
 *
 * @see xmppMUCSUB:didDiscoverFeaturesForRoom:
 * @see xmppMUCSUB:failedToDiscoverFeaturesForRoom:withError:
 *
 */
- (BOOL)discoverFeaturesForRoomJID:(XMPPJID *)roomJID;

/**
 * User can subscribe to  MUC Room events
 *
 * Subscription is associated with a nick.It will implicitly register the nick.
 * Server should otherwise make sure that subscription match the user registered nickname in that room.
 * In order to change the nick and/or subscription nodes, the same request MUST be sent with a different nick or nodes information.
 *
 * A room moderator can subscribe another user to MUC Room events by providing the user JID as an attribute in the <subscribe/> element.
 *
 * @see xmppMUCSUB:didSubscribeForRoomJID:
 * @see xmppMUCSUB:failedToSubscribeForRoomJID:withError:
 *
 * @param events the events that user wants to subscribe to.
 * @param roomJID the room that user wants to subscribe to.
 * @param nickName nickname of user in room.
 * @param password room password if there is any.
 */
- (void)subscibeToEvents:(NSArray<XMPPSubscribeEvent> *)events roomJID:(XMPPJID *)roomJID userJID:(XMPPJID *)userJID withNick:(NSString *)nickName passwordForRoom:(NSString *)password;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol XMPPMUCSUBDelegate
@optional

- (void)xmppMUCSUB:(XMPPMUCSUB *)sender roomJID:(XMPPJID *)roomJID didReceiveInvitation:(XMPPMessage *)message;
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender roomJID:(XMPPJID *)roomJID didReceiveInvitationDecline:(XMPPMessage *)message;
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender didReceiveMessage:(XMPPMessage *)message;
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender didReceivePresence:(XMPPPresence *)message;
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender didSubscribe:(NSXMLElement *)subscribe;
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender didUnsubscribe:(NSXMLElement *)unsubscribe;

/**
 * Implement this method when calling [mucsubInstanse discoverFeatures]. It will be invoked if the request
 * for discovering services is successfully executed and receives a successful response.
 *
 * @param sender XMPPMUCSUB object invoking this delegate method.
 * @param features An array of NSXMLElements in the form shown below. You will need to extract the data you
 *                 wish to use.
 *
 *                 <feature var="urn:xmpp:mucsub:0" />
 */
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender didDiscoverFeatures:(NSArray *)features;

/**
 * Implement this method when calling [mucsubInstanse discoverFeatures]. It will be invoked if the request
 * for discovering services is unsuccessfully executed or receives an unsuccessful response.
 *
 * @param sender XMPPMUCSUB object invoking this delegate method.
 * @param error NSError containing more details of the failure.
 */
- (void)xmppMUCSUBFailedToDiscoverFeatures:(XMPPMUCSUB *)sender withError:(NSError *)error;

/**
 * Implement this method when calling [mucsubInstanse discoverMUCSUBForRoomJID:]. It will be invoked if
 * the request for discovering mucsub service is successfully executed and receives a successful response.
 *
 * @param sender XMPPMUCSUB object invoking this delegate method.
 * @param features An array of NSXMLElements in the form shown below. You will need to extract the data you
 *              wish to use.
 *
 *              <feature var='urn:xmpp:mucsub:0' />
 *
 * @param roomJID room JID that user wants to discover mucsub service for.
 */
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender didDiscoverFeatures:(NSArray *)features ForRoomJID:(XMPPJID *)roomJID;

/**
 * Implement this method when calling [mucsubInstanse discoverMUCSUBForRoomJID:]. It will be invoked if
 * the request for discovering mucsub service is unsuccessfully executed or receives an unsuccessful response.
 *
 * @param sender XMPPMUCSUB object invoking this delegate method.
 * @param roomJID room JID that user wants to discover mucsub service for.
 * @param error NSError containing more details of the failure.
 */
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender failedToDiscoverFeaturesForRoomJID:(XMPPJID *)roomJID withError:(NSError *)error;

/**
 * Implement this method when calling [mucsubInstanse didSubscribeForRoomJID:]. It will be invoked if
 * the request for subscribing roomJID is successfully executed and receives a successful response.
 *
 * @param sender XMPPMUCSUB object invoking this delegate method.
 * @param roomJID room JID that user wants to subscribe to.
 */
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender didSubscribeToEvents:(NSArray<XMPPSubscribeEvent> *)events roomJID:(XMPPJID *)roomJID;

/**
 * Implement this method when calling [mucsubInstanse failedToSubscribeForRoomJID:withError:]. It will be invoked if
 * the request for subscribing roomJID is unsuccessfully executed or receives an unsuccessful response.
 *
 * @param sender XMPPMUCSUB object invoking this delegate method.
 * @param roomJID room JID that user wants to subscribe to.
 * @param error NSError containing more details of the failure.
 */
- (void)xmppMUCSUB:(XMPPMUCSUB *)sender failedToSubscribeToRoomJID:(XMPPJID *)roomJID withError:(NSError *)error;

@end
