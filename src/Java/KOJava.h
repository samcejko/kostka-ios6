#import <Foundation/Foundation.h>

// The Java VM in the app: HotSpot (the client VM of OpenJDK 8, ported to iOS) loaded from the bundle's jre folder
// (jre/lib/client/libjvm.dylib), started on a thread of its own with a large stack. What Java prints (System.out,
// System.err, the VM's own messages) goes to Documents/java.log and, line by line, to the log ("[Kostka] java: ...").
// One VM per process: a second start is refused (HotSpot cannot be started twice).
@interface KOJava : NSObject

+ (NSString *)runtimePath;    // the jre folder: in the app bundle, or a downloaded one in Documents
+ (NSString *)logPath;

// Starts the VM with `options` ("-Xmx96m", "-Dfoo=bar") and the class path, then runs `mainClass`.main(args).
// `done` is called on the main thread with the exit code (0 when main returned, else a message in `error`).
+ (void)runMainClass:(NSString *)mainClass
           classPath:(NSArray *)classPath
             options:(NSArray *)options
                args:(NSArray *)args
                done:(void (^)(int exitCode, NSString *error))done;

@end
