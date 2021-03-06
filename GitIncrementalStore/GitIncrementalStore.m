//
//

#import "GitIncrementalStore.h"

#import "MsgPackSerialization.h"
#import "git2.h"

#import "lmdb_transactional_backend.h"
#import "odb.h"


@interface GitIncrementalStore ( )

@property (strong, nonatomic) NSCache * transformerCache;
@property (strong, nonatomic) Class entityPersistanceClass;
@property (assign, nonatomic) git_repository * repository;

@end


static NSString * emptyCommitMessage, * emptyCommitAuthor, * emptyCommitEmail;

@implementation NSSaveChangesRequest (GitCommitChangesRequest)

- (NSString *) message
{
	return emptyCommitMessage;
}

- (NSString *) author
{
	return emptyCommitAuthor;
}

- (NSString *) email
{
	return emptyCommitEmail;
}

@end


@implementation GitCommitChangesRequest

@end


#pragma mark -

@implementation NSManagedObjectID (GitIncrementalStore)

- (NSString *) keyPathRepresentation
{
	NSString * path = self.URIRepresentation.path;
	NSUInteger length = [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

	char buffer[length+1];
	[path getBytes:buffer maxLength:length usedLength:&length encoding:NSUTF8StringEncoding options:0 range:NSMakeRange(0, path.length) remainingRange:0];
	buffer[length] = '\0';

	// /EntityName/… → EntityName/…
	size_t n = self.entity.name.length;
	for (int i = 0; i <= n; ++i)
		buffer[i] = buffer[i+1];

	// pb9b3f2e8-2d26-4377-8388-e786c18d0be6 → b9b3f2e8-2d26-4377-8388-e786c18d0be6
	for (int i = 1; i < 50; ++i)
		buffer[n+i] = buffer[n+i+2];

	// EntityName/b9b3f2e8-2d26-4377-8388-e786c18d0be6
	return [[NSString alloc] initWithBytes:buffer length:length - 2 encoding:NSASCIIStringEncoding];
}

@end


@implementation GitIncrementalStore

- (void) setUseJSON:(BOOL)useJSON
{
	self.entityPersistanceClass = useJSON ? [NSJSONSerialization class] : [MsgPackSerialization class];
}

+ (NSString *) type
{
	return @"GitIncrementalStore"; // not GitIncrementalStoreType because the ‘Type’ suffix gets removed by Core Data anyway…
}

static inline void throw_if_error(int status)
{
	if (status != GIT_OK)
		@throw [NSException exceptionWithName:@"LibGit₂" reason:[[NSString alloc] initWithFormat:@"%s", giterr_last() ? giterr_last()->message : ""] userInfo:nil];
}


#pragma mark -

- (NSArray *) saveRequest:(NSSaveChangesRequest *)saveRequest withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error
{
	git_reference * reference, * symbolic;
	throw_if_error(git_reference_lookup(&symbolic, self.repository, "HEAD"));
	throw_if_error(git_reference_resolve(&reference, symbolic));
	git_reference_free(symbolic);
	
	git_commit * commit;
	throw_if_error(git_commit_lookup(&commit, self.repository, git_reference_target(reference)));
	git_reference_free(reference);

	git_index * index;
	throw_if_error(git_repository_index(&index, self.repository));

	// writes are done within a transaction
	throw_if_error(git_odb_transaction_begin(self.repository));

	void (^updateIndex)(NSManagedObject *, BOOL *) = ^(NSManagedObject * object, BOOL * stop) {
		@autoreleasepool {
			NSMutableDictionary * dictionary = [[NSMutableDictionary alloc] init];
			[object.entity.attributesByName enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSAttributeDescription * property, BOOL * stop) {
				if (property.isTransient == YES)
					return;

				id value = [object valueForKey:key];
				if (property.attributeType != NSTransformableAttributeType) {
					if (value != nil && [property.defaultValue isEqual:value] == NO)
						dictionary[key] = [object valueForKey:key];
				}
				else
				{
					NSValueTransformer * transformer = [self.transformerCache objectForKey:property.valueTransformerName];
					if (transformer == nil) {
						transformer = [[NSClassFromString(property.valueTransformerName) alloc] init];
						[self.transformerCache setObject:transformer forKey:property.valueTransformerName];
					}

					dictionary[key] = [transformer transformedValue:value];
				}
			}];

			[object.entity.relationshipsByName enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSRelationshipDescription * property, BOOL * stop) {
				if (property.isTransient == YES)
					return;
				if (property.isToMany == NO)
					dictionary[key] = [self referenceObjectForObjectID:[[object valueForKey:key] objectID]];
				else {
					NSMutableArray * values = [[NSMutableArray alloc] init];
					for (NSManagedObject * obj in [object valueForKey:key]) // works for NSSet or NSOrderedSet
						[values addObject:[self referenceObjectForObjectID:obj.objectID]];

					if (property.isOrdered == NO)
						[values sortUsingSelector:@selector(compare:)]; // sort for consistency

					dictionary[key] = values;
				}
			}];

			// Note: MsgPackSerialization stores dictionaries sorted by key
			NSData * data = [self.entityPersistanceClass dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:nil];
			
			git_index_entry entry = { .mode = GIT_FILEMODE_BLOB, .path = (char *) object.objectID.keyPathRepresentation.UTF8String };
			throw_if_error(git_blob_create_frombuffer(&entry.oid, self.repository, data.bytes, data.length));
			throw_if_error(git_index_add(index, &entry));
		}
	};

	[saveRequest.insertedObjects enumerateObjectsUsingBlock:updateIndex];
	[saveRequest.updatedObjects enumerateObjectsUsingBlock:updateIndex];

	for (NSManagedObject * object in saveRequest.deletedObjects)
		git_index_remove_bypath(index, object.objectID.keyPathRepresentation.UTF8String);

	// write out the index contents
	git_oid oid;
	throw_if_error(git_index_write_tree(&oid, index));
	throw_if_error(git_index_write(index));
	git_index_free(index);

	git_commit * parent = nil;
	git_commit_parent(&parent, commit, 0);

	// only keep user commits (with messages) and the initial repository creation save; over-write “just” saves
	if (parent == nil || strcmp(git_commit_committer(commit)->email, emptyCommitEmail.UTF8String) != NSOrderedSame)
		parent = commit;

	git_tree * tree;
	throw_if_error(git_tree_lookup(&tree, self.repository, &oid));

	git_signature * signature;
	throw_if_error(git_signature_now(&signature, saveRequest.author.UTF8String, saveRequest.email.UTF8String));
	throw_if_error(git_commit_create(/* replace tree oid with commit oid */ &oid, self.repository, "HEAD", signature, signature, nil, saveRequest.message.UTF8String, tree, 1, (void *) &parent));
	git_signature_free(signature);

	// write the objects to a git packfile
	git_packbuilder * builder;
	throw_if_error(git_packbuilder_new(&builder, self.repository));
	throw_if_error(git_packbuilder_insert_commit(builder, &oid));
	throw_if_error(git_packbuilder_write(builder, [@( git_repository_path(self.repository) ) stringByAppendingPathComponent:@"objects/pack"].fileSystemRepresentation, nil, nil));
	git_packbuilder_free(builder);

	// now that pack is written, discard all the “loose” objects
	git_odb_transaction_rollback(self.repository);

	return @[ ]; // “If the request is a save request, the method should return an empty array.” — NSIncrementalStore Class Reference
}


