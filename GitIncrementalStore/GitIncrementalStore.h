//
//

#import <CoreData/CoreData.h>


@interface GitIncrementalStore : NSIncrementalStore

+ (NSString *) type;

@end


@interface GitCommitChangesRequest : NSSaveChangesRequest

@property (copy, nonatomic) NSString * message, * author, * email;

@end


@interface NSManagedObjectID (GitIncrementalStore)

- (NSString *) keyPathRepresentation;

@end

