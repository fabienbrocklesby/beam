#ifndef SESSION_SPAWN_H
#define SESSION_SPAWN_H

#include <sys/types.h>

/// Starts `path` with `argv` and `envp` (both NULL-terminated) as the leader
/// of a new session whose controlling terminal is the pty slave `tty`, which
/// becomes its standard input, output and error. It starts in `directory`,
/// with default signal handling and nothing blocked.
///
/// Returns the child's pid, or -1 with errno set when it could not start one.
/// A child that cannot take the terminal, the directory or the program exits
/// with status 127.
pid_t session_spawn(const char *path, char *const argv[], char *const envp[], int tty, const char *directory);

#endif
