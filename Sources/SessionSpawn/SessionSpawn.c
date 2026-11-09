// posix_spawn cannot do this on macOS: it runs file actions before
// POSIX_SPAWN_SETSID, so the child opens the pty before it leads a session and
// never gets it as its controlling terminal. Then the line discipline signals
// nobody: Ctrl+C, Ctrl+Z and window size changes never reach the shell's jobs.
// (bash hides this by opening its terminal again at startup; zsh does not.)
// So this forks, sets up the session, and execs, as Ghostty does.

#include "SessionSpawn.h"

#include <signal.h>
#include <sys/ioctl.h>
#include <unistd.h>

pid_t session_spawn(const char *path, char *const argv[], char *const envp[], int tty, const char *directory) {
    pid_t pid = fork();
    if (pid != 0) return pid;

    // The child. The parent has other threads, so nothing but
    // async-signal-safe calls until exec.
    struct sigaction defaults = {.sa_handler = SIG_DFL};
    for (int number = 1; number < NSIG; number++) sigaction(number, &defaults, NULL);
    sigset_t none;
    sigemptyset(&none);
    sigprocmask(SIG_SETMASK, &none, NULL);

    if (setsid() < 0 || ioctl(tty, TIOCSCTTY, 0) < 0) _exit(127);
    if (dup2(tty, STDIN_FILENO) < 0 || dup2(tty, STDOUT_FILENO) < 0 || dup2(tty, STDERR_FILENO) < 0) _exit(127);
    if (tty > STDERR_FILENO) close(tty);
    if (chdir(directory) < 0) _exit(127);
    execve(path, argv, envp);
    _exit(127);
}
