//
//

#import "GitIncrementalStore.h"
#import "git2.h"


@interface GitIncrementalStore ( )

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

	if (git_repository_open(&_repository, url.path.fileSystemRepresentation) != GIT_OK
			&& git_repository_init(&_repository, url.path.fileSystemRepresentation, /* bare ? */ YES) != GIT_OK)
		return nil;

	[[NSFileManager defaultManager] setAttributes:@{ NSFileExtensionHidden : @YES } ofItemAtPath:url.path error:nil];
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

