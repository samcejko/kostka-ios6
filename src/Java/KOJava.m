#import <UIKit/UIKit.h>
#import "KOJava.h"
#import "KOCommon.h"
#include <dlfcn.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <mach/mach.h>
#include <libkern/OSAtomic.h>
#include "jni.h"

typedef jint (JNICALL *KOCreateJavaVM)(JavaVM **vm, void **env, void *args);

static BOOL g_started;
static int g_logFd = -1;

// Everything a start needs, handed to the VM's thread
@interface KOJavaLaunch : NSObject
@property (nonatomic, copy) NSString *libjvm, *mainClass, *workingDirectory;
@property (nonatomic, strong) NSArray *options, *args;
@property (nonatomic, copy) void (^done)(int, NSString *);
@end
@implementation KOJavaLaunch
@end

// The alert of a game that has stopped: its button closes Kostka (one Java VM per process)
@interface KOStoppedAlert : NSObject <UIAlertViewDelegate>
@end
@implementation KOStoppedAlert
- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    exit(0);
}
@end

@implementation KOJava

+ (NSString *)dataPath
{
    // (Kostka lives in /Applications: its home is /var/mobile, shared with the system's apps; its files are here)
    NSString *p = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Kostka"];
    [[NSFileManager defaultManager] createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:NULL];
    return p;
}

+ (NSString *)runtimePath
{
    NSString *downloaded = [[self dataPath] stringByAppendingPathComponent:@"jre"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[downloaded stringByAppendingPathComponent:@"lib/client/libjvm.dylib"]]) return downloaded;
    return [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"jre"];
}

+ (NSString *)logPath
{
    return [[self dataPath] stringByAppendingPathComponent:@"java.log"];
}

+ (int)memoryInUse
{
    struct task_basic_info info;
    mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return (int)(info.resident_size >> 20);
}

+ (void)note:(NSString *)format, ...
{
    static FILE *f;
    static CFAbsoluteTime t0;
    va_list ap;
    va_start(ap, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    @synchronized (self) {
        if (!f) {
            f = fopen([[[self dataPath] stringByAppendingPathComponent:@"run.txt"] fileSystemRepresentation], "w");
            t0 = CFAbsoluteTimeGetCurrent();
        }
        if (!f) return;
        fprintf(f, "%.0f %s\n", CFAbsoluteTimeGetCurrent() - t0, [line UTF8String]);
        fflush(f);
    }
}

// Why the game stopped, from what Java printed last (java.log): the last exception, leaving out the ones that are
// part of every start here (no game controllers, Mojang's old resource server gone) and Kostka's own AWT refusing the
// text area of an old version's crash screen (the cause is printed before it)
+ (NSString *)stopReason
{
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:[self logPath]];
    if (!h) return nil;
    unsigned long long size = [h seekToEndOfFile];
    [h seekToFileOffset:size > 65536 ? size - 65536 : 0];
    NSData *data = [h readDataToEndOfFile];
    [h closeFile];
    // (the cut may fall inside a character: then as Latin-1, which takes any byte - exceptions are ASCII anyway)
    NSString *tail = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?:
                     [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!tail) return nil;
    NSRegularExpression *exception = [NSRegularExpression regularExpressionWithPattern:
        @"^(Exception in thread \"[^\"]*\" )?([a-zA-Z_$][\\w$]*\\.)+[\\w$]*(Exception|Error)\\b.*$" options:0 error:NULL];
    NSString *found = nil;
    for (NSString *line in [tail componentsSeparatedByString:@"\n"]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![exception firstMatchInString:t options:0 range:NSMakeRange(0, t.length)]) continue;
        if ([t rangeOfString:@"HeadlessException"].location != NSNotFound ||
            [t rangeOfString:@"initialise controllers"].location != NSNotFound ||
            [t rangeOfString:@"MinecraftResources"].location != NSNotFound) continue;
        found = t;
    }
    return found.length > 240 ? [[found substringToIndex:240] stringByAppendingString:@"…"] : found;
}

static void KOShowStopped(int code)
{
    static volatile int32_t shown;
    static KOStoppedAlert *delegate;
    if (!OSAtomicCompareAndSwap32(0, 1, &shown)) return;
    NSString *reason = [KOJava stopReason];
    KOLog(@"game stopped: %d %@", code, reason ?: @"");
    [KOJava note:@"stopped %d %@", code, reason ?: @""];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *closing = L(@"Kostka closes: open it again to play.");
        NSString *message = reason.length ? [NSString stringWithFormat:@"%@\n\n%@", reason, closing] : closing;
        delegate = [[KOStoppedAlert alloc] init];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:L(@"The game has stopped") message:message delegate:delegate
                                              cancelButtonTitle:L(@"OK") otherButtonTitles:nil];
        [alert show];
    });
}

// HotSpot's exit hook (the VM option "exit"): System.exit ends here. A plain quit ends the app at once; a game that
// ends with an error (1.6 and newer do after their crash report) has its reason shown first.
static void JNICALL KOJavaExit(jint code)
{
    [KOJava note:@"java exit %d", (int)code];
    if (code == 0) exit(0);
    KOShowStopped((int)code);
    for (;;) sleep(60);
}

