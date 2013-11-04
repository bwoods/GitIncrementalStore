# GitIncrementalStore

An NSIncrementalStore subclass that stores its data in a git repository. 

## API

For now, just a quick example extracted from the Unit Tests.

```objc
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
```

More documentation will come…


## License (MIT)

Copyright (c) 2013 Bryan Woods

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

