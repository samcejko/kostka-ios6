#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#import "KOChangelog.h"
#import "KOVersions.h"
#import "KONet.h"
#import "KOJava.h"
#import "KOCommon.h"

// Mojang's notes: the launcher's news of 2011 to 2016 (its API gives 50 posts at a time) and its patch notes from 1.13
static NSString *const KONewsPage = @"https://mcupdate.tumblr.com/api/read/json?num=50&start=%lu";
static NSString *const KOPatchNotes = @"https://launchercontent.mojang.com/v2/javaPatchNotes.json";
static NSString *const KOPatchNotesBase = @"https://launchercontent.mojang.com/v2/";

static NSString *KOTemplatesOut(NSString *s);
static NSString *KOLinksOut(NSString *s);

// A template's or a link's parts, split at its own "|" (not at the ones of templates and links inside it)
static NSArray *KOParts(NSString *inner)
{
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger n = inner.length, from = 0;
    int braces = 0, brackets = 0;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [inner characterAtIndex:i], d = i + 1 < n ? [inner characterAtIndex:i + 1] : 0;
        if (c == '{' && d == '{') { braces++; i++; }
        else if (c == '}' && d == '}') { braces--; i++; }
        else if (c == '[' && d == '[') { brackets++; i++; }
        else if (c == ']' && d == ']') { brackets--; i++; }
        else if (c == '|' && braces <= 0 && brackets <= 0) {
            [parts addObject:[inner substringWithRange:NSMakeRange(from, i - from)]];
            from = i + 1;
        }
    }
    [parts addObject:[inner substringFromIndex:from]];
    return parts;
}

