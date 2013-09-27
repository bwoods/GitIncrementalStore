//
//

#include "git2.h"

#pragma once


GIT_BEGIN_DECL

int git_odb_add_transactional_backend(git_repository * repository, const char * path);


int git_odb_transaction_begin(git_repository * repository);
int git_odb_transaction_commit(git_repository * repository);
int git_odb_transaction_rollback(git_repository * repository);

GIT_END_DECL

