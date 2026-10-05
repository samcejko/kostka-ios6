#import "KOProbe.h"
#import "KOCommon.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <mach/mach.h>
#include <libkern/OSCacheControl.h>
#include <signal.h>
#include <errno.h>

typedef void (^KOOut)(NSString *line);

#pragma mark - Device

static NSString *KOSysctl(const char *name)
{
    char buf[128] = { 0 };
    size_t len = sizeof buf - 1;
    if (sysctlbyname(name, buf, &len, NULL, 0) != 0) return @"?";
    return [NSString stringWithUTF8String:buf] ?: @"?";
}

static double KOResidentMB(void)
{
    struct task_basic_info info;
    mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return info.resident_size / 1048576.0;
}

static void KOInfo(KOOut out)
{
    UIDevice *d = [UIDevice currentDevice];
    out([NSString stringWithFormat:@"device %@, iOS %@, %lu cores, %.0f MB RAM", KOSysctl("hw.machine"), d.systemVersion,
         (unsigned long)[NSProcessInfo processInfo].processorCount, [NSProcessInfo processInfo].physicalMemory / 1048576.0]);
    vm_size_t page = 0;
    host_page_size(mach_host_self(), &page);
    vm_statistics_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
    if (host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&vm, &count) == KERN_SUCCESS) {
        double mb = page / 1048576.0;
        out([NSString stringWithFormat:@"memory now: free %.0f MB, active %.0f, inactive %.0f, wired %.0f (page %lu)",
             vm.free_count * mb, vm.active_count * mb, vm.inactive_count * mb, vm.wire_count * mb, (unsigned long)page]);
    }
    out([NSString stringWithFormat:@"this app: resident %.0f MB, home %@", KOResidentMB(), NSHomeDirectory()]);
    struct rlimit rl;
    if (getrlimit(RLIMIT_STACK, &rl) == 0) out([NSString stringWithFormat:@"stack limit %llu KB", (unsigned long long)rl.rlim_cur / 1024]);
    NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
    out([NSString stringWithFormat:@"free storage %.0f MB", [fs[NSFileSystemFreeSize] doubleValue] / 1048576.0]);
    out([NSString stringWithFormat:@"bundle %@", [NSBundle mainBundle].bundlePath]);
}

#pragma mark - Generated code

static volatile uintptr_t g_faultAddress;
static volatile int g_faultsCaught;

// What the Java VM does on a fault in its own code: look at the address, change the registers, carry on
static void KOFaultHandler(int sig, siginfo_t *info, void *context)
{
    ucontext_t *uc = (ucontext_t *)context;
    if ((uintptr_t)info->si_addr != g_faultAddress) {
        signal(sig, SIG_DFL);   // (not ours: the fault happens again and is a crash)
        return;
    }
    g_faultsCaught++;
    uint32_t lr = uc->uc_mcontext->__ss.__lr;
    uc->uc_mcontext->__ss.__r[0] = 99;
    uc->uc_mcontext->__ss.__pc = lr & ~1u;
    if (lr & 1) uc->uc_mcontext->__ss.__cpsr |= 0x20; else uc->uc_mcontext->__ss.__cpsr &= ~0x20u;
}

