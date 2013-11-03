//
//

#import "Base64ValueTransformer.h"


@implementation Base64ValueTransformer

+ (void) load
{
	[NSValueTransformer setValueTransformer:[[Base64ValueTransformer alloc] init] forName:NSStringFromClass(self)];
}

+ (Class) transformedValueClass
{
	return [NSString class];
}

- (NSString *) transformedValue:(NSData *)data
{
	return [data base64EncodedStringWithOptions:0];
}

+ (BOOL) allowsReverseTransformation
{
	return YES;
}

- (NSData *) reverseTransformedValue:(NSString *)string
{
	return [[NSData alloc] initWithBase64EncodedString:string options:0];
}

@end