// What a template stands for in the text: a few give their first value ({{key|F3}}, {{cmd|locate}}: "/locate"),
// the rest (infoboxes, pictures, references, the tables of fixes) nothing
static NSString *KOTemplateText(NSString *inner)
{
    NSArray *parts = KOParts(inner);
    NSString *name = [[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSString *first = parts.count > 1 ? KOTemplatesOut(parts[1]) : @"";
    // ("a minor update for {{JE}} that was released ...")
    NSDictionary *words = @{ @"je": @"Java Edition", @"be": @"Bedrock Edition", @"mc": @"Minecraft" };
    if (words[name]) return words[name];
    if ([name isEqualToString:@"cmd"]) return [@"/" stringByAppendingString:first];
    if ([@[ @"key", @"keys", @"code", @"tc", @"mono", @"nowrap", @"w", @"tooltip", @"lang" ] containsObject:name]) return first;
    return @"";
}

// The text without its templates ({{...}}) and tables ({| ... |} from a line's start)
static NSString *KOTemplatesOut(NSString *s)
{
    NSUInteger n = s.length;
    if (!n) return s;
    unichar *c = malloc(n * sizeof(unichar));
    [s getCharacters:c range:NSMakeRange(0, n)];
    NSMutableString *out = [NSMutableString stringWithCapacity:n];
    NSUInteger i = 0, from = 0;
    while (i < n) {
        if (i + 1 < n && c[i] == '{' && c[i + 1] == '{') {
            NSUInteger j = i + 2;
            int depth = 1;
            while (j < n && depth > 0) {
                if (j + 1 < n && c[j] == '{' && c[j + 1] == '{') { depth++; j += 2; }
                else if (j + 1 < n && c[j] == '}' && c[j + 1] == '}') { depth--; j += 2; }
                else j++;
            }
            [out appendString:[s substringWithRange:NSMakeRange(from, i - from)]];
            if (depth == 0) [out appendString:KOTemplateText([s substringWithRange:NSMakeRange(i + 2, j - 2 - (i + 2))])];
            i = from = j;
            continue;
        }
        if ((i == 0 || c[i - 1] == '\n') && i + 1 < n && c[i] == '{' && c[i + 1] == '|') {
            NSUInteger j = i + 2;
            int depth = 1;
            while (j < n && depth > 0) {
                BOOL lineStart = c[j - 1] == '\n';
                if (lineStart && j + 1 < n && c[j] == '{' && c[j + 1] == '|') { depth++; j += 2; }
                else if (lineStart && j + 1 < n && c[j] == '|' && c[j + 1] == '}') { depth--; j += 2; }
                else j++;
            }
            [out appendString:[s substringWithRange:NSMakeRange(from, i - from)]];
            i = from = j;
            continue;
        }
        i++;
    }
    if (from < n) [out appendString:[s substringFromIndex:from]];
    free(c);
    return out;
}

// The text with its wiki links as their words ("[[Concrete powder]]", "[[Sand|sand]]": "sand"); pictures and
// categories out
static NSString *KOLinksOut(NSString *s)
{
    NSUInteger n = s.length;
    NSMutableString *out = [NSMutableString stringWithCapacity:n];
    NSUInteger i = 0, from = 0;
    while (i + 1 < n) {
        if ([s characterAtIndex:i] == '[' && [s characterAtIndex:i + 1] == '[') {
            NSUInteger j = i + 2;
            int depth = 1;
            while (j < n && depth > 0) {
                unichar c = [s characterAtIndex:j], d = j + 1 < n ? [s characterAtIndex:j + 1] : 0;
                if (c == '[' && d == '[') { depth++; j += 2; }
                else if (c == ']' && d == ']') { depth--; j += 2; }
                else j++;
            }
            [out appendString:[s substringWithRange:NSMakeRange(from, i - from)]];
            if (depth == 0) {
                NSString *inner = [s substringWithRange:NSMakeRange(i + 2, j - 2 - (i + 2))];
                NSString *lower = [inner lowercaseString];
                if (!([lower hasPrefix:@"file:"] || [lower hasPrefix:@"image:"] || [lower hasPrefix:@"category:"] ||
                      [lower hasPrefix:@"media:"])) {
                    NSArray *parts = KOParts(inner);
                    NSString *words = parts.count > 1 ? [parts lastObject] : parts[0];
                    if (parts.count == 1) {
                        if ([words hasPrefix:@":"]) words = [words substringFromIndex:1];
                        NSRange hash = [words rangeOfString:@"#"];
                        if (hash.location != NSNotFound && hash.location > 0) words = [words substringToIndex:hash.location];
                    }
                    [out appendString:KOLinksOut(words)];
                }
            }
            i = from = j;
            continue;
        }
        i++;
    }
    if (from < n) [out appendString:[s substringFromIndex:from]];
    return out;
}

static NSString *KOReplace(NSString *s, NSString *pattern, NSString *with)
{
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
        options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:NULL];
    return re ? [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:with] : s;
}

#pragma mark - Mojang's notes

// The character references and entities of Mojang's notes ("&rsquo;", "&#x26;", "&#8217;")
static NSString *KOEntities(NSString *s)
{
    if (![s isKindOfClass:[NSString class]]) return @"";
    if ([s rangeOfString:@"&"].location == NSNotFound) return s;
    static NSRegularExpression *numeric;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        numeric = [NSRegularExpression regularExpressionWithPattern:@"&#(x?)([0-9a-f]{1,6});" options:NSRegularExpressionCaseInsensitive error:NULL];
    });
    NSDictionary *named = @{ @"&nbsp;": @" ", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&apos;": @"'", @"&rsquo;": @"’",
                             @"&lsquo;": @"‘", @"&rdquo;": @"”", @"&ldquo;": @"“", @"&hellip;": @"…", @"&ndash;": @"–",
                             @"&mdash;": @"—", @"&bull;": @"•", @"&times;": @"×" };
    NSMutableString *out = [s mutableCopy];
    for (NSString *e in named) [out replaceOccurrencesOfString:e withString:named[e] options:0 range:NSMakeRange(0, out.length)];
    for (NSTextCheckingResult *m in [[numeric matchesInString:out options:0 range:NSMakeRange(0, out.length)] reverseObjectEnumerator]) {
        NSString *digits = [out substringWithRange:[m rangeAtIndex:2]];
        unsigned long value = strtoul(digits.UTF8String, NULL, [m rangeAtIndex:1].length ? 16 : 10);
        NSString *c = @"";
        if (value >= 0x10000 && value <= 0x10FFFF) {
            unichar pair[2] = { (unichar)(0xD800 + ((value - 0x10000) >> 10)), (unichar)(0xDC00 + ((value - 0x10000) & 0x3FF)) };
            c = [NSString stringWithCharacters:pair length:2];
        } else if (value > 0 && value <= 0xFFFF && (value < 0xD800 || value > 0xDFFF)) {
            unichar one = (unichar)value;
            c = [NSString stringWithCharacters:&one length:1];
        }
        [out replaceCharactersInRange:m.range withString:c];
    }
    [out replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange(0, out.length)];
    return out;
}

