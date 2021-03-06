//
//  PusherChatMonitor.m
//  PusherChat-iPhone
//
//  Created by Luke Redpath on 16/08/2011.
//  Copyright 2011 LJR Software Limited. All rights reserved.
//

#import "PusherChatMonitor.h"
#import "PTPusher.h"
#import "PTPusherChannel.h"
#import "PTPusherEvent.h"
#import "PusherChatService.h"
#import "PusherChatUser.h"
#import "PusherChatMessage.h"
#import "Macros.h"


// the URL used to authenticate users when connect to the presence channel
#define kPUSHER_CHAT_AUTH_URL    @"http://pusherchat.dev/api/authenticate?user_id=%d"

@interface PusherChatMonitor ()
@property (nonatomic, readonly) PTPusher *pusher;
@property (nonatomic, retain) PTPusherChannel *channel;
- (void)bindToChatEvents;
@end

@implementation PusherChatMonitor

@synthesize pusher = _pusher;
@synthesize channel;

- (id)initWithPusher:(PTPusher *)aPusher chat:(PusherChat *)aChat
{
  if ((self = [super init])) {
    _pusher = [aPusher retain];
    _pusher.delegate = self;
    chat = [aChat retain];
  }
  return self;
}

- (void)dealloc 
{
  [_pusher disconnect];
  [_pusher release];
  [chat release];
  [super dealloc];
}

- (void)startMonitoring
{
  if ([self.pusher.connection isConnected]) {
    self.channel = [self.pusher subscribeToPresenceChannelNamed:chat.channel delegate:self];
    [self bindToChatEvents];
  }
  else {
    [self.pusher connect];
  }
}

- (void)stopMonitoring
{
  [self.pusher unsubscribeFromChannel:self.channel];
}

- (void)setUser:(PusherChatUser *)user
{
  // once we have a user, we can configure the Pusher authorisation URL
  NSString *URLString = [NSString stringWithFormat:kPUSHER_CHAT_AUTH_URL, user.userID];
  self.pusher.authorizationURL = [NSURL URLWithString:URLString];
}

#pragma mark - Pusher delegate methods

- (void)pusher:(PTPusher *)pusher connectionDidConnect:(PTPusherConnection *)connection
{
  self.channel = [pusher subscribeToPresenceChannelNamed:chat.channel delegate:self];
  [self bindToChatEvents];
  
  NSLog(@"Chat monitor connected to channel %@.", self.channel.name);
}

- (void)pusher:(PTPusher *)pusher connection:(PTPusherConnection *)connection failedWithError:(NSError *)error
{
  NSLog(@"Failed to start chat monitor, error: %@", error);
}

- (void)pusher:(PTPusher *)pusher connectionDidDisconnect:(PTPusherConnection *)connection
{
  NSLog(@"Chat monitor disconnected.");
}

- (void)pusher:(PTPusher *)pusher didFailToSubscribeToChannel:(PTPusherChannel *)channel withError:(NSError *)error
{
  NSLog(@"Chat monitor could not subscribe to chat channel, error: %@", error);
}

#pragma mark - Event bindings

- (void)bindToChatEvents
{
  [self.channel bindToEventNamed:@"send_message" handleWithBlock:^(PTPusherEvent *event) {
    PusherChatMessage *message = [[PusherChatMessage alloc] initWithDictionaryFromService:event.data chat:chat];
    [chat receivedMessage:message];
    [message release];
  }];
}

#pragma mark - Presence events

- (void)presenceChannel:(PTPusherPresenceChannel *)channel didSubscribeWithMemberList:(NSArray *)members
{
  NSMutableArray *users = [NSMutableArray arrayWithCapacity:members.count];
  
  for (NSDictionary *userDictionary in members) {
    PusherChatUser *user = [[PusherChatUser alloc] initWithDictionaryFromService:[userDictionary objectForKey:@"chat_user"]];
    [users addObject:user];
    [user release];
  }
  [chat didConnect:users];
}

- (void)presenceChannel:(PTPusherPresenceChannel *)channel memberAdded:(NSDictionary *)memberData
{
  PusherChatUser *user = [[PusherChatUser alloc] initWithDictionaryFromService:[memberData objectForKey:@"chat_user"]];
  [chat userDidJoin:user];
  [user release];
}

- (void)presenceChannel:(PTPusherPresenceChannel *)channel memberRemoved:(NSDictionary *)memberData
{
  NSInteger userID = [[memberData objectForKey:@"user_id"] integerValue];
  PusherChatUser *user = [chat userWithID:userID];
  [chat userDidLeave:user];
}

@end

#pragma mark -

@implementation PusherChatMonitorFactory

@synthesize key;

+ (id)defaultFactory
{
  DEFINE_SHARED_INSTANCE_USING_BLOCK(^{
    return [[self alloc] init];
  });
}

- (PusherChatMonitor *)monitorForChat:(PusherChat *)chat
{
  PTPusher *pusher = [PTPusher pusherWithKey:self.key connectAutomatically:NO];
  return [[[PusherChatMonitor alloc] initWithPusher:pusher chat:chat] autorelease];
}

@end
