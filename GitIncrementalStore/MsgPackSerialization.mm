//
//

#import "MsgPackSerialization.h"
#import "msgpack.h"


#pragma mark MsgPack template methods

#include <string>

// the MsgPack C-API uses an… interesting implementation of the Template Method Pattern using the C preprocessor.

static inline id template_callback_root(void *) { return nil; }
static inline int template_callback_string_append(std::string * string, const char * buf, unsigned int len) { string->append(buf, len); return 0; }

static inline int template_callback_uint8(void *, uint8_t d, id * o) { *o = [[NSNumber alloc] initWithUnsignedChar:d]; return 0; }
static inline int template_callback_uint16(void *, uint16_t d, id * o) { *o = [[NSNumber alloc] initWithUnsignedShort:d]; return 0; }
static inline int template_callback_uint32(void *, uint32_t d, id * o) { *o = [[NSNumber alloc] initWithUnsignedInt:d]; return 0; }
static inline int template_callback_uint64(void *, uint64_t d, id * o) { *o = [[NSNumber alloc] initWithUnsignedLongLong:d]; return 0; }
static inline int template_callback_int8(void *, int8_t d, id * o) { *o = (__bridge_transfer id) CFNumberCreate(nil, kCFNumberSInt8Type, &d); return 0; }
static inline int template_callback_int16(void *, int16_t d, id * o) { *o = (__bridge_transfer id) CFNumberCreate(nil, kCFNumberSInt16Type, &d); return 0; }
static inline int template_callback_int32(void *, int32_t d, id * o) { *o = (__bridge_transfer id) CFNumberCreate(nil, kCFNumberSInt32Type, &d); return 0; }
static inline int template_callback_int64(void *, int64_t d, id * o) { *o = (__bridge_transfer id) CFNumberCreate(nil, kCFNumberSInt64Type, &d); return 0; }
static inline int template_callback_float(void *, float d, id * o) { *o = (__bridge_transfer id) CFNumberCreate(nil, kCFNumberFloat32Type, &d); return 0; }
static inline int template_callback_double(void *, double d, id * o) { *o = (__bridge_transfer id) CFNumberCreate(nil, kCFNumberFloat64Type, &d); return 0; }
static inline int template_callback_nil(void *, id * o) { *o = [NSNull null]; return 0; }
static inline int template_callback_true(void *, id * o) { *o = (__bridge id) kCFBooleanTrue; return 0; }
static inline int template_callback_false(void *, id * o) { *o = (__bridge id) kCFBooleanFalse; return 0; }

static inline int template_callback_raw(void *, const char * b, const char * p, unsigned int l, id * o)
{
	if (l >= 3 && p[0] == '\xef' && p[1] == '\xbb' && p[2] == '\xbf') // http://en.wikipedia.org/wiki/Byte_order_mark#UTF-8
		*o = (__bridge_transfer id) CFStringCreateWithBytes(nil, (const UInt8 *) p+3, l-3, kCFStringEncodingUTF8, YES);
	else
		*o = (__bridge_transfer id) CFDataCreate(nil, (const UInt8 *) p+3, l-3);

	return 0;
}

static inline int template_callback_array(void *, unsigned int n, __strong id * o)
{
	*o = (__bridge_transfer id) CFArrayCreateMutable(nil, n, &kCFTypeArrayCallBacks);
	return 0;
}

static inline int template_callback_array_item(void * u, const id * c, id o)
{
	CFMutableArrayRef array = (__bridge CFMutableArrayRef) *c;
	CFArrayAppendValue(array, (const void *) o);
	return 0;
}