// Mojang's HTML as plain text: paragraphs and line breaks as lines, list items "• " (4 spaces in a level), headings in
// capitals - as the wiki's text comes out
static NSString *KOHTMLText(NSString *html)
{
    if (![html isKindOfClass:[NSString class]] || !html.length) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:html.length];
    NSCharacterSet *nameEnd = [NSCharacterSet characterSetWithCharactersInString:@" \t\r\n/>"];
    NSUInteger n = html.length, i = 0, headingFrom = NSNotFound;
    NSInteger lists = 0;
    while (i < n) {
        NSRange lt = [html rangeOfString:@"<" options:0 range:NSMakeRange(i, n - i)];
        NSUInteger textEnd = lt.location == NSNotFound ? n : lt.location;
        if (textEnd > i) {
            // (the HTML's own line breaks are spaces; only spaces between two tags: one, if any)
            NSString *run = [html substringWithRange:NSMakeRange(i, textEnd - i)];
            run = [[run componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
            if ([run stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length) [out appendString:run];
            else if (out.length && ![out hasSuffix:@"\n"] && ![out hasSuffix:@" "]) [out appendString:@" "];
        }
        if (lt.location == NSNotFound) break;
        NSRange gt = [html rangeOfString:@">" options:0 range:NSMakeRange(lt.location, n - lt.location)];
        if (gt.location == NSNotFound) break;
        NSString *tag = [[html substringWithRange:NSMakeRange(lt.location + 1, gt.location - lt.location - 1)] lowercaseString];
        i = gt.location + 1;
        BOOL closing = [tag hasPrefix:@"/"];
        if (closing) tag = [tag substringFromIndex:1];
        NSRange end = [tag rangeOfCharacterFromSet:nameEnd];
        NSString *name = end.location == NSNotFound ? tag : [tag substringToIndex:end.location];
        if ([name isEqualToString:@"br"]) {
            [out appendString:@"\n"];
        } else if ([name isEqualToString:@"p"] || [name isEqualToString:@"div"]) {
            // (in a list the items make the lines)
            if (!lists) [out appendString:@"\n"];
        } else if ([name isEqualToString:@"ul"] || [name isEqualToString:@"ol"]) {
            // (each item starts its own line; the end of a whole list ends one)
            lists = MAX(0, lists + (closing ? -1 : 1));
            if (closing && !lists) [out appendString:@"\n"];
        } else if ([name isEqualToString:@"li"]) {
            if (closing) continue;
            [out appendString:@"\n"];
            for (NSInteger k = 1; k < lists; k++) [out appendString:@"    "];
            [out appendString:@"• "];
        } else if (name.length == 2 && [name characterAtIndex:0] == 'h' && isdigit([name characterAtIndex:1])) {
            if (!closing) {
                [out appendString:@"\n\n"];
                headingFrom = out.length;
            } else if (headingFrom != NSNotFound && headingFrom <= out.length) {
                NSRange r = NSMakeRange(headingFrom, out.length - headingFrom);
                [out replaceCharactersInRange:r withString:[[out substringWithRange:r] uppercaseString]];
                [out appendString:@"\n"];
                headingFrom = NSNotFound;
            }
        }
    }
    // line by line: spaces once (an item's indent kept), at most one empty line in a row
    NSMutableArray *lines = [NSMutableArray array];
    BOOL empty = YES;
    for (NSString *raw in [KOEntities(out) componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        while ([line rangeOfString:@"  "].location != NSNotFound) line = [line stringByReplacingOccurrencesOfString:@"  " withString:@" "];
        if (!line.length || [line isEqualToString:@"•"]) {
            if (!empty) [lines addObject:@""];
            empty = YES;
            continue;
        }
        NSUInteger indent = 0;
        if ([line hasPrefix:@"• "]) while (indent < raw.length && [raw characterAtIndex:indent] == ' ') indent++;
        [lines addObject:[[@"" stringByPaddingToLength:indent withString:@" " startingAtIndex:0] stringByAppendingString:line]];
        empty = NO;
    }
    return [[lines componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// The news's API answers with JavaScript: "var tumblr_api_read = {...};"
static NSDictionary *KONewsJSON(NSData *data)
{
    NSString *s = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    NSRange open = [s rangeOfString:@"{"], close = [s rangeOfString:@"}" options:NSBackwardsSearch];
    if (!s || open.location == NSNotFound || close.location == NSNotFound || close.location < open.location) return nil;
    NSData *json = [[s substringWithRange:NSMakeRange(open.location, close.location + 1 - open.location)] dataUsingEncoding:NSUTF8StringEncoding];
    id o = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
    return [o isKindOfClass:[NSDictionary class]] ? o : nil;
}

// "2016-11-17" as days from 1970-01-01 (0 when it is not a date)
static long KODay(NSString *day)
{
    int y, m, d;
    if (![day isKindOfClass:[NSString class]] || day.length < 10 || sscanf(day.UTF8String, "%4d-%2d-%2d", &y, &m, &d) != 3) return 0;
    y -= m <= 2;
    long era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400;
    long doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    return era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468;
}

// The versions a post of the news is about, by its title ("Minecraft Beta 1.7.3", "Minecraft 1.7.3 & 1.7.4", "Minecraft
// 1.11 - The Exploration Update"), as Mojang's list names them: a name the list lacks is the first of the list's that
// start with it, released within 3 days of the post (the news's Beta 1.3 is b1.3b there, its 1.2 1.2.1 - the list's
// dates of that time are a day or so off)
static NSArray *KONewsVersions(NSString *title, NSString *day, NSDictionary *released)
{
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^Minecraft (Beta )?([0-9]+(?:\\.[0-9]+)+(?:_[0-9]+)?)(?: & ([0-9]+(?:\\.[0-9]+)+(?:_[0-9]+)?))?(?=$|[ ,:-])"
                                                       options:0 error:NULL];
    });
    if (![title isKindOfClass:[NSString class]]) return @[];
    NSTextCheckingResult *m = [re firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
    if (!m) return @[];
    NSString *prefix = [m rangeAtIndex:1].location != NSNotFound ? @"b" : @"";
    long postDay = KODay(day);
    NSMutableArray *names = [NSMutableArray array];
    for (NSUInteger g = 2; g <= 3; g++) {
        NSRange r = [m rangeAtIndex:g];
        if (r.location == NSNotFound) continue;
        NSString *name = [prefix stringByAppendingString:[title substringWithRange:r]];
        if (!released.count || released[name]) {
            [names addObject:name];
            continue;
        }
        NSString *best = nil;
        long bestDay = 0;
        for (NSString *other in released) {
            if (other.length <= name.length || ![other hasPrefix:name]) continue;
            unichar next = [other characterAtIndex:name.length];
            if (next >= '0' && next <= '9') continue;   // (1.1 is not 1.10)
            long otherDay = KODay(released[other]);
            if (labs(otherDay - postDay) > 3) continue;
            if (!best || otherDay < bestDay || (otherDay == bestDay && [other compare:best] == NSOrderedAscending)) {
                best = other;
                bestDay = otherDay;
            }
        }
        if (best) [names addObject:best];
    }
    return names;
}

// Mojang's notes by version name, from what was fetched: { from: news, title, date, text } or { from: patch, title,
// date, path, short } (the whole text of a patch note is fetched with its version)
static NSDictionary *KOMojangNotes(NSDictionary *raw, NSDictionary *released)
{
    NSMutableDictionary *notes = [NSMutableDictionary dictionary];
    NSArray *news = [raw[@"news"] isKindOfClass:[NSArray class]] ? raw[@"news"] : @[];
    NSArray *patch = [raw[@"patch"] isKindOfClass:[NSArray class]] ? raw[@"patch"] : @[];
    for (NSDictionary *p in news) {
        if (![p isKindOfClass:[NSDictionary class]]) continue;
        NSString *day = [p[@"date"] isKindOfClass:[NSString class]] && [p[@"date"] length] >= 10 ? [p[@"date"] substringToIndex:10] : @"";
        NSArray *names = KONewsVersions(p[@"title"], day, released);
        NSString *text = names.count ? KOHTMLText(p[@"html"]) : nil;
        if (!text.length) continue;
        for (NSString *name in names)
            if (!notes[name]) notes[name] = @{ @"from": @"news", @"title": p[@"title"], @"date": day, @"text": text };
    }
    for (NSDictionary *e in patch) {
        if (![e isKindOfClass:[NSDictionary class]] || ![e[@"version"] isKindOfClass:[NSString class]] ||
            ![e[@"path"] isKindOfClass:[NSString class]] || notes[e[@"version"]]) continue;
        NSString *date = [e[@"date"] isKindOfClass:[NSString class]] && [e[@"date"] length] >= 10 ? [e[@"date"] substringToIndex:10] : @"";
        notes[e[@"version"]] = @{ @"from": @"patch", @"title": [e[@"title"] isKindOfClass:[NSString class]] ? e[@"title"] : e[@"version"],
                                  @"date": date, @"path": e[@"path"], @"short": KOEntities(e[@"short"]) };
    }
    return notes;
}

// Fetching Mojang's notes: the news's pages one after another, then the patch notes' list. `done` gets { news: [{ title,
// date, html }], patch: [{ version, title, date, path, short }] } and whether all of it came
@interface KOMojangFetch : NSObject
@property (nonatomic, strong) NSMutableArray *news, *patch;
@property (nonatomic) BOOL newsCame, patchCame;
@property (nonatomic, copy) void (^done)(NSDictionary *raw, BOOL whole);
- (void)start;
@end

@implementation KOMojangFetch

- (void)start
{
    self.news = [NSMutableArray array];
    self.patch = [NSMutableArray array];
    [self newsFrom:0];
}

- (void)newsFrom:(NSUInteger)start
{
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:KONewsPage, (unsigned long)start]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSDictionary *json = KONewsJSON(data);
        NSArray *posts = [json[@"posts"] isKindOfClass:[NSArray class]] ? json[@"posts"] : nil;
        if (!posts) {
            [self patchNotes];
            return;
        }
        for (NSDictionary *p in posts) {
            if (![p isKindOfClass:[NSDictionary class]] || ![p[@"regular-title"] isKindOfClass:[NSString class]]) continue;
            [self.news addObject:@{ @"title": p[@"regular-title"],
                                    @"date": [p[@"date-gmt"] isKindOfClass:[NSString class]] ? p[@"date-gmt"] : @"",
                                    @"html": [p[@"regular-body"] isKindOfClass:[NSString class]] ? p[@"regular-body"] : @"" }];
        }
        NSInteger total = [json[@"posts-total"] respondsToSelector:@selector(integerValue)] ? [json[@"posts-total"] integerValue] : 0;
        NSUInteger next = start + posts.count;
        if (posts.count && (NSInteger)next < total && next < 1000) {
            [self newsFrom:next];
            return;
        }
        self.newsCame = YES;
        [self patchNotes];
    }];
}

- (void)patchNotes
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:KOPatchNotes]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            NSArray *entries = [json isKindOfClass:[NSDictionary class]] && [json[@"entries"] isKindOfClass:[NSArray class]] ? json[@"entries"] : nil;
            NSMutableArray *patch = [NSMutableArray array];
            for (NSDictionary *e in entries) {
                if (![e isKindOfClass:[NSDictionary class]] || ![e[@"version"] isKindOfClass:[NSString class]] ||
                    ![e[@"contentPath"] isKindOfClass:[NSString class]]) continue;
                [patch addObject:@{ @"version": e[@"version"], @"path": e[@"contentPath"],
                                    @"title": [e[@"title"] isKindOfClass:[NSString class]] ? e[@"title"] : e[@"version"],
                                    @"date": [e[@"date"] isKindOfClass:[NSString class]] ? e[@"date"] : @"",
                                    @"short": [e[@"shortText"] isKindOfClass:[NSString class]] ? e[@"shortText"] : @"" }];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.patch = patch;
                self.patchCame = entries != nil;
                void (^done)(NSDictionary *, BOOL) = self.done;
                self.done = nil;
                if (done) done(@{ @"news": self.news, @"patch": self.patch }, self.newsCame && self.patchCame);
            });
        });
    }];
}

