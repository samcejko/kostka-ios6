#import <Foundation/Foundation.h>

// What is new in a version. Mojang's own notes where it wrote any that can be read: the launcher's news of 2011 to
// 2016 (Minecraft Update News, mcupdate.tumblr.com: the releases from Beta 1.3 to 1.11.2) and the launcher's patch
// notes from 1.13 on (launchercontent.mojang.com). Then the Minecraft Wiki's page about the version (minecraft.wiki,
// its text under CC BY-NC-SA 3.0): for the versions Mojang's notes miss (1.12, the snapshots of the LWJGL 2 era,
// Alpha, Classic) and for more than the news's few lines. Fetched when looked at, as plain text (the markup, templates,
// pictures and references taken out), kept in Library/Kostka/changelogs for the times without network.
@interface KOChangelog : NSObject

// Mojang's list (KOVersions): the names the news's titles are matched with ("Minecraft Beta 1.3" is b1.3b there)
+ (void)setVersions:(NSArray *)versions;

// The wiki's page for one of Mojang's version names: "a1.2.6" is "Java Edition Alpha v1.2.6", "b1.7.3" "Java Edition
// Beta 1.7.3", "c0.30_01c" "Java Edition Classic 0.30_01c", "inf-20100618" "Java Edition Infdev 20100618"
+ (NSString *)wikiTitleFor:(NSString *)identifier;

// The texts, on the main thread. `mojang`: Mojang's notes, nil when it wrote none - { text, title ("Minecraft 1.11 -
// The Exploration Update"), date ("2016-11-17"), from ("news" or "patch") }. `wiki`: the wiki's text - not fetched for
// the versions of the launcher's patch notes, which say it all. An error when there is neither. Headings are lines in
// capitals, list items start with "• " (Mojang's news keeps its own marks: + added, * changed, - removed or fixed).
+ (void)load:(NSString *)identifier done:(void (^)(NSDictionary *mojang, NSString *wiki, NSError *error))done;

// A line of what is new in the version, for the list: its first items ("New mobs and new places to put your precious
// items! · Added cursed enchantments · Added the Observer block · ..."), Mojang's when there are, else the wiki's.
// What is known already, or nil - and then `want:` brings it.
+ (NSString *)summaryFor:(NSString *)identifier;
// Mojang's notes fetched (when they are older than a week) and their summaries known: `done` on the main thread
+ (void)prepare:(void (^)(void))done;
// The summary fetched in the background, a few at a time, the last asked for first (the rows on the screen); `done` on
// the main thread, with nil when there is none (no network: asked again a minute later)
+ (void)want:(NSString *)identifier done:(void (^)(NSString *summary))done;

// (tests) the wiki's markup as plain text; a text's summary
+ (NSString *)plainText:(NSString *)wikitext;
+ (NSString *)summaryOf:(NSString *)text mojang:(BOOL)mojang;

@end