static int fetch_request_treewalk_with_block(const char * prefix, const git_tree_entry * entry, void(^block)(const char *, const char *))
{
	if (git_tree_entry_type(entry) == GIT_OBJ_BLOB)
		block(prefix, git_tree_entry_name(entry));

	return GIT_OK;
}

- (id) fetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError  * __autoreleasing *)error
{
	NSMutableArray * managedObjects = [[NSMutableArray alloc] init];

	git_reference * reference, * symbolic;
	throw_if_error(git_reference_lookup(&symbolic, self.repository, "HEAD"));
	throw_if_error(git_reference_resolve(&reference, symbolic));
	git_reference_free(symbolic);
	
	git_commit * commit;
	throw_if_error(git_commit_lookup(&commit, self.repository, git_reference_target(reference)));
	git_reference_free(reference);

	git_tree * root;
	throw_if_error(git_commit_tree(&root, commit));

	void (^collectEntities)(NSString *) = ^(NSString * entityName) {
		git_tree_entry * entry;
		throw_if_error(git_tree_entry_bypath(&entry, root, entityName.UTF8String)); // grab the ‘EntityName’ entry…

		git_tree * tree;
		throw_if_error(git_tree_lookup(&tree, self.repository, git_tree_entry_id(entry))); // …and walk its sub-trees

		git_tree_walk(tree, GIT_TREEWALK_PRE, (git_treewalk_cb) fetch_request_treewalk_with_block, (__bridge void *) ^(const char * prefix, const char * path) {
			NSString * referenceObject = [[NSString alloc] initWithFormat:@"%c%c%c%s", prefix[0], prefix[1], prefix[2], path]; // undo the prefix/hash
			NSManagedObjectID * objectID = [self newObjectIDForEntity:fetchRequest.entity referenceObject:referenceObject];
			NSManagedObject * managedObject = [context objectWithID:objectID];

			if (fetchRequest.predicate == nil || [fetchRequest.predicate evaluateWithObject:managedObject] == YES)
				[managedObjects addObject:managedObject];
		});

		git_tree_entry_free(entry);
	};

	if (fetchRequest.includesSubentities)
		for (NSEntityDescription * entity in fetchRequest.entity.subentities)
			collectEntities(entity.name);
	collectEntities(fetchRequest.entityName);

	if (fetchRequest.sortDescriptors.count != 0)
		[managedObjects sortUsingDescriptors:fetchRequest.sortDescriptors];
	if (fetchRequest.fetchOffset && managedObjects.count)
		[managedObjects removeObjectsInRange:NSMakeRange(0, MIN(fetchRequest.fetchOffset, managedObjects.count))];
	if (fetchRequest.fetchLimit && managedObjects.count > fetchRequest.fetchLimit)
		[managedObjects removeObjectsInRange:NSMakeRange(fetchRequest.fetchLimit, managedObjects.count - fetchRequest.fetchLimit)];

	switch (fetchRequest.resultType)
	{
		case NSManagedObjectResultType:
			return managedObjects;
		case NSCountResultType:
			return @[ @( managedObjects.count ) ];
		case NSManagedObjectIDResultType:
			return [managedObjects valueForKey:@"objectID"]; // FIXME: if we aren’t filtering we needn’t create the objects in the first place; we just throw them away here…
		case NSDictionaryResultType: {
			id dictionaries = [[(fetchRequest.returnsDistinctResults ? [NSMutableSet class] : [NSMutableArray class]) alloc] initWithCapacity:managedObjects.count];
			for (NSManagedObject * managedObject in managedObjects) {
				NSArray * propertyNames = fetchRequest.propertiesToFetch ? [fetchRequest.propertiesToFetch valueForKey:@"name"] : managedObject.entity.attributesByName.allKeys;
				[dictionaries addObject:[managedObject dictionaryWithValuesForKeys:propertyNames]];
			}

			return dictionaries;
		}
	}

	return nil;
}


