#include <ctype.h>
#import "KOChangelog.h"
#import "KONet.h"
#import "KOJava.h"
#import "KOCommon.h"

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

@implementation KOChangelog

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
    for (NSString *raw in [s componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSTextCheckingResult *h = [heading firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (h) {
            NSUInteger level = [h rangeAtIndex:1].length;
            NSString *name = [[line substringWithRange:[h rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (level <= 2 && [after containsObject:[name lowercaseString]]) break;
            [lines addObject:@[ level <= 2 ? [name uppercaseString] : name, @(level) ]];
            continue;
        }
        NSTextCheckingResult *m = [item firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (m) {
            NSString *marks = [line substringWithRange:[m rangeAtIndex:1]];
            NSString *text = [line substringWithRange:[m rangeAtIndex:2]];
            if (!text.length) continue;
            NSString *indent = [@"" stringByPaddingToLength:(marks.length - 1) * 4 withString:@" " startingAtIndex:0];
            unichar kind = [marks characterAtIndex:marks.length - 1];
            line = kind == '*' || kind == '#' ? [NSString stringWithFormat:@"%@• %@", indent, text] : [indent stringByAppendingString:text];
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

+ (NSString *)cachePath:(NSString *)identifier
{
    NSString *dir = [[KOJava dataPath] stringByAppendingPathComponent:@"changelogs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    // (".2": the text as this Kostka makes it - one kept by an earlier one is made anew)
    return [dir stringByAppendingPathComponent:[identifier stringByAppendingString:@".2.txt"]];
}

+ (void)load:(NSString *)identifier done:(void (^)(NSString *, NSError *))done
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
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        id wikitext = [json isKindOfClass:[NSDictionary class]] ? json[@"parse"][@"wikitext"][@"*"] : nil;
        if (![wikitext isKindOfClass:[NSString class]]) {
            done(nil, error ?: [KONet errorWithText:L(@"The Minecraft Wiki has no page about this version.")]);
            return;
        }
        // (the work on the text is light: a page of a large update is some 100 KB)
        NSString *text = [self plainText:wikitext];
        if (text.length) [text writeToFile:cache atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        done(text, nil);
    }];
}

@end
