//
//

#import <XCTest/XCTest.h>


@interface GitIncrementalStoreTests : XCTestCase

@property (strong, nonatomic) NSManagedObjectContext * managedObjectContext;
@property (strong, nonatomic) NSURL * url;

@end


#import "GitIncrementalStore.h"

@implementation GitIncrementalStoreTests

- (void) setUp
{
	// Put each test in it’s own repository
	self.url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSStringFromSelector(self.selector)];
	[[NSFileManager defaultManager] removeItemAtURL:self.url error:nil];

	NSManagedObjectModel * model = [NSManagedObjectModel mergedModelFromBundles:@[ [NSBundle bundleForClass:self.class] ]];
	NSPersistentStoreCoordinator * persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];

	NSError * error = nil;
	[persistentStoreCoordinator addPersistentStoreWithType:GitIncrementalStore.type configuration:nil URL:self.url options:nil error:&error];
	XCTAssertNil(error, @"Couldn’t create the GitIncrementalStore: %@", error.localizedDescription);

	self.managedObjectContext = [[NSManagedObjectContext alloc] init];
	[self.managedObjectContext setPersistentStoreCoordinator:persistentStoreCoordinator];
	XCTAssertNotNil(self.managedObjectContext, @"NSManagedObjectContext not created.");
}

- (void) tearDown
{
	self.managedObjectContext = nil;
	self.url = nil;
}


#pragma mark -

- (void) testManagedObjectKeyPathRepresentation
{
	NSManagedObject * object = [NSEntityDescription insertNewObjectForEntityForName:@"ExampleEntity" inManagedObjectContext:self.managedObjectContext];

	// check that the base objectID.URIRepresentation is what we expect
	XCTAssertTrue([object.objectID.URIRepresentation.path characterAtIndex:0] == '/', @"%@", object.objectID.URIRepresentation.path);
	XCTAssertTrue([object.objectID.URIRepresentation.path characterAtIndex:object.entity.name.length+1] == '/', @"%@", object.objectID.URIRepresentation.path);
	XCTAssertTrue([object.objectID.URIRepresentation.path characterAtIndex:object.entity.name.length+2] == 't', @"%@", object.objectID.URIRepresentation.path);

	// check that the slashes are where they should be
	NSString * path = object.objectID.keyPathRepresentation;
	XCTAssertTrue([path characterAtIndex:0] != '/', @"But the resulting path was %@.", path);
	XCTAssertTrue([path characterAtIndex:object.entity.name.length] == '/', @"But the resulting path was %@.", path);

	// both the temporary and permanent id markers should be missing
	XCTAssertTrue([path characterAtIndex:object.entity.name.length+1] != 'p', @"But the resulting path was %@.", path);
	XCTAssertTrue([path characterAtIndex:object.entity.name.length+1] != 't', @"But the resulting path was %@.", path);
}

- (void) testIncrementalStoreFindObjectIDForEntity
{
	NSManagedObject * object = [NSEntityDescription insertNewObjectForEntityForName:@"ExampleEntity" inManagedObjectContext:self.managedObjectContext];

	GitIncrementalStore * store = (id) [self.managedObjectContext.persistentStoreCoordinator persistentStoreForURL:self.url];
	XCTAssertNotNil(store, @"GitIncrementalStore not created.");
	XCTAssertThrows([store referenceObjectForObjectID:object.objectID], @"An unsaved object was found?");

	NSError * error = nil;
	[self.managedObjectContext save:&error];
	XCTAssertNil(error, @"Couldn’t save the managedObjectContext: %@", error.localizedDescription);
	XCTAssertNotNil([store referenceObjectForObjectID:object.objectID], @"A saved object was not found?");
}


#pragma mark -

- (void) testIncrementalStorePropertySerialization
{
	NSNumber * value = @( arc4random() );

	NSManagedObject * object = [NSEntityDescription insertNewObjectForEntityForName:@"ExampleEntity" inManagedObjectContext:self.managedObjectContext];
	[object setValue:value forKey:@"number"];

	NSError * error = nil;
	[self.managedObjectContext save:&error];
	XCTAssertNil(error, @"Couldn’t save the managedObjectContext: %@", error.localizedDescription);
	[object.managedObjectContext refreshObject:object mergeChanges:NO];

	NSFetchRequest * request = [[NSFetchRequest alloc] initWithEntityName:object.entity.name];
	request.predicate = [NSPredicate predicateWithFormat:@"objectID == %@", object.objectID];
	object = nil;

	NSArray * results = [self.managedObjectContext executeFetchRequest:request error:&error];
	XCTAssertNil(error, @"Couldn’t fetch object from the managedObjectContext: %@", error.localizedDescription);
	XCTAssertTrue(results.count == 1, @"No results were returned? %@", results);

	XCTAssertEqualObjects([results.lastObject valueForKey:@"number"], value, @"Object didn’t deserialize properly: %@", results.lastObject);
	XCTAssertNotNil([results.lastObject valueForKey:@"text"], @"Default values are not properly restored: %@", results.lastObject);
}

@end

