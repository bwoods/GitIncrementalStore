//
//

#import <CoreData/CoreData.h>


@interface GitIncrementalStore : NSIncrementalStore

+ (NSString *) type;

@end


@interface NSManagedObjectID (GitIncrementalStore)

- (NSString *) keyPathRepresentation;

@end