@end

static NSDictionary *g_released;          // Mojang's list: name -> "2016-11-17"
static NSDictionary *g_mojang;            // Mojang's notes by version name (KOMojangNotes)
static BOOL g_mojangMatched;              // (made with the list's names)
static NSMutableArray *g_mojangWaiting;   // the blocks waiting for g_mojang
static NSDate *g_mojangFailed;
static NSMutableDictionary *g_summaries;  // name -> a line of what is new (changelogs/summaries.1.plist)
static NSMutableArray *g_wanted;          // the summaries asked for, the last asked for at the end
static NSMutableDictionary *g_waiting;    // name -> the blocks waiting for its summary
static NSMutableSet *g_fetching;
static NSMutableDictionary *g_failed;     // name -> when it could not be had

// The first sentence of a line, short enough for a row of the list
static NSString *KOShort(NSString *s, NSUInteger most)
{
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSRange stop = [t rangeOfString:@". "];
    if (stop.location != NSNotFound && stop.location > 0) t = [t substringToIndex:stop.location];
    while (t.length && [@".:;," rangeOfString:[t substringFromIndex:t.length - 1]].location != NSNotFound) t = [t substringToIndex:t.length - 1];
    if (t.length > most) {
        NSRange space = [t rangeOfString:@" " options:NSBackwardsSearch range:NSMakeRange(0, most)];
        t = [[t substringToIndex:space.location != NSNotFound && space.location > most / 2 ? space.location : most] stringByAppendingString:@"…"];
    }
    return t;
}

