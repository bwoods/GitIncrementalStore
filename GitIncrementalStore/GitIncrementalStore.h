//
//

#import <CoreData/CoreData.h>


@interface GitIncrementalStore : NSIncrementalStore

// Use JSON to store the NSManagedObjects rather than MsgPack; NSValueTransformers will need to be used for types that cannot be stored in JSON natively (such as NSData and NSDate)
@property (assign, nonatomic) BOOL useJSON;

+ (NSString *) type;

@end


@interface GitCommitChangesRequest : NSSaveChangesRequest

@property (copy, nonatomic) NSString * message, * author, * email;

@end


@interface NSManagedObjectID (GitIncrementalStore)

- (NSString *) keyPathRepresentation;

@end