#pragma mark - NSIncrementalStore methods

- (NSIncrementalStoreNode *) newValuesForObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error
{
	git_reference * reference, * symbolic;
	throw_if_error(git_reference_lookup(&symbolic, self.repository, "HEAD"));
	throw_if_error(git_reference_resolve(&reference, symbolic));
	git_reference_free(symbolic);
	
	git_commit * commit;
	throw_if_error(git_commit_lookup(&commit, self.repository, git_reference_target(reference)));
	git_reference_free(reference);

	git_tree * root;
	throw_if_error(git_commit_tree(&root, commit));

	git_tree_entry * entry;
	throw_if_error(git_tree_entry_bypath(&entry, root, objectID.keyPathRepresentation.UTF8String));

	git_blob * blob;
	git_blob_lookup(&blob, self.repository, git_tree_entry_id(entry));

	NSData * data = [[NSData alloc] initWithBytesNoCopy:(void *)git_blob_rawcontent(blob) length:(NSUInteger)git_blob_rawsize(blob) freeWhenDone:NO];
	NSMutableDictionary * values = [self.entityPersistanceClass JSONObjectWithData:data options:0 error:error];
	git_blob_free(blob);

	[objectID.entity.attributesByName enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSAttributeDescription * property, BOOL * stop) {
		if (property.defaultValue != nil && values[key] == nil)
			values[key] = property.defaultValue;

		// NSValueTransformer’s transformedValue: is most commonly used to used to store non-scalar types in the persistent store, so reverseTransformedValue: is used (if it exists) to restore the original type
		if (property.attributeType == NSTransformableAttributeType)
		{
			NSValueTransformer * transformer = [self.transformerCache objectForKey:property.valueTransformerName];
			if (transformer == nil) {
				transformer = [[NSClassFromString(property.valueTransformerName) alloc] init];
				[self.transformerCache setObject:transformer forKey:property.valueTransformerName];
			}

			if ([transformer.class allowsReverseTransformation])
				values[key] = [transformer reverseTransformedValue:values[key]];
		}
	}];

	return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID withValues:values version:0];
}

- (id) executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError  * __autoreleasing *)error
{
	switch (request.requestType)
	{
		case NSFetchRequestType:
			return [self fetchRequest:(NSFetchRequest *)request withContext:context error:error];
		case NSSaveRequestType:
			return [self saveRequest:(NSSaveChangesRequest *)request withContext:context error:error];
	}

	return nil;
}