// A heading of the text: a line in capitals
static BOOL KOIsHeading(NSString *line)
{
    return [line isEqualToString:[line uppercaseString]] && ![line isEqualToString:[line lowercaseString]];
}

@implementation KOChangelog

+ (void)setVersions:(NSArray *)versions
{
    NSMutableDictionary *released = [NSMutableDictionary dictionary];
    for (KOVersion *v in versions)
        if ([v isKindOfClass:[KOVersion class]] && !v.parent && v.identifier && v.released) released[v.identifier] = v.released;
    g_released = released;
}

+ (NSString *)wikiTitleFor:(NSString *)identifier
{
    NSString *rest = identifier.length > 1 ? [identifier substringFromIndex:1] : identifier;
    BOOL digit = rest.length && isdigit([rest characterAtIndex:0]);
    if ([identifier hasPrefix:@"a"] && digit) return [@"Java Edition Alpha v" stringByAppendingString:rest];
    if ([identifier hasPrefix:@"b"] && digit) return [@"Java Edition Beta " stringByAppendingString:rest];
    if ([identifier hasPrefix:@"c"] && digit) return [@"Java Edition Classic " stringByAppendingString:rest];
    if ([identifier hasPrefix:@"inf-"]) return [@"Java Edition Infdev " stringByAppendingString:[identifier substringFromIndex:4]];
    return [@"Java Edition " stringByAppendingString:identifier];
}

