//
//

#pragma once


GIT_BEGIN_DECL

int git_odb_backend_lmdb(git_repository * repository, const char * path);


int git_odb_backend_lmdb_begin(git_repository * repository);
int git_odb_backend_lmdb_commit(git_repository * repository);
int git_odb_backend_lmdb_rollback(git_repository * repository);

GIT_END_DECL

