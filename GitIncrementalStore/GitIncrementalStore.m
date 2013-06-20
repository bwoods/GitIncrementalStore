//
//

#import "GitIncrementalStore.h"
#import "git2.h"


@interface GitIncrementalStore ( )

@property (assign, nonatomic) git_signature empty_signature;
@property (assign, nonatomic) git_repository * repository;

@end


@implementation GitIncrementalStore

+ (NSString *) type
{
	return @"GitIncrementalStore"; // not GitIncrementalStoreType because the ‘Type’ suffix gets removed by Core Data anyway…
}


#pragma mark - NSIncrementalStore methods

- (BOOL) loadMetadata:(NSError **)error
{
	return YES; // the actual loading is done in -[metadata]
}


#pragma mark - NSPersistentStore methods

static NSString * NSPersistentStoreMetadataFilename = @"incremental-store.json";

- (void) setMetadata:(NSDictionary *)metadata
{
	NSURL * url = [self.URL URLByAppendingPathComponent:NSPersistentStoreMetadataFilename];
	NSData * data = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:nil];

	[data writeToURL:url atomically:YES];
	[[NSFileManager defaultManager] setAttributes:@{ NSFileExtensionHidden : @YES } ofItemAtPath:url.path error:nil];
}

- (NSDictionary *) metadata
{
	NSURL * url = [self.URL URLByAppendingPathComponent:NSPersistentStoreMetadataFilename];
	NSData * data = [[NSData alloc] initWithContentsOfURL:url];
	if (data != nil)
		return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

	// make an initial commit for this empty repository
	git_treebuilder * empty;
	git_treebuilder_create(&empty, nil);

	git_oid oid;
	git_treebuilder_write(&oid, self.repository, empty);
	git_treebuilder_free(empty);

	git_tree * tree;
	git_tree_lookup(&tree, self.repository, &oid);

	git_signature * initial;
	git_signature_now(&initial, self.empty_signature.name, self.empty_signature.email);
	git_commit_create(&oid, self.repository, "HEAD", initial, initial, nil, "Repository created.", tree, 0, nil);
	git_signature_free(initial);
	git_tree_free(tree);

	// return the required metadata
	CFUUIDRef uuid = CFUUIDCreate(nil);
	NSString * string = CFBridgingRelease(CFUUIDCreateString(nil, uuid));
	CFRelease(uuid);

	return @{
		NSStoreTypeKey : self.class.type,
		NSStoreUUIDKey : string.lowercaseString,
	};
}

- (id) initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator configurationName:(NSString *)name URL:(NSURL *)url options:(NSDictionary *)options
{
	self = [super initWithPersistentStoreCoordinator:coordinator configurationName:name URL:url options:options];
	self.empty_signature = (git_signature) {
		(char *) [[NSBundle mainBundle].infoDictionary[@"CFBundleName"] UTF8String],
		(char *) [[NSBundle mainBundle].infoDictionary[@"CFBundleIdentifier"] UTF8String],
	};

	if (git_repository_open(&_repository, url.path.fileSystemRepresentation) != GIT_OK && git_repository_init(&_repository, url.path.fileSystemRepresentation, /* bare ? */ YES) != GIT_OK)
		return nil;

	[[NSFileManager defaultManager] setAttributes:@{
		NSFileProtectionKey : NSFileProtectionCompleteUnlessOpen,
		NSFileExtensionHidden : @YES
	} ofItemAtPath:url.path error:nil];

	return self;
}


#pragma mark - NSObject methods

- (void) dealloc
{
	git_repository_free(_repository);
}

+ (void) initialize
{
	[NSPersistentStoreCoordinator registerStoreClass:self forStoreType:self.type];
}

@end