+ (NSString *)plainText:(NSString *)wikitext
{
    NSString *s = wikitext ?: @"";
    s = KOReplace(s, @"<!--.*?-->", @"");
    s = KOReplace(s, @"<ref[^>/]*/>", @"");
    s = KOReplace(s, @"<ref[^>]*>.*?</ref>", @"");
    s = KOReplace(s, @"<br\\s*/?>", @"\n");
    s = KOTemplatesOut(s);
    s = KOLinksOut(s);
    s = KOReplace(s, @"\\[https?://[^\\s\\]]+\\s+([^\\]]+)\\]", @"$1");
    s = KOReplace(s, @"\\[https?://[^\\s\\]]+\\]", @"");
    s = KOReplace(s, @"</?[a-z][^>]*>", @"");
    // (a line all in bold - "'''[[Concrete]]'''", the name of what the lines under it are about - a term of a
    // definition list)
    static NSRegularExpression *bold;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bold = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*'''([^'\\n]+?)'''[ \\t]*$" options:NSRegularExpressionAnchorsMatchLines error:NULL];
    });
    s = [bold stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@";$1"];
    s = [s stringByReplacingOccurrencesOfString:@"'''" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"''" withString:@""];
    NSDictionary *entities = @{ @"&nbsp;": @" ", @"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"",
                                @"&ndash;": @"–", @"&mdash;": @"—", @"&#x26;": @"&", @"&#39;": @"'" };
    for (NSString *e in entities) s = [s stringByReplacingOccurrencesOfString:e withString:entities[e]];

    // line by line: headings (until the sections that are not about the version: videos, trivia, ...), lists
    NSRegularExpression *heading = [NSRegularExpression regularExpressionWithPattern:@"^(=+)\\s*(.*?)\\s*=+\\s*$" options:0 error:NULL];
    NSRegularExpression *item = [NSRegularExpression regularExpressionWithPattern:@"^([*#:;]+)\\s*(.*)$" options:0 error:NULL];
    NSSet *after = [NSSet setWithArray:@[ @"videos", @"trivia", @"gallery", @"references", @"navigation", @"external links",
                                          @"see also", @"notes", @"screenshots", @"video" ]];
    NSMutableArray *lines = [NSMutableArray array];   // { text, level } - level 0 for text
    NSUInteger term = 0;   // (under a term the list's items go one level deeper: they are about it)
    for (NSString *raw in [s componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSTextCheckingResult *h = [heading firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (h) {
            NSUInteger level = [h rangeAtIndex:1].length;
            NSString *name = [[line substringWithRange:[h rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (level <= 2 && [after containsObject:[name lowercaseString]]) break;
            [lines addObject:@[ level <= 2 ? [name uppercaseString] : name, @(level) ]];
            term = 0;
            continue;
        }
        NSTextCheckingResult *m = [item firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (m) {
            NSString *marks = [line substringWithRange:[m rangeAtIndex:1]];
            NSString *text = [line substringWithRange:[m rangeAtIndex:2]];
            if (!text.length) continue;
            unichar kind = [marks characterAtIndex:marks.length - 1];
            if ([marks characterAtIndex:0] == ';') {
                // a term ("; Concrete", a line in bold): an item
                line = [NSString stringWithFormat:@"%@• %@", [@"" stringByPaddingToLength:(marks.length - 1) * 4 withString:@" " startingAtIndex:0], text];
                term = 1;
            } else {
                NSString *indent = [@"" stringByPaddingToLength:(marks.length - 1 + term) * 4 withString:@" " startingAtIndex:0];
                line = kind == '*' || kind == '#' ? [NSString stringWithFormat:@"%@• %@", indent, text] : [indent stringByAppendingString:text];
            }
        } else {
            term = 0;
        }
        [lines addObject:@[ line, @0 ]];
    }
    // headings with nothing under them out (the fixes, a table the templates took away)
    NSMutableArray *kept = [NSMutableArray array];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSUInteger level = [lines[i][1] unsignedIntegerValue];
        if (level) {
            BOOL content = NO;
            for (NSUInteger j = i + 1; j < lines.count; j++) {
                NSUInteger l = [lines[j][1] unsignedIntegerValue];
                if (l && l <= level) break;
                if (!l && [lines[j][0] length]) { content = YES; break; }
            }
            if (!content) continue;
            [kept addObject:@""];
        }
        [kept addObject:lines[i][0]];
    }
    NSString *text = [kept componentsJoinedByString:@"\n"];
    text = KOReplace(text, @"\n{3,}", @"\n\n");
    // (two spaces where a template was taken out of a sentence: one; a list's indent is left as it is)
    text = KOReplace(text, @"(?<=\\S) {2,}", @" ");
    text = KOReplace(text, @" +([.,;:])", @"$1");
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)pathOf:(NSString *)file
{
    NSString *dir = [[KOJava dataPath] stringByAppendingPathComponent:@"changelogs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:file];
}

// (".3": the text as this Kostka makes it - one kept by an earlier one is made anew)
+ (NSString *)cachePath:(NSString *)identifier
{
    return [self pathOf:[identifier stringByAppendingString:@".3.txt"]];
}

// The wiki's text (main thread); the work on it in the background - a page of a large update is some 100 KB
+ (void)wikiText:(NSString *)identifier done:(void (^)(NSString *text, NSError *error))done
{
    NSString *cache = [self cachePath:identifier];
    NSString *kept = [NSString stringWithContentsOfFile:cache encoding:NSUTF8StringEncoding error:NULL];
    if (kept.length) {
        done(kept, nil);
        return;
    }
    NSString *title = [[self wikiTitleFor:identifier] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://minecraft.wiki/api.php?action=parse&format=json&redirects=1&prop=wikitext&page=%@", title]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            id wikitext = [json isKindOfClass:[NSDictionary class]] ? json[@"parse"][@"wikitext"][@"*"] : nil;
            NSString *text = [wikitext isKindOfClass:[NSString class]] ? [self plainText:wikitext] : nil;
            if (text.length) [text writeToFile:cache atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (text.length) done(text, nil);
                else done(nil, error ?: [KONet errorWithText:L(@"The Minecraft Wiki has no page about this version.")]);
            });
        });
    }];
}

// Mojang's notes on every version it wrote about (KOMojangNotes), on the main thread: from changelogs/mojang.1.json
// while it is younger than a week, else fetched (what was kept is what there is when that fails; once a minute at
// most)
+ (void)mojang:(void (^)(NSDictionary *notes))done
{
    if (g_mojang && (g_mojangMatched || !g_released.count)) {
        done(g_mojang);
        return;
    }
    if (!g_mojangWaiting) g_mojangWaiting = [NSMutableArray array];
    [g_mojangWaiting addObject:[done copy]];
    if (g_mojangWaiting.count > 1) return;   // (being fetched)
    NSString *path = [self pathOf:@"mojang.1.json"];
    NSData *kept = [NSData dataWithContentsOfFile:path];
    NSDate *changed = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileModificationDate];
    BOOL fresh = kept && changed && [changed timeIntervalSinceNow] > -7 * 86400;
    BOOL failedLately = g_mojangFailed && [g_mojangFailed timeIntervalSinceNow] > -60;
    if (fresh || failedLately) {
        [self mojangFrom:kept];
        return;
    }
    KOMojangFetch *fetch = [[KOMojangFetch alloc] init];
    fetch.done = ^(NSDictionary *raw, BOOL whole) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:raw options:0 error:NULL];
        if (whole) [data writeToFile:path atomically:YES];
        else g_mojangFailed = [NSDate date];
        KOLog(@"changelog: Mojang's notes %@ (%lu posts of the news, %lu patch notes)", whole ? @"fetched" : @"not all fetched",
              (unsigned long)[raw[@"news"] count], (unsigned long)[raw[@"patch"] count]);
        [self mojangFrom:whole || !kept ? data : kept];
    };
    [fetch start];
}

