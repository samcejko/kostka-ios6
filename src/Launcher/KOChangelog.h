#import <Foundation/Foundation.h>

// What is new in a version: the Minecraft Wiki's page about it (minecraft.wiki, its text under CC BY-NC-SA 3.0),
// fetched when the version is looked at - its first lines and its sections Additions, Changes and Fixes, as plain
// text (the wiki's markup, templates, pictures and references taken out). Kept in Library/Kostka/changelogs for the
// times without network.
@interface KOChangelog : NSObject

// The wiki's page for one of Mojang's version names: "a1.2.6" is "Java Edition Alpha v1.2.6", "b1.7.3" "Java Edition
// Beta 1.7.3", "c0.30_01c" "Java Edition Classic 0.30_01c", "inf-20100618" "Java Edition Infdev 20100618"
+ (NSString *)wikiTitleFor:(NSString *)identifier;

// The text, or an error (main thread). Headings are lines in capitals, list items start with "•".
+ (void)load:(NSString *)identifier done:(void (^)(NSString *text, NSError *error))done;

// The wiki's markup as plain text (for tests)
+ (NSString *)plainText:(NSString *)wikitext;

@end
