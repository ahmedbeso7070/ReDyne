#import "AppDelegate.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Register for memory warnings
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
    return YES;
}

- (void)handleMemoryWarning:(NSNotification *)notification {
    // Clear URL caches
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    // Clear temporary files
    NSString *tmpDir = NSTemporaryDirectory();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *tmpFiles = [fm contentsOfDirectoryAtPath:tmpDir error:nil];
    for (NSString *file in tmpFiles) {
        NSString *path = [tmpDir stringByAppendingPathComponent:file];
        [fm removeItemAtPath:path error:nil];
    }
}

#pragma mark - UISceneSession Lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
}

@end

