//
//

#import <XCTest/XCTest.h>

@interface Libgit_Tests : XCTestCase

@end


#include <git2.h>

@implementation Libgit_Tests

// A simple test to insure that Libgit₂ compiled
- (void) testHashOfEmptyString
{
	git_oid oid;
	XCTAssertTrue(git_odb_hash(&oid, "", 0, GIT_OBJ_BLOB) == GIT_OK, "Couldn’t hash an empty string.");

	char result[GIT_OID_HEXSZ + 1] = { };
	git_oid_fmt(result, &oid);
	XCTAssertTrue(strcmp(result, "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391") == 0, "But the result was %s.", result);
}

@end

