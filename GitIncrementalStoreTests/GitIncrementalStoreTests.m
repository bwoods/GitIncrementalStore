//
//

#import <XCTest/XCTest.h>


@interface GitIncrementalStoreTests : XCTestCase

@property (strong, nonatomic) NSManagedObjectContext * managedObjectContext;
@property (strong, nonatomic) NSURL * URL;

@end


#import "GitIncrementalStore.h"

@implementation GitIncrementalStoreTests

- (void) testLoadingMetaData
{
	GitIncrementalStore * store = [[GitIncrementalStore alloc] initWithPersistentStoreCoordinator:self.managedObjectContext.persistentStoreCoordinator configurationName:nil URL:self.URL options:nil];

	NSError * error = nil;
	[store loadMetadata:&error];
	XCTAssertNil(error, @"-[loadMetadata] failed: %@", error.localizedFailureReason);
	XCTAssertEqualObjects(GitIncrementalStore.type, store.metadata[NSStoreTypeKey], @"Store metadata type was munged?");
}


#pragma mark -

- (void) setUp
{
	self.URL = [NSURL URLWithString:@"unittests.git" relativeToURL:[NSURL fileURLWithPath:NSTemporaryDirectory()]];
	[[NSFileManager defaultManager] removeItemAtURL:self.URL error:nil];

    NSManagedObjectModel * model = [NSManagedObjectModel mergedModelFromBundles:nil];
    NSPersistentStoreCoordinator * persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	[persistentStoreCoordinator addPersistentStoreWithType:GitIncrementalStore.type configuration:nil URL:self.URL options:nil error:nil];

	self.managedObjectContext = [[NSManagedObjectContext alloc] init];
	[self.managedObjectContext setPersistentStoreCoordinator:persistentStoreCoordinator];
	XCTAssertNotNil(self.managedObjectContext, @"NSManagedObjectContext not created.");
}

- (void) tearDown
{
	self.managedObjectContext = nil;
	self.URL = nil;
}

@end