// While Java runs, the app's memory goes into the log each time it has moved by 16 MB: the iPad 2 warns from about
// 250 MB and ends the app at about 320, and what each version takes shows here. Every 2 seconds the run's notes get
// the frames the game has drawn, its window and the memory (LWJGL's counters, if it is loaded). And a game that has
// closed its window and does nothing more for 8 seconds has stopped: Classic to 1.5.2 then show their crash report in
// an AWT window, which iOS has not - Kostka says so instead.
static void KOWatchMemory(void)
{
    static dispatch_source_t timer;
    static int logged;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 2 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(timer, ^{
        int mb = [KOJava memoryInUse];
        if (mb >= 0 && abs(mb - logged) >= 16) {
            logged = mb;
            KOLog(@"memory: %d MB", mb);
        }
        static int *frames, *width, *height, *grabbed, *windows;
        if (!frames) {
            frames = (int *)dlsym(RTLD_DEFAULT, "ko_game_frames");
            width = (int *)dlsym(RTLD_DEFAULT, "ko_game_width");
            height = (int *)dlsym(RTLD_DEFAULT, "ko_game_height");
            grabbed = (int *)dlsym(RTLD_DEFAULT, "ko_game_grabbed");
            windows = (int *)dlsym(RTLD_DEFAULT, "ko_game_windows");
        }
        [KOJava note:@"progress frames=%d window=%dx%d memory=%d grabbed=%d", frames ? *frames : 0, width ? *width : 0,
            height ? *height : 0, mb, grabbed ? *grabbed : 0];
        static BOOL hadWindow;
        static CFAbsoluteTime goneSince;
        if (windows && *windows > 0) {
            hadWindow = YES;
            goneSince = 0;
        } else if (windows && hadWindow) {
            if (!goneSince) goneSince = CFAbsoluteTimeGetCurrent();
            else if (CFAbsoluteTimeGetCurrent() - goneSince > 8) KOShowStopped(-1);
        }
    });
    dispatch_resume(timer);
}

// What Java writes to stdout and stderr goes through a pipe: into java.log, and each line into the system log - at
// most 30 lines a second there (a game that logs every frame would slow itself down; java.log keeps everything)
static void *KOJavaLogReader(void *arg)
{
    int fd = (int)(intptr_t)arg;
    char buf[4096];
    NSMutableData *line = [NSMutableData data];
    ssize_t n;
    time_t second = 0;
    int inSecond = 0, skipped = 0;
    while ((n = read(fd, buf, sizeof buf)) > 0) {
        if (g_logFd >= 0) write(g_logFd, buf, n);
        for (ssize_t i = 0; i < n; i++) {
            if (buf[i] == '\n') {
                time_t now = time(NULL);
                if (now != second) {
                    if (skipped) NSLog(@"[Kostka] java: (%d more lines in java.log)", skipped);
                    second = now;
                    inSecond = skipped = 0;
                }
                if (++inSecond <= 30) {
                    @autoreleasepool {
                        NSString *s = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] ?: @"(binary)";
                        NSLog(@"[Kostka] java: %@", s);
                    }
                } else {
                    skipped++;
                }
                [line setLength:0];
            } else {
                [line appendBytes:buf + i length:1];
            }
        }
    }
    return NULL;
}

