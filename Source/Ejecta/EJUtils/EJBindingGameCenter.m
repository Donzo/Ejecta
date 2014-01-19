#import "EJBindingGameCenter.h"
#import "EJJavaScriptView.h"

@implementation EJBindingGameCenter

- (id)initWithContext:(JSContextRef)ctx argc:(size_t)argc argv:(const JSValueRef [])argv {
	if( self = [super initWithContext:ctx argc:argc argv:argv] ) {
		achievements = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc {
	[achievements release];
	[super dealloc];
}

- (void)loadAchievements {
	[GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *loadedAchievements, NSError *error) {
		if( !error ) {
			for (GKAchievement* achievement in loadedAchievements) {
				achievements[achievement.identifier] = achievement;
			}
		}
	}];
}

- (void)leaderboardViewControllerDidFinish:(GKLeaderboardViewController *)viewController {
	[viewController.presentingViewController dismissModalViewControllerAnimated:YES];
	viewIsActive = false;
}

- (void)achievementViewControllerDidFinish:(GKAchievementViewController *)viewController {
	[viewController.presentingViewController dismissModalViewControllerAnimated:YES];
	viewIsActive = false;
}


EJ_BIND_FUNCTION( authenticate, ctx, argc, argv ) {
	__block JSObjectRef callback = NULL;
	if( argc > 0 && JSValueIsObject(ctx, argv[0]) ) {
		callback = JSValueToObject(ctx, argv[0], NULL);
		JSValueProtect(ctx, callback);
	}
	
	[[GKLocalPlayer localPlayer] authenticateWithCompletionHandler:^(NSError *error) {
		authed = !error;

		if( authed ) {
			NSLog(@"GameKit: Authed.");
			[self loadAchievements];
		}
		else {
			NSLog(@"GameKit: Auth failed: %@", error );
		}
		
		int autoAuth = authed
			? kEJGameCenterAutoAuthSucceeded
			: kEJGameCenterAutoAuthFailed;
		[[NSUserDefaults standardUserDefaults] setObject:@(autoAuth) forKey:kEJGameCenterAutoAuth];
		[[NSUserDefaults standardUserDefaults] synchronize];
		
		if( callback ) {
			JSContextRef gctx = scriptView.jsGlobalContext;
			JSValueRef params[] = { JSValueMakeBoolean(gctx, error) };
			[scriptView invokeCallback:callback thisObject:NULL argc:1 argv:params];
			JSValueUnprotectSafe(gctx, callback);
			
			// Make sure this callback is only called once
			callback = NULL;
		}
	}];
	return NULL;
}

EJ_BIND_FUNCTION( softAuthenticate, ctx, argc, argv ) {
	// Check if the last auth was successful or never tried and if so, auto auth this time
	int autoAuth = [[[NSUserDefaults standardUserDefaults] objectForKey:kEJGameCenterAutoAuth] intValue];
	if(
		autoAuth == kEJGameCenterAutoAuthNeverTried ||
		autoAuth == kEJGameCenterAutoAuthSucceeded
	) {
		[self _func_authenticate:ctx argc:argc argv:argv];
	}
	else if( argc > 0 && JSValueIsObject(ctx, argv[0]) ) {
		NSLog(@"GameKit: Skipping soft auth.");
		
		JSObjectRef callback = JSValueToObject(ctx, argv[0], NULL);
		JSValueRef params[] = { JSValueMakeBoolean(ctx, true) };
		[scriptView invokeCallback:callback thisObject:NULL argc:1 argv:params];
	}
	return NULL;
}

EJ_BIND_FUNCTION( reportScore, ctx, argc, argv ) {
	if( argc < 2 ) { return NULL; }
	if( !authed ) { NSLog(@"GameKit Error: Not authed. Can't report score."); return NULL; }
	
	NSString *category = JSValueToNSString(ctx, argv[0]);
	int64_t score = JSValueToNumberFast(ctx, argv[1]);
	
	JSObjectRef callback = NULL;
	if( argc > 2 && JSValueIsObject(ctx, argv[2]) ) {
		callback = JSValueToObject(ctx, argv[2], NULL);
		JSValueProtect(ctx, callback);
	}
	
	GKScore *scoreReporter = [[[GKScore alloc] initWithCategory:category] autorelease];
	if( scoreReporter ) {
		scoreReporter.value = score;

		[scoreReporter reportScoreWithCompletionHandler:^(NSError *error) {
			if( callback ) {
				JSContextRef gctx = scriptView.jsGlobalContext;
				JSValueRef params[] = { JSValueMakeBoolean(gctx, error) };
				[scriptView invokeCallback:callback thisObject:NULL argc:1 argv:params];
				JSValueUnprotectSafe(gctx, callback);
			}
		}];
	}
	
	return NULL;
}


// get friends base info
EJ_BIND_FUNCTION( retrieveFriends, ctx, argc, argv ) {

    JSObjectRef callback = JSValueToObject(ctx, argv[0], NULL);
    if( callback ) {
        JSValueProtect(ctx, callback);
    }

    if (authed){
        GKLocalPlayer *player = [GKLocalPlayer localPlayer];
        [player loadFriendsWithCompletionHandler:^(NSArray *friends, NSError *error) {
            [self loadPlayers:friends callback:callback];
        }];
    }else{
        JSValueRef params[] = { NULL,NULL };
        [scriptView invokeCallback:callback thisObject:NULL argc:2 argv:params];
        JSValueUnprotectSafe(ctx, callback);
    }
    return NULL;
}

// get players base info
//      args: playerIdentifiers (array)
EJ_BIND_FUNCTION( retrievePlayers, ctx, argc, argv ) {
    
    JSObjectRef jsIdentifiers = JSValueToObject(ctx, argv[0], NULL);
    int length= JSValueToNumber(ctx, JSObjectGetProperty(ctx, jsIdentifiers, JSStringCreateWithUTF8CString("length"), NULL),NULL);
    NSMutableArray *identifiers = [[NSMutableArray alloc] init];
    for (int i = 0; i < length; i++) {
        [identifiers addObject: JSValueToNSString(ctx, JSObjectGetPropertyAtIndex(ctx, jsIdentifiers, i, NULL))];
    }
    
    JSObjectRef callback = JSValueToObject(ctx, argv[1], NULL);
    if( callback ) {
        JSValueProtect(ctx, callback);
    }

    [self loadPlayers:identifiers callback:callback];
    
    return NULL;
}

// get scores in range
//      args: category, options(timeScope,friendsOnly,start,end), callback
// playerScope
EJ_BIND_FUNCTION( retrieveScores, ctx, argc, argv ) {

    GKLeaderboard *leaderboardRequest = [[GKLeaderboard alloc] init];
    if (leaderboardRequest != nil) {
        NSString *category = JSValueToNSString(ctx, argv[0]);
        
        JSObjectRef jsOptions=JSValueToObject(ctx,argv[1], NULL);
        JSObjectRef callback = JSValueToObject(ctx,argv[2], NULL );
       	if( callback ) {
            JSValueProtect(ctx, callback);
        }
        
//      NSObject *options = JSValueToNSObject(ctx, jsOptions);
        
        int start=JSValueToNumberFast(ctx, JSObjectGetProperty(ctx, jsOptions, JSStringCreateWithUTF8CString("start"), NULL));
        int end=JSValueToNumberFast(ctx, JSObjectGetProperty(ctx, jsOptions, JSStringCreateWithUTF8CString("end"), NULL));
        if (!start){
            start=1;
        }
        if (!end){
            end=start+100-1;
        }

        //  0: GKLeaderboardTimeScopeToday  , 1: GKLeaderboardTimeScopeWeek , 2: GKLeaderboardTimeScopeAllTime
        int timeScope=JSValueToBoolean(ctx, JSObjectGetProperty(ctx, jsOptions, JSStringCreateWithUTF8CString("timeScope"), NULL));
        
        bool friendsOnly=JSValueToBoolean(ctx, JSObjectGetProperty(ctx, jsOptions, JSStringCreateWithUTF8CString("friendsOnly"), NULL));
        
        switch(timeScope) {
            case 0:
                leaderboardRequest.timeScope = GKLeaderboardTimeScopeToday;
                break;
            case 1:
                leaderboardRequest.timeScope = GKLeaderboardTimeScopeWeek;
                break;
            case 2:
                leaderboardRequest.timeScope = GKLeaderboardTimeScopeAllTime;
                break;
        }
        leaderboardRequest.playerScope = friendsOnly?GKLeaderboardPlayerScopeFriendsOnly: GKLeaderboardPlayerScopeGlobal;
        
        leaderboardRequest.category = category;
        leaderboardRequest.range = NSMakeRange(start,end);
        
        [leaderboardRequest loadScoresWithCompletionHandler: ^(NSArray *scores, NSError *error) {
    
            NSMutableArray *identifiers = [[NSMutableArray alloc] init];
            NSMutableArray *scoreList = [[NSMutableArray alloc] init];
            if (scores!=NULL){
                for (GKScore *obj in leaderboardRequest.scores) {
                    [identifiers addObject:obj.playerID];
                    [scoreList addObject:obj];
                }
            }
            
            [self loadPlayersAndScores:identifiers scores:scoreList callback:callback];
            
        }];
    }
    return NULL;
}


// get local player base info
EJ_BIND_FUNCTION( getLocalPlayerInfo, ctx, argc, argv ) {
    if (!authed){
        return NULL;
    }
    GKLocalPlayer * player=[GKLocalPlayer localPlayer];
    JSValueRef jsPlayer = NSObjectToJSValue(ctx,
                                            @{
                                              @"playerID": player.playerID,
                                              @"displayName": player.displayName,
                                              @"alias": player.alias,
                                              @"isFriend": @(player.isFriend)
                                              });
    return jsPlayer;
}


-(void)loadPlayers:(NSArray *)identifiers callback:(JSObjectRef)callback {
  
    [GKPlayer loadPlayersForIdentifiers:identifiers withCompletionHandler:^(NSArray *players, NSError *error)
     {
         JSObjectRef jsPlayers = NULL;
         JSContextRef gctx = scriptView.jsGlobalContext;
         if (players != nil) {
             NSUInteger size=players.count;
             JSValueRef *jsArrayItems = malloc( sizeof(JSValueRef) * size);
             int count=0;
             for (GKPlayer *player in players){
                 jsArrayItems[count++] = NSObjectToJSValue(gctx,
                                               @{
                                                 @"alias": player.alias,
                                                 @"displayName": player.displayName,
                                                 @"playerID": player.playerID,
                                                 @"isFriend": @(player.isFriend)
                                                 });
             }
             jsPlayers = JSObjectMakeArray(gctx, count, jsArrayItems, NULL);
         }
         JSValueRef params[] = { jsPlayers, JSValueMakeBoolean(gctx, error) };
         [scriptView invokeCallback:callback thisObject:NULL argc:2 argv:params];
         JSValueUnprotectSafe(gctx, callback);
     }];

}




-(void)loadPlayersAndScores:(NSArray *)identifiers scores:(NSArray *)scores callback:(JSObjectRef)callback {
    
    [GKPlayer loadPlayersForIdentifiers:identifiers withCompletionHandler:^(NSArray *players, NSError *error)
     {
         JSObjectRef jsScores = NULL;
         JSContextRef gctx = scriptView.jsGlobalContext;
         if (players != nil) {
             NSUInteger size=players.count;
             JSValueRef *jsArrayItems = malloc( sizeof(JSValueRef) * size);
             int count=0;
             for (GKPlayer *player in players){
                 GKScore *score = [scores objectAtIndex:count];
                 jsArrayItems[count++] = NSObjectToJSValue(gctx,
                                               @{
                                                 @"alias": player.alias,
                                                 @"displayName": player.displayName,
                                                 @"playerID": player.playerID,
                                                 @"category": score.category,
                                                 @"date": score.date,
                                                 @"formattedValue": score.formattedValue,
                                                 @"value": @(score.value),
                                                 @"rank": @(score.rank)
                                                 });
             }
             jsScores = JSObjectMakeArray(gctx, count, jsArrayItems, NULL);
         }
         JSValueRef params[] = { jsScores, JSValueMakeBoolean(gctx, error) };
         [scriptView invokeCallback:callback thisObject:NULL argc:2 argv:params];
         JSValueUnprotectSafe(gctx, callback);
     }];
}



EJ_BIND_FUNCTION( showLeaderboard, ctx, argc, argv ) {
	if( argc < 1 || viewIsActive ) { return NULL; }
	if( !authed ) { NSLog(@"GameKit Error: Not authed. Can't show leaderboard."); return NULL; }
	
	GKLeaderboardViewController *leaderboard = [[[GKLeaderboardViewController alloc] init] autorelease];
	if( leaderboard ) {
		viewIsActive = true;
		leaderboard.leaderboardDelegate = self;
		leaderboard.category = JSValueToNSString(ctx, argv[0]);
        leaderboard.timeScope=GKLeaderboardTimeScopeAllTime;
		[scriptView.window.rootViewController presentModalViewController:leaderboard animated:YES];
	}
	
	return NULL;
}


- (void)reportAchievementWithIdentifier:(NSString *)identifier
	percentage:(float)percentage isIncrement:(BOOL)isIncrement
	ctx:(JSContextRef)ctx callback:(JSObjectRef)callback
{
	if( !authed ) { NSLog(@"GameKit Error: Not authed. Can't report achievment."); return; }
	
	GKAchievement *achievement = achievements[identifier];
	if( achievement ) {		
		// Already reported with same or higher percentage or already at 100%?
		if(
			achievement.percentComplete == 100.0f ||
			(!isIncrement && achievement.percentComplete >= percentage)
		) {
			return;
		}
		
		if( isIncrement ) {
			percentage = MIN( achievement.percentComplete + percentage, 100.0f );
		}
	}
	else {
		achievement = [[[GKAchievement alloc] initWithIdentifier:identifier] autorelease];
	}
	
	achievement.showsCompletionBanner = YES;
	achievement.percentComplete = percentage;
	
	if( callback ) {
		JSValueProtect(ctx, callback);
	}
	
	[achievement reportAchievementWithCompletionHandler:^(NSError *error) {
		achievements[identifier] = achievement;
		
		if( callback ) {
			JSContextRef gctx = scriptView.jsGlobalContext;
			JSValueRef params[] = { JSValueMakeBoolean(gctx, error) };
			[scriptView invokeCallback:callback thisObject:NULL argc:1 argv:params];
			JSValueUnprotectSafe(gctx, callback);
		}
	}];
}

EJ_BIND_FUNCTION( reportAchievement, ctx, argc, argv ) {
	if( argc < 2 ) { return NULL; }
	
	NSString *identifier = JSValueToNSString(ctx, argv[0]);
	float percent = JSValueToNumberFast(ctx, argv[1]);
	
	JSObjectRef callback = NULL;
	if( argc > 2 && JSValueIsObject(ctx, argv[2]) ) {
		callback = JSValueToObject(ctx, argv[2], NULL);
	}
	
	[self reportAchievementWithIdentifier:identifier percentage:percent isIncrement:NO ctx:ctx callback:callback];
	return NULL;
}

EJ_BIND_FUNCTION( reportAchievementAdd, ctx, argc, argv ) {
	if( argc < 2 ) { return NULL; }
	
	NSString *identifier = JSValueToNSString(ctx, argv[0]);
	float percent = JSValueToNumberFast(ctx, argv[1]);
	
	JSObjectRef callback = NULL;
	if( argc > 2 && JSValueIsObject(ctx, argv[2]) ) {
		callback = JSValueToObject(ctx, argv[2], NULL);
	}
	
	[self reportAchievementWithIdentifier:identifier percentage:percent isIncrement:YES ctx:ctx callback:callback];
	return NULL;
}

EJ_BIND_FUNCTION( showAchievements, ctx, argc, argv ) {
	if( viewIsActive ) { return NULL; }
	if( !authed ) { NSLog(@"GameKit Error: Not authed. Can't show achievements."); return NULL; }
	
	GKAchievementViewController *achievementView = [[[GKAchievementViewController alloc] init] autorelease];
	if( achievementView ) {
		viewIsActive = true;
		achievementView.achievementDelegate = self;
		[scriptView.window.rootViewController presentModalViewController:achievementView animated:YES];
	}
	return NULL;
}

EJ_BIND_GET(authed, ctx) {
	return JSValueMakeBoolean(ctx, authed);
}

@end
