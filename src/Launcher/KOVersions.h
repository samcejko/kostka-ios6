#import <Foundation/Foundation.h>

// The versions of Minecraft: Java Edition, from Mojang's list (piston-meta.mojang.com), kept in
// Library/Kostka/versions for when the network is away. And what Kostka can do with each.
typedef NS_ENUM(NSInteger, KOSupport) {
    KOSupportPlays,   // tried on an iPad 2: it starts, makes a new world and plays in it (Resources/Tested.json)
    KOSupportTry,     // of the LWJGL 2 era, not tried yet (snapshots)
    KOSupportSoon,    // of the LWJGL 2 era, but it did not play in the tries (Tested.json says why)
    KOSupportNever    // LWJGL 3, newer OpenGL and Java: more than iOS 6 gives
};

@interface KOVersion : NSObject
@property (nonatomic, copy) NSString *identifier;   // "rd-132211", "1.7.10"
@property (nonatomic, copy) NSString *type;         // release, snapshot, old_beta, old_alpha
@property (nonatomic, copy) NSString *url;          // its JSON
@property (nonatomic, copy) NSString *sha1;         // of its JSON
@property (nonatomic, copy) NSString *released;     // "2009-05-13"
@property (nonatomic, readonly) KOSupport support;
@property (nonatomic, readonly) NSString *localizedSupport;   // "Plays", "Not yet", ...
@property (nonatomic, readonly) NSString *problem;            // KOSupportSoon: what went wrong in the tries
@property (nonatomic, readonly) NSString *localizedReleased;  // the date, as this device writes dates
@end

@interface KOVersions : NSObject
+ (NSString *)versionsPath;
// The list, newest first: from Mojang, or (offline) the copy from the last time. Called on the main thread.
+ (void)load:(void (^)(NSArray *versions, NSError *error))done;
@end
