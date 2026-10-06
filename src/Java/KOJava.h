#import <Foundation/Foundation.h>

// The Java VM in the app: HotSpot (the client VM of OpenJDK 8, ported to iOS) loaded from the bundle's jre folder
// (jre/lib/client/libjvm.dylib), started on a thread of its own with a large stack. What Java prints (System.out,
// System.err, the VM's own messages) goes to Documents/java.log and, line by line, to the log ("[Kostka] java: ...").
// One VM per process: a second start is refused (HotSpot cannot be started twice).
@interface KOJava : NSObject

+ (NSString *)dataPath;       // Library/Kostka: Kostka's files, and the folder Java works in
+ (NSString *)runtimePath;    // the jre folder: in the app bundle, or a downloaded one in Documents
+ (NSString *)logPath;
+ (int)memoryInUse;           // the app's memory in use (resident), in MB
// (tests: a line into Library/Kostka/run.txt, which each process starts anew - what a run did, for a computer to read
// over SSH; while Java runs, "progress frames= window= memory=" every 2 seconds)
+ (void)note:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

// Starts the VM with `options` ("-Xmx96m", "-Dfoo=bar") and the class path, then runs `mainClass`.main(args).
// `done` is called on the main thread with the exit code (0 when main returned, else a message in `error`).
+ (void)runMainClass:(NSString *)mainClass
           classPath:(NSArray *)classPath
             options:(NSArray *)options
                args:(NSArray *)args
                done:(void (^)(int exitCode, NSString *error))done;

// The same, in a working folder of its own (games keep their files in it; without one: dataPath)
+ (void)runMainClass:(NSString *)mainClass
           classPath:(NSArray *)classPath
             options:(NSArray *)options
                args:(NSArray *)args
    workingDirectory:(NSString *)workingDirectory
                done:(void (^)(int exitCode, NSString *error))done;

@end
