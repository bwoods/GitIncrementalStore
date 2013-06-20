//
//

#import <Foundation/Foundation.h>


/**
	This class is designed as a drop in replacement for NSJSONSerialization. But in addition to supporting the valid JSON types,

		“An object that may be converted to JSON must have the following properties:
			• The top level object is an NSArray or NSDictionary.
			• All objects are instances of NSString, NSNumber, NSArray, NSDictionary, or NSNull.
			• All dictionary keys are instances of NSString.
			• Numbers are not NaN or infinity.” — NSJSONSerialization Class Reference

	it can store NSData as well.

*/

@interface MsgPackSerialization : NSJSONSerialization

// NSJSONWritingOptions are ignored. NSJSONWritingPrettyPrinted has no meaning for a binary format
+ (NSData *) dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error;

// NSJSONReadingOptions are ignored. NSJSONReadingMutableContainers is always true.
+ (id) JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error;


// The stream methods still write JSON, rather than MessagePack
+ (id) JSONObjectWithStream:(NSInputStream *)stream options:(NSJSONReadingOptions)opt error:(NSError *__autoreleasing *)error __attribute((deprecated));
+ (NSInteger) writeJSONObject:(id)obj toStream:(NSOutputStream *)stream options:(NSJSONWritingOptions)opt error:(NSError *__autoreleasing *)error __attribute((deprecated));
@end

