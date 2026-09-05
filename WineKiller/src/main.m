#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Kill Wine processes
    [self killWineProcesses];
    
    // Quit immediately after killing
    [NSApp terminate:nil];
}

- (void)killWineProcesses {
    NSLog(@"🔪 Killing Wine processes...");
    
    // Get current username
    NSString *username = NSUserName();
    
    // Build the kill command
    NSString *killCommand = [NSString stringWithFormat:
        @"pkill -9 -U %@ wineserver wine wine64 wine-preloader wine64-preloader 2>/dev/null; "
        @"pgrep -U %@ -f \".exe\" | xargs kill -9 2>/dev/null",
        username, username];
    
    // Run the command
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", killCommand];
    
    // Capture output
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    
    NSFileHandle *fileHandle = [pipe fileHandleForReading];
    
    [task launch];
    [task waitUntilExit];
    
    // Read output
    NSData *data = [fileHandle readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    if (output.length > 0) {
        NSLog(@"Kill output: %@", output);
    }
    
    // Get exit status
    int status = [task terminationStatus];
    if (status == 0) {
        NSLog(@"✅ Wine processes killed successfully");
    } else {
        NSLog(@"⚠️ No Wine processes found to kill (exit: %d)", status);
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