static inline int template_callback_map(void *, unsigned int n, __strong id * o)
{
	*o = (__bridge_transfer id) CFDictionaryCreateMutable(nil, n, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	return 0;
}

static inline int template_callback_map_item(void *, const id * m, id k, id v)
{
	CFMutableDictionaryRef map = (__bridge CFMutableDictionaryRef) *m;
	CFDictionaryAddValue(map, (const void *) k, (const void *) v);
	return 0;
}

#define msgpack_unpack_struct(name) \
	struct template ## name

#define msgpack_unpack_func(ret, name) \
	ret template ## name

#define msgpack_unpack_callback(name) \
	template_callback ## name

#define msgpack_unpack_object id
#define msgpack_unpack_user void *

// with the above functions definitions and macros in place, these include files implement the actual parsing function, template_execute(), used below

#include "msgpack/unpack_define.h"
#include "msgpack/unpack_template.h"
#include "msgpack.h"


#pragma mark - Double Dispatch methods

@implementation NSNull (MsgPack)
 
- (std::string) msgPack
{
	std::string result;
	msgpack_packer packer = { .data = &result, .callback = (msgpack_packer_write) template_callback_string_append };

	msgpack_pack_nil(&packer);
	return std::move(result);
}
 
@end
 
@implementation NSNumber (MsgPack)
 
- (std::string) msgPack
{
	std::string result;
	int32_t n; int64_t m; float f; double d;
	msgpack_packer packer = { .data = &result, .callback = (msgpack_packer_write) template_callback_string_append };

	CFNumberRef value = (__bridge CFNumberRef) self;
	if (value == (CFNumberRef) kCFBooleanTrue)
		msgpack_pack_true(&packer);
	else if (value == (CFNumberRef) kCFBooleanFalse)
		msgpack_pack_false(&packer);
	else if (CFNumberGetValue(value, kCFNumberSInt32Type, &n))
		msgpack_pack_int32(&packer, n);
	else if (CFNumberGetValue(value, kCFNumberFloat32Type, &f)) // prefer float over 64-bit types whenever possible
		msgpack_pack_float(&packer, f);
	else if (CFNumberGetValue(value, kCFNumberSInt64Type, &m))
		msgpack_pack_int64(&packer, m);
	else if (CFNumberGetValue(value, kCFNumberFloat64Type, &d))
		msgpack_pack_double(&packer, d);
	else
		msgpack_pack_uint64(&packer, self.unsignedLongLongValue); // value > 2⁶³ and CFNumber doesn’t do unsigned…

	return std::move(result);
}
 
@end
 
@implementation NSString (MsgPack)
 
- (std::string) msgPack
{
	std::string result;
	msgpack_packer packer = { .data = &result, .callback = (msgpack_packer_write) template_callback_string_append };

	NSData * data = (__bridge_transfer id) CFStringCreateExternalRepresentation(nil, (__bridge CFStringRef) self, kCFStringEncodingUTF8, 0);

	msgpack_pack_raw(&packer, data.length+3);
	msgpack_pack_raw_body(&packer, "\xef\xbb\xbf", 3); // http://en.wikipedia.org/wiki/Byte_order_mark#UTF-8
	msgpack_pack_raw_body(&packer, data.bytes, data.length);

	return std::move(result);
}
 
@end
 
@implementation NSData (MsgPack)
 
- (std::string) msgPack
{
	std::string result;
	msgpack_packer packer = { .data = &result, .callback = (msgpack_packer_write) template_callback_string_append };

	msgpack_pack_raw(&packer, self.length);
	msgpack_pack_raw_body(&packer, self.bytes, self.length);

	return std::move(result);
}
 
@end
 
@implementation NSArray (MsgPack)
 
- (std::string) msgPack
{
	std::string result;
	msgpack_packer packer = { .data = &result, .callback = (msgpack_packer_write) template_callback_string_append };

	msgpack_pack_array(&packer, self.count);
	for (id value in self)
		result += [value msgPack];

	return std::move(result);
}
 
@end
 
@implementation NSDictionary (MsgPack)
 
- (std::string) msgPack
{
	std::string result;
	msgpack_packer packer = { .data = &result, .callback = (msgpack_packer_write) template_callback_string_append };

	msgpack_pack_map(&packer, self.count);
	for (NSString * key in [self.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		result += [key msgPack];
		result += [self[key] msgPack];
	}

	return std::move(result);
}

@end


#pragma mark -

@implementation MsgPackSerialization

+ (NSData *) dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error
{
	@try {
		std::string buffer = [object msgPack];
		return [[NSData alloc] initWithBytes:buffer.data() length:buffer.size()];
	}
	@catch (NSException * exception) {
		if (error)
			*error = [NSError errorWithDomain:@"MessagePack" code:0 userInfo:exception.userInfo];
		return nil;
	}
}

+ (id) JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error
{
	size_t offset = 0;
	template_context context = { 0 };
	if (template_execute(&context, (const char *)data.bytes, data.length, &offset) != 0)
		return template_data(&context);

	// perhaps data contains JSON?
	return [super JSONObjectWithData:data options:options error:error];
}


#pragma mark - JSON only methods

+ (NSInteger) writeJSONObject:(id)object toStream:(NSOutputStream *)stream options:(NSJSONWritingOptions)options error:(NSError **)error
{
	return [super writeJSONObject:object toStream:stream options:options error:error];
}

+ (id) JSONObjectWithStream:(NSInputStream *)stream options:(NSJSONReadingOptions)options error:(NSError **)error
{
	return [super JSONObjectWithStream:stream options:options error:error];
}

@end