+ (void)mojangFrom:(NSData *)data
{
    NSDictionary *released = g_released;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        id raw = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *notes = [raw isKindOfClass:[NSDictionary class]] ? KOMojangNotes(raw, released) : @{};
        dispatch_async(dispatch_get_main_queue(), ^{
            // (none at all: asked for again later)
            if (notes.count) {
                g_mojang = notes;
                g_mojangMatched = released.count > 0;
            }
            NSArray *waiting = g_mojangWaiting;
            g_mojangWaiting = nil;
            for (void (^w)(NSDictionary *) in waiting) w(notes);
        });
    });
}

// The whole of one of the launcher's patch notes (changelogs/<name>.mojang.1.txt); its first lines when it cannot be
// fetched
+ (void)patchText:(NSDictionary *)note name:(NSString *)name done:(void (^)(NSString *text))done
{
    NSString *cache = [self pathOf:[name stringByAppendingString:@".mojang.1.txt"]];
    NSString *kept = [NSString stringWithContentsOfFile:cache encoding:NSUTF8StringEncoding error:NULL];
    if (kept.length) {
        done(kept);
        return;
    }
    NSURL *url = [NSURL URLWithString:[KOPatchNotesBase stringByAppendingString:note[@"path"]]];
    if (!url) {
        done(note[@"short"]);
        return;
    }
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            id body = [json isKindOfClass:[NSDictionary class]] ? json[@"body"] : nil;
            NSString *text = [body isKindOfClass:[NSString class]] ? KOHTMLText(body) : nil;
            if (text.length) [text writeToFile:cache atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{ done(text.length ? text : note[@"short"]); });
        });
    }];
}

+ (void)load:(NSString *)identifier done:(void (^)(NSDictionary *, NSString *, NSError *))done
{
    [self mojang:^(NSDictionary *notes) {
        NSDictionary *note = notes[identifier];
        if ([note[@"from"] isEqualToString:@"patch"]) {
            // (the launcher's patch notes say it all: the wiki only when they cannot be had)
            [self patchText:note name:identifier done:^(NSString *text) {
                if (text.length) {
                    NSMutableDictionary *whole = [note mutableCopy];
                    whole[@"text"] = text;
                    done(whole, nil, nil);
                    return;
                }
                [self wikiText:identifier done:^(NSString *wiki, NSError *error) { done(nil, wiki, wiki ? nil : error); }];
            }];
            return;
        }
        [self wikiText:identifier done:^(NSString *wiki, NSError *error) {
            done(note, wiki, note || wiki ? nil : error);
        }];
    }];
}

#pragma mark Summaries

// The items of the text's first level, each - the wiki's are about a thing, its items under it:
// - with nothing under it, or Mojang's: itself ("Added cursed enchantments")
// - a group's word ("General", "Blocks"): its first item
// - under Additions: the thing's name ("Concrete")
// - else the thing and the first word on it ("Trapped chests: Now change their texture to suit Christmas ...")
// Mojang's first line goes first ("New mobs and new places to put your precious items!"); the wiki's ("1.12.2 is a minor
// update for Java Edition that was released on ...") only when there are no items
+ (NSString *)summaryOf:(NSString *)text mojang:(BOOL)mojang
{
    if (![text isKindOfClass:[NSString class]]) return nil;
    static NSSet *groups;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        groups = [NSSet setWithArray:@[ @"general", @"gameplay", @"world generation", @"world", @"blocks", @"items", @"blocks and items",
                                        @"mobs", @"entities", @"non-mob entities", @"biomes", @"structures", @"commands",
                                        @"command format", @"other", @"miscellaneous", @"sounds", @"options", @"menu screens",
                                        @"graphics", @"technical", @"user interface", @"multiplayer" ]];
    });
    NSMutableArray *lines = [NSMutableArray array];   // { depth, words, the section (the heading in capitals above) }
    NSString *section = @"", *lead = nil;
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length < 2) continue;
        unichar mark = [line characterAtIndex:0];
        BOOL item = line.length > 2 && [line characterAtIndex:1] == ' ' && (mark == 0x2022 || mark == '+' || mark == '-' || mark == '*');
        if (item) {
            NSUInteger spaces = 0;
            while (spaces < raw.length && [raw characterAtIndex:spaces] == ' ') spaces++;
            [lines addObject:@[ @(spaces / 4), [line substringFromIndex:2], section ]];
        } else if (KOIsHeading(line)) {
            section = line;
        } else if (!lines.count && !lead) {
            lead = line;
        }
    }
    NSMutableArray *parts = [NSMutableArray array];
    NSUInteger length = 0;
    for (NSUInteger i = 0; i < lines.count && parts.count < 6 && length <= 200; i++) {
        if ([lines[i][0] integerValue] != 0) continue;
        NSString *thing = lines[i][1];
        NSString *first = i + 1 < lines.count && [lines[i + 1][0] integerValue] == 1 ? lines[i + 1][1] : nil;
        NSString *part;
        if (!first || mojang) part = KOShort(thing, 80);
        else if ([groups containsObject:[thing lowercaseString]]) part = KOShort(first, 80);
        else if ([lines[i][2] hasPrefix:@"ADDITION"]) part = KOShort(thing, 60);
        else part = [NSString stringWithFormat:@"%@: %@", KOShort(thing, 40), KOShort(first, 70)];
        if (!part.length || [parts containsObject:part]) continue;
        [parts addObject:part];
        length += part.length + 3;
    }
    if (lead && (mojang ? lead.length <= 120 : !parts.count)) [parts insertObject:KOShort(lead, mojang ? 120 : 180) atIndex:0];
    return parts.count ? [parts componentsJoinedByString:@" · "] : nil;
}