static void KOJit(BOOL writeThenExecute, KOOut out)
{
    size_t len = 16384;
    int prot = writeThenExecute ? (PROT_READ | PROT_WRITE) : (PROT_READ | PROT_WRITE | PROT_EXEC);
    uint32_t *code = mmap(NULL, len, prot, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (code == MAP_FAILED) {
        out([NSString stringWithFormat:@"jit: mmap(%@) failed: %s", writeThenExecute ? @"RW" : @"RWX", strerror(errno)]);
        return;
    }
    out([NSString stringWithFormat:@"jit: mmap(%@) ok at %p", writeThenExecute ? @"RW" : @"RWX", code]);
    code[0] = 0xe3a0002a;   // mov r0, #42
    code[1] = 0xe12fff1e;   // bx lr
    if (writeThenExecute && mprotect(code, len, PROT_READ | PROT_EXEC) != 0) {
        out([NSString stringWithFormat:@"jit: mprotect(RX) failed: %s", strerror(errno)]);
        munmap(code, len);
        return;
    }
    sys_icache_invalidate(code, 8);
    KOLog(@"probe jit: running generated code now (if the app dies here, the kernel refused it)");
    int first = ((int (*)(void))code)();
    // (a JIT patches its code after it has run)
    if (writeThenExecute && mprotect(code, len, PROT_READ | PROT_WRITE) != 0) {
        out([NSString stringWithFormat:@"jit: ran (%d), but mprotect(RW) back failed: %s", first, strerror(errno)]);
        munmap(code, len);
        return;
    }
    code[0] = 0xe3a00007;   // mov r0, #7
    if (writeThenExecute) mprotect(code, len, PROT_READ | PROT_EXEC);
    sys_icache_invalidate(code, 8);
    int patched = ((int (*)(void))code)();
    out([NSString stringWithFormat:@"jit: generated code ran: %d, after patching: %d %@", first, patched,
         (first == 42 && patched == 7) ? @"OK" : @"WRONG"]);

    // A load from a guarded page in generated code, the fault taken over by a signal handler
    void *guard = mmap(NULL, 4096, PROT_NONE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (writeThenExecute) mprotect(code, len, PROT_READ | PROT_WRITE);
    code[0] = 0xe5900000;   // ldr r0, [r0]
    code[1] = 0xe12fff1e;   // bx lr
    if (writeThenExecute) mprotect(code, len, PROT_READ | PROT_EXEC);
    sys_icache_invalidate(code, 8);
    struct sigaction sa, oldSegv, oldBus;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = KOFaultHandler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, &oldSegv);
    sigaction(SIGBUS, &sa, &oldBus);
    g_faultAddress = (uintptr_t)guard;
    g_faultsCaught = 0;
    KOLog(@"probe jit: faulting on purpose in generated code (if the app dies here, faults cannot be handled)");
    int recovered = ((int (*)(uintptr_t))code)((uintptr_t)guard);
    sigaction(SIGSEGV, &oldSegv, NULL);
    sigaction(SIGBUS, &oldBus, NULL);
    out([NSString stringWithFormat:@"jit: fault in generated code handled: returned %d, %d fault(s) %@", recovered, g_faultsCaught,
         (recovered == 99 && g_faultsCaught == 1) ? @"OK" : @"WRONG"]);
    munmap(guard, 4096);
    munmap(code, len);
}

#pragma mark - Address space and memory

static void KOAddressSpace(KOOut out)
{
    size_t best = 0;
    for (size_t mb = 128; mb <= 3072; mb += 128) {
        void *p = mmap(NULL, mb << 20, PROT_NONE, MAP_ANON | MAP_PRIVATE, -1, 0);
        if (p == MAP_FAILED) break;
        best = mb;
        munmap(p, mb << 20);
    }
    out([NSString stringWithFormat:@"vm: largest single reservation %lu MB", (unsigned long)best]);
    // (the Java heap is reserved whole, then committed as it grows)
    size_t reserve = 512u << 20, commit = 64u << 20;
    char *p = mmap(NULL, reserve, PROT_NONE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (p == MAP_FAILED) { out(@"vm: reserving 512 MB failed"); return; }
    if (mprotect(p, commit, PROT_READ | PROT_WRITE) != 0) {
        out([NSString stringWithFormat:@"vm: committing in a reservation failed: %s", strerror(errno)]);
    } else {
        memset(p, 1, commit);
        out([NSString stringWithFormat:@"vm: 64 MB committed inside a 512 MB reservation, resident %.0f MB", KOResidentMB()]);
    }
    munmap(p, reserve);
}

static void KOMemory(KOOut out)
{
    enum { kStepMB = 8, kMaxSteps = 112 };   // up to 896 MB
    void *chunks[kMaxSteps];
    int n = 0;
    for (; n < kMaxSteps; n++) {
        void *b = mmap(NULL, kStepMB << 20, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        if (b == MAP_FAILED) { out([NSString stringWithFormat:@"mem: mmap failed after %d MB", n * kStepMB]); break; }
        memset(b, n + 1, kStepMB << 20);
        chunks[n] = b;
        KOLog(@"probe mem: %d MB touched, resident %.0f MB", (n + 1) * kStepMB, KOResidentMB());
        usleep(40000);
    }
    out([NSString stringWithFormat:@"mem: survived %d MB", n * kStepMB]);
    for (int i = 0; i < n; i++) munmap(chunks[i], kStepMB << 20);
}

#pragma mark - OpenGL ES

static NSString *KOGLString(GLenum e)
{
    const GLubyte *s = glGetString(e);
    return s ? [NSString stringWithUTF8String:(const char *)s] : @"?";
}

static void KOGL(KOOut out)
{
    EAGLContext *ctx = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!ctx || ![EAGLContext setCurrentContext:ctx]) { out(@"gl: no OpenGL ES 2.0 context"); return; }
    out([NSString stringWithFormat:@"gl: %@ | %@ | %@ | GLSL %@", KOGLString(GL_VENDOR), KOGLString(GL_RENDERER),
         KOGLString(GL_VERSION), KOGLString(GL_SHADING_LANGUAGE_VERSION)]);
    struct { GLenum e; const char *name; } ints[] = {
        { GL_MAX_TEXTURE_SIZE, "max texture" }, { GL_MAX_RENDERBUFFER_SIZE, "max renderbuffer" },
        { GL_MAX_VERTEX_ATTRIBS, "vertex attribs" }, { GL_MAX_VERTEX_UNIFORM_VECTORS, "vertex uniforms" },
        { GL_MAX_FRAGMENT_UNIFORM_VECTORS, "fragment uniforms" }, { GL_MAX_VARYING_VECTORS, "varyings" },
        { GL_MAX_TEXTURE_IMAGE_UNITS, "texture units" }, { GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS, "vertex texture units" },
    };
    NSMutableArray *parts = [NSMutableArray array];
    for (unsigned i = 0; i < sizeof ints / sizeof ints[0]; i++) {
        GLint v = -1;
        glGetIntegerv(ints[i].e, &v);
        [parts addObject:[NSString stringWithFormat:@"%s %d", ints[i].name, v]];
    }
    out([@"gl: " stringByAppendingString:[parts componentsJoinedByString:@", "]]);
    NSArray *ext = [[KOGLString(GL_EXTENSIONS) componentsSeparatedByString:@" "] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    for (NSUInteger i = 0; i < ext.count; i += 6) {
        out([@"gl ext: " stringByAppendingString:[[ext subarrayWithRange:NSMakeRange(i, MIN(6, ext.count - i))] componentsJoinedByString:@" "]]);
    }
    [EAGLContext setCurrentContext:nil];
}

#pragma mark - CPU

static volatile uint32_t g_sink;
static volatile double g_dsink;

static void KOCPU(KOOut out)
{
    CFTimeInterval t0 = CACurrentMediaTime();
    uint32_t x = 1;
    for (int i = 0; i < 50000000; i++) x = x * 1664525u + 1013904223u;
    g_sink = x;
    CFTimeInterval t1 = CACurrentMediaTime();
    double a = 1.0;
    for (int i = 0; i < 20000000; i++) a = a * 1.0000001 + 1e-7;
    g_dsink = a;
    CFTimeInterval t2 = CACurrentMediaTime();
    size_t size = 16u << 20;
    char *src = malloc(size), *dst = malloc(size);
    memset(src, 3, size);
    memset(dst, 4, size);
    CFTimeInterval t3 = CACurrentMediaTime();
    for (int i = 0; i < 8; i++) memcpy(dst, src, size);
    CFTimeInterval t4 = CACurrentMediaTime();
    g_sink = dst[size / 2];
    free(src);
    free(dst);
    out([NSString stringWithFormat:@"cpu: 50M integer steps %.0f ms, 20M double steps %.0f ms, memcpy %.0f MB/s",
         (t1 - t0) * 1000, (t2 - t1) * 1000, 128.0 / (t4 - t3)]);
}

#pragma mark -

@implementation KOProbe

+ (NSArray *)testNames
{
    return @[ @"info", @"jit", @"jitwx", @"vm", @"mem", @"gl", @"cpu" ];
}

+ (void)run:(NSString *)test output:(void (^)(NSString *))output done:(void (^)(void))done
{
    KOOut out = ^(NSString *line) {
        KOLog(@"probe %@", line);
        dispatch_async(dispatch_get_main_queue(), ^{ output(line); });
    };
    void (^finish)(void) = ^{ dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(); }); };
    // (OpenGL and UIKit on the main thread; the long ones in the background, so the screen keeps showing them)
    if ([test isEqualToString:@"gl"]) { KOGL(out); finish(); return; }
    if ([test isEqualToString:@"info"]) { KOInfo(out); finish(); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            if ([test isEqualToString:@"jit"]) KOJit(NO, out);
            else if ([test isEqualToString:@"jitwx"]) KOJit(YES, out);
            else if ([test isEqualToString:@"vm"]) KOAddressSpace(out);
            else if ([test isEqualToString:@"mem"]) KOMemory(out);
            else if ([test isEqualToString:@"cpu"]) KOCPU(out);
            else out([NSString stringWithFormat:@"unknown test %@", test]);
            finish();
        }
    });
}

@end
