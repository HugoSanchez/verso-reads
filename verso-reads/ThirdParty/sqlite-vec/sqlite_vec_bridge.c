// sqlite_vec_bridge.c
#include <stddef.h>
#include "sqlite-vec.h"
#include "sqlite3.h"

// Register sqlite-vec directly on an open database connection.
// This replaces the previous sqlite3_auto_extension approach which
// returned SQLITE_MISUSE (code 21) on macOS system SQLite.
int verso_sqlite_vec_register_on(sqlite3 *db) {
    return sqlite3_vec_init(db, NULL, NULL);
}
