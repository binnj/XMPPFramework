//
//  XMPPMessageArchiveManagement.h
//  supDawg
//
//  Created by 8707839 CANADA INC. on 2015-11-11.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import "XMPP.h"
#import "XMPPIDTracker.h"

@protocol XMPPMessageArchivingManagementStorage;

/**
 * This class provides support for query and control an archive of messages stored on the server.
 * The functionality is formalized in XEP-0313.
 **/
@interface XMPPMessageArchiveManagement : XMPPModule
{
    @protected
        __strong id <XMPPMessageArchivingManagementStorage> xmppMessageArchivingManagementStorage;
    @private
        XMPPIDTracker *responseTracker;
        NSXMLElement *preferences;
}

- (id)initWithMessageArchivingManagementStorage:(id <XMPPMessageArchivingManagementStorage>)storage;
- (id)initWithMessageArchivingManagementStorage:(id <XMPPMessageArchivingManagementStorage>)storage dispatchQueue:(dispatch_queue_t)queue;

@property (readonly, strong) id <XMPPMessageArchivingManagementStorage> xmppMessageArchivingManagementStorage;
@property (readwrite, copy) NSXMLElement *preferences;

- (void) syncLocalMessageArchiveWithServerMessageArchive;
- (void) syncLocalMessageArchiveWithServerMessageArchiveWithBareJid: (NSString*)withBareJid startTime:(NSDate*)startTime endTime:(NSDate*)endTime maxResultNumber: (NSInteger*)maxResultNumber;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol XMPPMessageArchivingManagementStorage <NSObject>
@required

//
//
// -- PUBLIC METHODS --
//
// There are no public methods required by this protocol.
//
// Each individual roster storage class will provide a proper way to access/enumerate the
// users/resources according to the underlying storage mechanism.
//


//
//
// -- PRIVATE METHODS --
//
// These methods are designed to be used ONLY by the XMPPMessageArchiving class.
//
//

/**
 * Configures the storage class, passing its parent and parent's dispatch queue.
 *
 * This method is called by the init method of the XMPPMessageArchiveManagement class.
 * This method is designed to inform the storage class of its parent
 * and of the dispatch queue the parent will be operating on.
 *
 * The storage class may choose to operate on the same queue as its parent,
 * or it may operate on its own internal dispatch queue.
 *
 * This method should return YES if it was configured properly.
 * If a storage class is designed to be used with a single parent at a time, this method may return NO.
 * The XMPPMessageArchiving class is configured to ignore the passed
 * storage class in its init method if this method returns NO.
 **/
- (BOOL)configureWithParent:(XMPPMessageArchiveManagement *)aParent queue:(dispatch_queue_t)queue;

/**
 *
 **/
- (void)archiveMessage:(XMPPMessage *)message outgoing:(BOOL)isOutgoing xmppStream:(XMPPStream *)stream;


@optional

/**
 * The storage class may optionally persistently store the client preferences.
 **/
- (void)setPreferences:(NSXMLElement *)prefs forUser:(XMPPJID *)bareUserJid;

/**
 * The storage class may optionally persistently store the client preferences.
 * This method is then used to fetch previously known preferences when the client first connects to the xmpp server.
 **/
- (NSXMLElement *)preferencesForUser:(XMPPJID *)bareUserJid;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - supdawg2016+may26@gmail.com
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol XMPPMessageArchiveManagementDelegate <NSObject>
@optional

/**
 * Implement this method to receive notifications of sync start
 */
- (void)syncLocalMessageArchiveWithServerMessageArchiveDidStarted;

/**
 * Implement this method to receive notifications of end of sync
 */
- (void)syncLocalMessageArchiveWithServerMessageArchiveDidFinished;
@end
