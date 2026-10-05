#import "KONet.h"
#import "KOCommon.h"
#include <CommonCrypto/CommonDigest.h>

NSString *const KOErrorDomain = @"Kostka";

static NSString *KOHex(const unsigned char *bytes, size_t length)
{
    NSMutableString *s = [NSMutableString stringWithCapacity:length * 2];
    for (size_t i = 0; i < length; i++) [s appendFormat:@"%02x", bytes[i]];
    return s;
}

// One download: the data goes to a .part file while it comes, hashed on the way
@interface KODownloadTask : NSObject <NSURLConnectionDataDelegate>
@property (nonatomic, copy) NSString *path, *sha1;
@property (nonatomic, copy) void (^progress)(long long, long long);
@property (nonatomic, copy) void (^done)(NSError *);
@property (nonatomic, strong) NSFileHandle *file;
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic) long long received, expected;
@property (nonatomic) NSInteger status;
@end

@implementation KODownloadTask {
    CC_SHA1_CTX _hash;
}

static NSMutableSet *g_tasks;   // (the running ones, kept alive)

- (NSString *)partPath
{
    return [self.path stringByAppendingString:@".part"];
}

- (void)start:(NSURL *)url
{
    if (!g_tasks) g_tasks = [NSMutableSet set];
    [g_tasks addObject:self];
    CC_SHA1_Init(&_hash);
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] createFileAtPath:[self partPath] contents:nil attributes:nil];
    self.file = [NSFileHandle fileHandleForWritingAtPath:[self partPath]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    [request setValue:@"Kostka/0.1 (iOS 6)" forHTTPHeaderField:@"User-Agent"];
    self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}

- (void)finish:(NSError *)error
{
    [self.file closeFile];
    self.file = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!error) {
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1_Final(digest, &_hash);
        NSString *got = KOHex(digest, sizeof digest);
        if (self.sha1.length && ![got isEqualToString:[self.sha1 lowercaseString]]) {
            error = [KONet errorWithText:[NSString stringWithFormat:L(@"The download of %@ is damaged (its checksum does not match)."),
                                          [self.path lastPathComponent]]];
        }
    }
    if (error) {
        [fm removeItemAtPath:[self partPath] error:NULL];
    } else {
        [fm removeItemAtPath:self.path error:NULL];
        [fm moveItemAtPath:[self partPath] toPath:self.path error:NULL];
    }
    void (^done)(NSError *) = self.done;
    self.done = nil;
    self.progress = nil;
    [g_tasks removeObject:self];
    if (done) done(error);
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
    self.expected = response.expectedContentLength;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (self.status != 200) return;
    [self.file writeData:data];
    CC_SHA1_Update(&_hash, data.bytes, (CC_LONG)data.length);
    self.received += data.length;
    if (self.progress) self.progress(self.received, self.expected);
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if (self.status != 200) {
        [self finish:[KONet errorWithText:[NSString stringWithFormat:L(@"The server answered %ld."), (long)self.status]]];
        return;
    }
    [self finish:nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self finish:error];
}

@end

@implementation KONet

+ (NSError *)errorWithText:(NSString *)text
{
    return [NSError errorWithDomain:KOErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: text }];
}

+ (void)fetchJSON:(NSURL *)url done:(void (^)(id, NSData *, NSError *))done
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [request setValue:@"Kostka/0.1 (iOS 6)" forHTTPHeaderField:@"User-Agent"];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (!error && status != 200) error = [KONet errorWithText:[NSString stringWithFormat:L(@"The server answered %ld."), (long)status]];
        id json = nil;
        if (!error) {
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }
        if (error) KOLog(@"fetch %@: %@", url, error);
        done(error ? nil : json, error ? nil : data, error);
    }];
}

+ (NSString *)sha1OfFile:(NSString *)path
{
    NSInputStream *in = [NSInputStream inputStreamWithFileAtPath:path];
    if (!in) return nil;
    [in open];
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    uint8_t buf[65536];
    NSInteger n;
    BOOL any = NO;
    while ((n = [in read:buf maxLength:sizeof buf]) > 0) {
        CC_SHA1_Update(&ctx, buf, (CC_LONG)n);
        any = YES;
    }
    [in close];
    if (n < 0 || (!any && ![[NSFileManager defaultManager] fileExistsAtPath:path])) return nil;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);
    return KOHex(digest, sizeof digest);
}

+ (void)download:(NSURL *)url to:(NSString *)path sha1:(NSString *)sha1
        progress:(void (^)(long long, long long))progress done:(void (^)(NSError *))done
{
    if (sha1.length && [[NSFileManager defaultManager] fileExistsAtPath:path] &&
        [[self sha1OfFile:path] isEqualToString:[sha1 lowercaseString]]) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
        return;
    }
    KOLog(@"download %@", url);
    KODownloadTask *task = [[KODownloadTask alloc] init];
    task.path = path;
    task.sha1 = sha1;
    task.progress = progress;
    task.done = done;
    [task start:url];
}

@end
