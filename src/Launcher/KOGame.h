#import <Foundation/Foundation.h>
#import "KOVersions.h"

// Starting a version: what it needs comes from Mojang (its JSON, the game's jar, its libraries, all checked
// against their SHA-1) into Library/Kostka, then the Java VM runs it in its own folder (Library/Kostka/games/<id>).
// The game takes the screen; when it ends, Kostka closes (one Java VM per process: the next game needs a new
// start of the app).
@interface KOGame : NSObject

+ (BOOL)isRunning;
// (tests: LWJGL with a check after every OpenGL call, lwjgl-debug.jar - the game stops at the first call that fails)
+ (void)setDebugGL:(BOOL)on;
+ (NSString *)playerName;
+ (void)setPlayerName:(NSString *)name;

// `status`: what is happening ("Downloading the game", 0..1, -1 when unknown); `failed`: it could not start
+ (void)play:(KOVersion *)version
      status:(void (^)(NSString *text, float progress))status
      failed:(void (^)(NSError *error))failed;

@end
