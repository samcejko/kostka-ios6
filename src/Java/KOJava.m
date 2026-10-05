#import "KOJava.h"
#import "KOCommon.h"
#include <dlfcn.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include "jni.h"

typedef jint (JNICALL *KOCreateJavaVM)(JavaVM **vm, void **env, void *args);

static BOOL g_started;
static int g_logFd = -1;

// Everything a start needs, handed to the VM's thread
@interface KOJavaLaunch : NSObject
@property (nonatomic, copy) NSString *libjvm, *mainClass;
@property (nonatomic, strong) NSArray *options, *args;
@property (nonatomic, copy) void (^done)(int, NSString *);
@end
@implementation KOJavaLaunch
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

// What Java writes to stdout and stderr goes through a pipe: into java.log, and each line into the system log
static void *KOJavaLogReader(void *arg)
{
    int fd = (int)(intptr_t)arg;
    char buf[4096];
    NSMutableData *line = [NSMutableData data];
    ssize_t n;
    while ((n = read(fd, buf, sizeof buf)) > 0) {
        if (g_logFd >= 0) write(g_logFd, buf, n);
        for (ssize_t i = 0; i < n; i++) {
            if (buf[i] == '\n') {
                @autoreleasepool {
                    NSString *s = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] ?: @"(binary)";
                    NSLog(@"[Kostka] java: %@", s);
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
    dispatch_async(dispatch_get_main_queue(), ^{ if (l.done) l.done(code, error); });
}

static void *KOJavaThread(void *arg)
{
    @autoreleasepool {
        KOJavaLaunch *l = (__bridge_transfer KOJavaLaunch *)arg;
        KORedirectOutput();
        // (games keep files next to themselves: the working folder is Kostka's own, not the root of the system)
        chdir([[KOJava dataPath] fileSystemRepresentation]);
        KOLog(@"java: loading %@", l.libjvm);
        void *h = dlopen([l.libjvm fileSystemRepresentation], RTLD_NOW | RTLD_GLOBAL);
        if (!h) { KOFinish(l, -1, [NSString stringWithFormat:@"dlopen failed: %s", dlerror()]); return NULL; }
        KOCreateJavaVM create = (KOCreateJavaVM)dlsym(h, "JNI_CreateJavaVM");
        if (!create) { KOFinish(l, -1, @"JNI_CreateJavaVM not found"); return NULL; }

        NSUInteger n = l.options.count;
        JavaVMOption *opts = calloc(n, sizeof(JavaVMOption));
        NSMutableArray *keep = [NSMutableArray array];
        for (NSUInteger i = 0; i < n; i++) {
            NSData *d = [[l.options[i] stringByAppendingString:@"\0"] dataUsingEncoding:NSUTF8StringEncoding];
            [keep addObject:d];
            opts[i].optionString = (char *)d.bytes;
            KOLog(@"java: option %@", l.options[i]);
        }
        JavaVMInitArgs vmArgs;
        vmArgs.version = JNI_VERSION_1_8;
        vmArgs.nOptions = (jint)n;
        vmArgs.options = opts;
        vmArgs.ignoreUnrecognized = JNI_FALSE;
        JavaVM *vm = NULL;
        JNIEnv *env = NULL;
        CFTimeInterval t0 = CFAbsoluteTimeGetCurrent();
        jint rc = create(&vm, (void **)&env, &vmArgs);
        free(opts);
        if (rc != JNI_OK) { KOFinish(l, -1, [NSString stringWithFormat:@"JNI_CreateJavaVM failed: %d", rc]); return NULL; }
        KOLog(@"java: VM started in %.0f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000);

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
    if (g_started) {
        if (done) done(-1, L(@"Java has already run since the app was opened: close the app and open it again."));
        return;
    }
    g_started = YES;
    NSString *jre = [self runtimePath];
    KOJavaLaunch *l = [[KOJavaLaunch alloc] init];
    l.libjvm = [jre stringByAppendingPathComponent:@"lib/client/libjvm.dylib"];
    l.mainClass = mainClass;
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
    }
    pthread_attr_destroy(&attr);
}

@end