// (".2": made as this Kostka makes them)
+ (NSMutableDictionary *)summaries
{
    if (!g_summaries)
        g_summaries = [NSMutableDictionary dictionaryWithContentsOfFile:[self pathOf:@"summaries.2.plist"]] ?: [NSMutableDictionary dictionary];
    return g_summaries;
}

// (written a moment after the last one came: not once a row)
+ (void)keepSummaries
{
    static BOOL planned;
    if (planned) return;
    planned = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        planned = NO;
        [[g_summaries copy] writeToFile:[self pathOf:@"summaries.2.plist"] atomically:YES];
    });
}

+ (NSString *)summaryFor:(NSString *)identifier
{
    NSString *s = identifier ? [self summaries][identifier] : nil;
    return s.length ? s : nil;
}

+ (void)prepare:(void (^)(void))done
{
    [self mojang:^(NSDictionary *notes) {
        NSMutableDictionary *summaries = [self summaries];
        BOOL changed = NO;
        for (NSString *name in notes) {
            NSString *text = notes[name][@"text"];
            NSString *s = text ? [self summaryOf:text mojang:YES] : nil;
            if (s.length && ![summaries[name] isEqualToString:s]) {
                summaries[name] = s;
                changed = YES;
            }
        }
        if (changed) [self keepSummaries];
        if (done) done();
    }];
}

+ (void)want:(NSString *)identifier done:(void (^)(NSString *))done
{
    if (!identifier.length) return;
    if (!g_wanted) {
        g_wanted = [NSMutableArray array];
        g_waiting = [NSMutableDictionary dictionary];
        g_fetching = [NSMutableSet set];
        g_failed = [NSMutableDictionary dictionary];
    }
    NSMutableArray *dones = g_waiting[identifier];
    if (!dones) g_waiting[identifier] = dones = [NSMutableArray array];
    if (done) [dones addObject:[done copy]];
    if (![g_fetching containsObject:identifier]) {
        [g_wanted removeObject:identifier];
        [g_wanted addObject:identifier];
        // (rows long scrolled past: forgotten)
        while (g_wanted.count > 30) {
            [g_waiting removeObjectForKey:g_wanted[0]];
            [g_wanted removeObjectAtIndex:0];
        }
    }
    [self work];
}

// Two at a time, the last asked for first
+ (void)work
{
    while (g_fetching.count < 2 && g_wanted.count) {
        NSString *name = [g_wanted lastObject];
        [g_wanted removeLastObject];
        NSString *known = [self summaryFor:name];
        NSDate *failed = g_failed[name];
        if (known || (failed && [failed timeIntervalSinceNow] > -60)) {
            [self finish:name summary:known];
            continue;
        }
        [g_fetching addObject:name];
        [self load:name done:^(NSDictionary *mojang, NSString *wiki, NSError *error) {
            NSString *s = mojang[@"text"] ? [self summaryOf:mojang[@"text"] mojang:YES] : nil;
            if (!s.length && wiki.length) s = [self summaryOf:wiki mojang:NO];
            if (s.length) {
                [self summaries][name] = s;
                [self keepSummaries];
            } else {
                g_failed[name] = [NSDate date];
            }
            [g_fetching removeObject:name];
            [self finish:name summary:s.length ? s : nil];
            dispatch_async(dispatch_get_main_queue(), ^{ [self work]; });
        }];
    }
}

// (always a moment later: the list may be drawing the row that asked)
+ (void)finish:(NSString *)name summary:(NSString *)summary
{
    NSArray *dones = [g_waiting[name] copy];
    [g_waiting removeObjectForKey:name];
    if (!dones.count) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (void (^d)(NSString *) in dones) d(summary);
    });
}

@end
