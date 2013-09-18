//
//

#include "git2.h"
#include "git2/sys/odb_backend.h"

#include <iostream>
#include <memory>
#include <cstring>

#include "lmdb.h"


struct lmdb_odb_backend : git_odb_backend
{
	lmdb_odb_backend(const char * path);
	~lmdb_odb_backend();
	MDB_env * env; MDB_dbi dbi;
};

static void lmdb_backend_free(git_odb_backend * backend)
{
	delete static_cast<lmdb_odb_backend *>(backend); // ensure the proper destructor gets called
}


static int lmdb_backend_write(git_oid * oid, git_odb_backend * backend, const void * data, size_t length, git_otype type)
{
	git_odb_hash(oid, data, length, type);

	MDB_val key = { .mv_data = oid->id, .mv_size = GIT_OID_RAWSZ };
	MDB_val value = { .mv_data = const_cast<void *>(data), .mv_size = length + 1 }; // ‘type’ is stored at the end

	MDB_txn * txn;
	int rc = mdb_txn_begin(static_cast<lmdb_odb_backend *>(backend)->env, nullptr, 0, &txn);
	if ((rc = mdb_put(txn, static_cast<lmdb_odb_backend *>(backend)->dbi, &key, &value, MDB_RESERVE)) != MDB_SUCCESS)
		return mdb_txn_abort(txn), GIT_ERROR;

	std::memcpy(value.mv_data, data, length);
	static_cast<char *>(value.mv_data)[length] = type;

	rc = mdb_txn_commit(txn);
	return rc == 0 ? GIT_OK : GIT_ERROR;
}

static int lmdb_backend_read(void ** data, size_t * length, git_otype * type, git_odb_backend * backend, const git_oid * oid)
{
	MDB_txn * txn;
	if (mdb_txn_begin(static_cast<lmdb_odb_backend *>(backend)->env, nullptr, MDB_RDONLY, &txn) != MDB_SUCCESS)
		return GIT_ERROR;

	MDB_val key = { .mv_data = const_cast<void *>(reinterpret_cast<const void *>(&oid->id)), .mv_size = GIT_OID_RAWSZ };
	MDB_val value = { };

	int result = mdb_get(txn, static_cast<lmdb_odb_backend *>(backend)->dbi, &key, &value);
	if (result == MDB_NOTFOUND)
		return mdb_txn_abort(txn), GIT_ENOTFOUND;
	else if (result != MDB_SUCCESS)
		return mdb_txn_abort(txn), GIT_ERROR;

    *length = value.mv_size - 1; // type is stored at the end of the value; see lmdb_backend_write
    *type = static_cast<git_otype>(static_cast<const char *>(value.mv_data)[*length]);

	// LMDB would allow a simple pointer assign; but libgit2 insists on freeing the memory passed to it.
    *data = git_odb_backend_malloc(backend, *length);
    std::memcpy(*data, value.mv_data, *length);

	mdb_txn_abort(txn);
	return GIT_OK;
}


static int lmdb_backend_foreach(git_odb_backend * backend, git_odb_foreach_cb callback, void * context)
{
	MDB_txn * txn;
	if (mdb_txn_begin(static_cast<lmdb_odb_backend *>(backend)->env, nullptr, MDB_RDONLY, &txn) != MDB_SUCCESS)
		return GIT_ERROR;

	MDB_cursor * cursor;
	if (mdb_cursor_open(txn, static_cast<lmdb_odb_backend *>(backend)->dbi, &cursor) != MDB_SUCCESS)
		return GIT_ERROR;

	MDB_val key; MDB_val value;
	while ((mdb_cursor_get(cursor, &key, &value, MDB_NEXT)) == 0) {
		if (callback(reinterpret_cast<const git_oid *>(key.mv_data), context) != GIT_OK)
			return mdb_cursor_close(cursor), mdb_txn_abort(txn), GIT_EUSER;
	}

	mdb_cursor_close(cursor);
	mdb_txn_abort(txn);
	return GIT_OK;
}

static int lmdb_backend_exists(git_odb_backend * backend, const git_oid * oid)
{
	MDB_txn * txn;
	if (mdb_txn_begin(static_cast<lmdb_odb_backend *>(backend)->env, nullptr, MDB_RDONLY, &txn) != MDB_SUCCESS)
		return GIT_ERROR;

	MDB_val key = { .mv_data = const_cast<void *>(reinterpret_cast<const void *>(&oid->id)), .mv_size = GIT_OID_RAWSZ };
	MDB_val value = { };

	int result = mdb_get(txn, static_cast<lmdb_odb_backend *>(backend)->dbi, &key, &value);
	mdb_txn_abort(txn);

	return result == MDB_NOTFOUND ? 0 : -1;
}


lmdb_odb_backend::lmdb_odb_backend(const char * path)
	: env(nullptr), dbi(0), git_odb_backend({
		.read = lmdb_backend_read, .write = lmdb_backend_write,
		.exists = lmdb_backend_exists, .foreach = lmdb_backend_foreach,
		.free = lmdb_backend_free, .version = GIT_ODB_BACKEND_VERSION,
	})
{
	int rc;
	if ((rc = mdb_env_create(&env)) != MDB_SUCCESS)
		return mdb_env_close(env);

	constexpr std::size_t maximum = std::size_t(1) << ((sizeof(std::size_t) * 8) - 3); // ⅛ of the address space reserved
	mdb_env_set_mapsize(env, maximum);

	if ((rc = mdb_env_open(env, path, MDB_NOSUBDIR, 0664)) != MDB_SUCCESS) {
		std::cerr << mdb_strerror(rc) << std::endl;
		return this->~lmdb_odb_backend();
	}

	MDB_txn * txn;
	if ((rc = mdb_txn_begin(env, nullptr, 0, &txn)) != MDB_SUCCESS)
		return this->~lmdb_odb_backend();

	if ((rc = mdb_dbi_open(txn, nullptr, 0, &dbi)) != MDB_SUCCESS)
		return this->~lmdb_odb_backend();

	if ((rc = mdb_txn_commit(txn)) != MDB_SUCCESS)
		return this->~lmdb_odb_backend();
}

lmdb_odb_backend::~lmdb_odb_backend()
{
	mdb_dbi_close(env, dbi); dbi = 0; // the destructor is idempotent; important given the error handling in the constructor…
	mdb_env_close(env); env = nullptr;
}


extern "C" int git_odb_backend_lmdb(git_repository * repository, const char * path)
{
	std::unique_ptr<lmdb_odb_backend> backend(new lmdb_odb_backend(path));
    if (backend == nullptr or backend->dbi == 0)
        return GIT_ERROR;

    git_odb * odb;
    git_repository_odb(&odb, repository);
    if (git_odb_add_backend(odb, backend.get(), 100) != GIT_OK)
        return GIT_ERROR;
 
    backend.release();
    git_odb_free(odb);

	return GIT_OK;
}