- (NSArray *) obtainPermanentIDsForObjects:(NSArray *)objects error:(NSError * __autoreleasing *)error
{
	NSMutableArray * array = [[NSMutableArray alloc] initWithCapacity:objects.count];
	for (NSManagedObject * object in objects)
	{
		CFUUIDRef uuid = CFUUIDCreate(nil);
		NSString * string = CFBridgingRelease(CFUUIDCreateString(nil, uuid));
		CFRelease(uuid);

		[array addObject:[self newObjectIDForEntity:object.entity referenceObject:string.lowercaseString]];
	}

	return array;
}

- (BOOL) loadMetadata:(NSError **)error
{
	return YES; // the actual loading is done in -[metadata]
}


#pragma mark - NSPersistentStore methods

static NSString * NSPersistentStoreMetadataFilename = @"metadata";

- (void) setMetadata:(NSDictionary *)metadata
{
	NSURL * url = [self.URL URLByAppendingPathComponent:NSPersistentStoreMetadataFilename];
	NSData * data = [NSPropertyListSerialization dataFromPropertyList:metadata format:NSPropertyListBinaryFormat_v1_0 errorDescription:nil];
	[data writeToURL:url atomically:YES];
}

- (NSDictionary *) metadata
{
	NSURL * url = [self.URL URLByAppendingPathComponent:NSPersistentStoreMetadataFilename];
	NSData * data = [[NSData alloc] initWithContentsOfURL:url];
	if (data != nil)
		return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:nil error:nil];

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
	self.transformerCache = [[NSCache alloc] init];
	self.useJSON = NO;

	emptyCommitMessage = @"Autosave…";
	emptyCommitAuthor = [NSBundle mainBundle].infoDictionary[@"CFBundleName"];
	emptyCommitEmail =  [NSBundle mainBundle].infoDictionary[@"CFBundleIdentifier"];

	NSString * transactions = @"objects/transactions";
	if (git_repository_open(&_repository, url.path.fileSystemRepresentation) == GIT_OK)
		throw_if_error(git_odb_add_transactional_backend(self.repository, [url.path stringByAppendingPathComponent:transactions].fileSystemRepresentation));
	else
	{
		throw_if_error(git_repository_init(&_repository, url.path.fileSystemRepresentation, /* bare ? */ YES));
		throw_if_error(git_odb_add_transactional_backend(self.repository, [url.path stringByAppendingPathComponent:transactions].fileSystemRepresentation));

		// writes are done within a transaction
		throw_if_error(git_odb_transaction_begin(self.repository));

		// an empty repository is an empty tree…
		git_treebuilder * empty;
		git_treebuilder_create(&empty, nil);

		git_oid oid;
		throw_if_error(git_treebuilder_write(&oid, self.repository, empty));
		git_treebuilder_free(empty);

		git_tree * tree;
		throw_if_error(git_tree_lookup(&tree, self.repository, &oid));

		// …with a corresponding commit
		git_signature * signature;
		throw_if_error(git_signature_now(&signature, emptyCommitAuthor.UTF8String, emptyCommitEmail.UTF8String));
		throw_if_error(git_commit_create(&oid, self.repository, "HEAD", signature, signature, nil, "Repository created.", tree, 0, nil));
		git_signature_free(signature);

		git_packbuilder * builder;
		throw_if_error(git_packbuilder_new(&builder, self.repository));
		throw_if_error(git_packbuilder_insert_commit(builder, &oid));
		throw_if_error(git_packbuilder_write(builder, [@( git_repository_path(self.repository) ) stringByAppendingPathComponent:@"objects/pack"].fileSystemRepresentation, nil, nil));
		git_packbuilder_free(builder);

		// now that the pack is written, discard all the “loose” objects
		git_odb_transaction_rollback(self.repository);

		// no need for the default hooks folder
		[[NSFileManager defaultManager] removeItemAtPath:[@( git_repository_path(self.repository) ) stringByAppendingPathComponent:@"hooks"] error:nil];

		[[NSFileManager defaultManager] setAttributes:@{
			NSFileExtensionHidden : @YES
		} ofItemAtPath:url.path error:nil];
	}

	return self;
}


#pragma mark - NSObject methods

- (void) dealloc
{
	git_repository_free(self.repository);
}

+ (void) load
{
	[NSPersistentStoreCoordinator registerStoreClass:self forStoreType:self.type];
}

@end


