#import <Foundation/Foundation.h>

// What the device allows a Java VM: code generated at run time (the JIT), recovering from a fault in it (the VM's
// null checks and safepoints), address space, memory, OpenGL ES, CPU speed. Every finding is a line, also logged
// ("[Kostka] probe ..."); a test that gets the app killed (too much memory, JIT refused) leaves its last line in
// the log.
@interface KOProbe : NSObject

+ (NSArray *)testNames;   // info, jit, jitwx, vm, mem, gl, cpu
// `output` is called on the main thread, `done` when the test has finished
+ (void)run:(NSString *)test output:(void (^)(NSString *line))output done:(void (^)(void))done;

@end
