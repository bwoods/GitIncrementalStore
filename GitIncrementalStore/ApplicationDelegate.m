//
//

#import "ApplicationDelegate.h"
#import "git2.h"

@implementation ApplicationDelegate

- (BOOL) application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
	git_threads_init();

	return YES;
}

- (void) applicationWillTerminate:(UIApplication *)application
{
	git_threads_shutdown();
}

@end

