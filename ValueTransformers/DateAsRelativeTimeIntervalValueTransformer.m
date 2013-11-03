//
//

#import "DateAsRelativeTimeIntervalValueTransformer.h"


@implementation DateAsRelativeTimeIntervalValueTransformer

+ (void) load
{
	[NSValueTransformer setValueTransformer:[[DateAsRelativeTimeIntervalValueTransformer alloc] init] forName:NSStringFromClass(self)];
}

+ (Class) transformedValueClass
{
	return [NSNumber class];
}

- (NSNumber *) transformedValue:(NSDate *)date
{
	return @( date.timeIntervalSinceReferenceDate );
}

+ (BOOL) allowsReverseTransformation
{
	return YES;
}

- (NSDate *) reverseTransformedValue:(NSNumber *)number
{
	return [[NSDate alloc] initWithTimeIntervalSinceNow:number.doubleValue];
}

@end

