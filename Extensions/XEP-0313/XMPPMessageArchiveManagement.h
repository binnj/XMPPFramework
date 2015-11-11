//
//  XMPPMessageArchiveManagement.h
//  supDawg
//
//  Created by Besat Zardosht on 2015-11-11.
//  Copyright © 2015 binnj inc. All rights reserved.
//

#import "XMPPModule.h"
#import "XMPPMessageArchivingManagementObject.h"
#import "XMPPIDTracker.h"

/**
 * This class provides support for query and control an archive of messages stored on the server.
 * The functionality is formalized in XEP-0313.
 **/
@interface XMPPMessageArchiveManagement : XMPPModule
{
    XMPPIDTracker *responseTracker;
}

@property (strong,nonatomic) NSArray* results;
@property (nonatomic) BOOL isResultCompleted;

- (void) fetchArchivedMessagesWithBareJid: (NSString*)withBareJid startTime:(NSDate*)startTime endTime:(NSDate*)endTime maxResultNumber: (NSInteger*)maxResultNumber;
//- (void) fetchNextResultPage;

@end
