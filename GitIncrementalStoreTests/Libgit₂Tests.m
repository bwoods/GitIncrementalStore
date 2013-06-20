//
//

#import <XCTest/XCTest.h>

@interface Libgit_Tests : XCTestCase

@end


#include "git2.h"

@implementation Libgit_Tests

// A simple test to ensure that Libgit₂ compiled was with threads enabled
- (void) testThatThreadingWasEnabled
{
	int cap = git_libgit2_capabilities();
	XCTAssertTrue(cap & GIT_CAP_THREADS);
}


#pragma mark - Well known (constant) hashing values

- (void) testHashOfEmptyString
{
	git_oid oid;
	XCTAssertTrue(git_odb_hash(&oid, "", 0, GIT_OBJ_BLOB) == GIT_OK, "Couldn’t hash an empty blob.");

	char result[GIT_OID_HEXSZ + 1] = { };
	git_oid_fmt(result, &oid);
	XCTAssertTrue(strcmp(result, "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391") == 0, "But the result was %s.", result);
}

- (void) testHashOfEmptyTree
{
	git_oid oid;
	XCTAssertTrue(git_odb_hash(&oid, "", 0, GIT_OBJ_TREE) == GIT_OK, "Couldn’t hash an empty tree.");

	char result[GIT_OID_HEXSZ + 1] = { };
	git_oid_fmt(result, &oid);
	XCTAssertTrue(strcmp(result, "4b825dc642cb6eb9a060e54bf8d69288fbee4904") == 0, "But the result was %s.", result);
}

@end