static void KORedirectOutput(void)
{
    g_logFd = open([[KOJava logPath] fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int p[2];
    if (pipe(p) != 0) return;
    dup2(p[1], STDOUT_FILENO);
    dup2(p[1], STDERR_FILENO);
    close(p[1]);
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    pthread_t reader;
    pthread_create(&reader, NULL, KOJavaLogReader, (void *)(intptr_t)p[0]);
    pthread_detach(reader);
}

static void KOFinish(KOJavaLaunch *l, int code, NSString *error)
{
    if (error) KOLog(@"java: %@", error);
    KOLog(@"java: finished with %d", code);
    [KOJava note:@"java finished %d %@", code, error ?: @""];
    dispatch_async(dispatch_get_main_queue(), ^{ if (l.done) l.done(code, error); });
}

static void *KOJavaThread(void *arg)
{
    @autoreleasepool {
        KOJavaLaunch *l = (__bridge_transfer KOJavaLaunch *)arg;
        KORedirectOutput();
        // (games keep files next to themselves: the working folder is the game's own, not the root of the system)
        chdir([(l.workingDirectory ?: [KOJava dataPath]) fileSystemRepresentation]);
        KOLog(@"java: loading %@", l.libjvm);
        void *h = dlopen([l.libjvm fileSystemRepresentation], RTLD_NOW | RTLD_GLOBAL);
        if (!h) { KOFinish(l, -1, [NSString stringWithFormat:@"dlopen failed: %s", dlerror()]); return NULL; }
        KOCreateJavaVM create = (KOCreateJavaVM)dlsym(h, "JNI_CreateJavaVM");
        if (!create) { KOFinish(l, -1, @"JNI_CreateJavaVM not found"); return NULL; }

        NSUInteger n = l.options.count;
        JavaVMOption *opts = calloc(n + 1, sizeof(JavaVMOption));
        NSMutableArray *keep = [NSMutableArray array];
        for (NSUInteger i = 0; i < n; i++) {
            NSData *d = [[l.options[i] stringByAppendingString:@"\0"] dataUsingEncoding:NSUTF8StringEncoding];
            [keep addObject:d];
            opts[i].optionString = (char *)d.bytes;
            KOLog(@"java: option %@", l.options[i]);
        }
        // (System.exit through Kostka: KOJavaExit)
        opts[n].optionString = "exit";
        opts[n].extraInfo = (void *)KOJavaExit;
        JavaVMInitArgs vmArgs;
        vmArgs.version = JNI_VERSION_1_8;
        vmArgs.nOptions = (jint)(n + 1);
        vmArgs.options = opts;
        vmArgs.ignoreUnrecognized = JNI_FALSE;
        JavaVM *vm = NULL;
        JNIEnv *env = NULL;
        CFTimeInterval t0 = CFAbsoluteTimeGetCurrent();
        jint rc = create(&vm, (void **)&env, &vmArgs);
        free(opts);
        if (rc != JNI_OK) { KOFinish(l, -1, [NSString stringWithFormat:@"JNI_CreateJavaVM failed: %d", rc]); return NULL; }
        KOLog(@"java: VM started in %.0f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000);
        [KOJava note:@"java started %@", l.mainClass];

        NSString *slashed = [l.mainClass stringByReplacingOccurrencesOfString:@"." withString:@"/"];
        jclass cls = (*env)->FindClass(env, [slashed UTF8String]);
        jmethodID main = cls ? (*env)->GetStaticMethodID(env, cls, "main", "([Ljava/lang/String;)V") : NULL;
        if (!main) {
            if ((*env)->ExceptionCheck(env)) (*env)->ExceptionDescribe(env);
            KOFinish(l, -1, [NSString stringWithFormat:@"no main in %@", l.mainClass]);
            return NULL;
        }
        jclass stringClass = (*env)->FindClass(env, "java/lang/String");
        jobjectArray args = (*env)->NewObjectArray(env, (jsize)l.args.count, stringClass, NULL);
        for (NSUInteger i = 0; i < l.args.count; i++) {
            jstring s = (*env)->NewStringUTF(env, [l.args[i] UTF8String]);
            (*env)->SetObjectArrayElement(env, args, (jsize)i, s);
            (*env)->DeleteLocalRef(env, s);
        }
        (*env)->CallStaticVoidMethod(env, cls, main, args);
        int code = 0;
        if ((*env)->ExceptionCheck(env)) {
            (*env)->ExceptionDescribe(env);
            code = 1;
        }
        // (DestroyJavaVM waits for the program's other threads)
        (*vm)->DestroyJavaVM(vm);
        KOFinish(l, code, nil);
    }
    return NULL;
}

+ (void)runMainClass:(NSString *)mainClass classPath:(NSArray *)classPath options:(NSArray *)options args:(NSArray *)args
                done:(void (^)(int, NSString *))done
{
    [self runMainClass:mainClass classPath:classPath options:options args:args workingDirectory:nil done:done];
}

+ (void)runMainClass:(NSString *)mainClass classPath:(NSArray *)classPath options:(NSArray *)options args:(NSArray *)args
    workingDirectory:(NSString *)workingDirectory done:(void (^)(int, NSString *))done
{
    if (g_started) {
        if (done) done(-1, L(@"Java has already run since the app was opened: close the app and open it again."));
        return;
    }
    g_started = YES;
    NSString *jre = [self runtimePath];
    KOJavaLaunch *l = [[KOJavaLaunch alloc] init];
    l.libjvm = [jre stringByAppendingPathComponent:@"lib/client/libjvm.dylib"];
    l.mainClass = mainClass;
    l.workingDirectory = workingDirectory;
    NSString *data = [self dataPath];
    NSString *tmp = [data stringByAppendingPathComponent:@"tmp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableArray *all = [NSMutableArray arrayWithArray:@[
        [@"-Djava.class.path=" stringByAppendingString:[classPath componentsJoinedByString:@":"]],
        @"-Djava.awt.headless=true",
        [@"-Djava.io.tmpdir=" stringByAppendingString:tmp],
        @"-Dfile.encoding=UTF-8",
        @"-XX:+UseSerialGC",
        @"-XX:ReservedCodeCacheSize=24m",
        @"-Xss512k",
        // (no performance data file in /tmp; a crash report of the VM where it can be written and read)
        @"-XX:-UsePerfData",
        [NSString stringWithFormat:@"-XX:ErrorFile=%@/hs_err_%%p.log", data],
    ]];
    [all addObjectsFromArray:options ?: @[]];
    l.options = all;
    l.args = args ?: @[];
    l.done = done;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 4u << 20);
    pthread_t t;
    if (pthread_create(&t, &attr, KOJavaThread, (__bridge_retained void *)l) != 0) {
        g_started = NO;
        if (done) done(-1, @"pthread_create failed");
    } else {
        KOWatchMemory();
    }
    pthread_attr_destroy(&attr);
}

@end
