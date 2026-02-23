// sqlite_vec_bridge.c
#include "sqlite-vec.h"
#include "sqlite3.h"

int verso_sqlite_vec_register(void) {
    return sqlite3_auto_extension((void (*)(void))sqlite3_vec_init);
}
