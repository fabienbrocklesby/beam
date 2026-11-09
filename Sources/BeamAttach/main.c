// beam-attach: the command a Beam pane's terminal runs. It connects the
// terminal to the pane's session in beamd, which starts the session if it is
// not running yet, then pumps bytes both ways until either side goes away.
// When the session ends the pane closes; when the pane closes, or Beam quits,
// the session keeps running. Frames are laid out in docs/sessions.md and
// Sources/BeamCore/DaemonFrame.swift.

#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <pwd.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <termios.h>
#include <unistd.h>

extern char **environ;

enum { FRAME_ATTACH = 1, FRAME_INPUT = 2, FRAME_RESIZE = 3 };
enum { WINDOW_SIZE_BYTES = 8 };

static struct termios original;
static int raw = 0;

static void restore_terminal(void) {
    if (raw) tcsetattr(STDIN_FILENO, TCSAFLUSH, &original);
}

static int write_all(int fd, const void *bytes, size_t count) {
    const uint8_t *next = bytes;
    while (count > 0) {
        ssize_t written = write(fd, next, count);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return -1;
        next += written;
        count -= (size_t)written;
    }
    return 0;
}

static int send_frame(int sock, uint8_t kind, const void *payload, uint32_t length) {
    uint8_t header[5] = {kind, length & 0xFF, (length >> 8) & 0xFF, (length >> 16) & 0xFF, length >> 24};
    if (write_all(sock, header, sizeof header) < 0) return -1;
    return write_all(sock, payload, length);
}

static void put_u16(uint8_t *out, unsigned short value) {
    out[0] = value & 0xFF;
    out[1] = value >> 8;
}

// This terminal's size as four little-endian shorts: columns, rows, width
// and height in pixels.
static void window_size(uint8_t out[WINDOW_SIZE_BYTES]) {
    struct winsize size = {0};
    ioctl(STDIN_FILENO, TIOCGWINSZ, &size);
    put_u16(out, size.ws_col);
    put_u16(out + 2, size.ws_row);
    put_u16(out + 4, size.ws_xpixel);
    put_u16(out + 6, size.ws_ypixel);
}

// Without beamd the pane still works: it runs the login shell itself, and
// only loses surviving a quit.
static void run_shell_here(const char *why) {
    const char *shell = getenv("SHELL");
    if (shell == NULL || *shell == '\0') {
        struct passwd *entry = getpwuid(getuid());
        shell = entry != NULL && entry->pw_shell != NULL ? entry->pw_shell : "/bin/zsh";
    }
    fprintf(stderr, "beam: %s, so this pane will not survive quitting Beam\r\n", why);
    char path[1024];
    char login_name[1024];
    snprintf(path, sizeof path, "%s", shell);
    snprintf(login_name, sizeof login_name, "-%s", basename(path));
    execl(shell, login_name, (char *)NULL);
    perror("beam: exec");
    exit(127);
}

static int connect_to(const char *path) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof address.sun_path) return -1;
    strcpy(address.sun_path, path);
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) return -1;
    fcntl(sock, F_SETFD, FD_CLOEXEC);
    int on = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
    if (connect(sock, (struct sockaddr *)&address, sizeof address) < 0) {
        close(sock);
        return -1;
    }
    return sock;
}

// The window size, then NUL-terminated: pane ID, working directory, and
// every environment variable, for the session to start with.
static int send_attach(int sock, const char *pane) {
    char directory[4096];
    if (getcwd(directory, sizeof directory) == NULL) directory[0] = '\0';
    size_t length = WINDOW_SIZE_BYTES + strlen(pane) + 1 + strlen(directory) + 1;
    for (char **entry = environ; *entry != NULL; entry++) length += strlen(*entry) + 1;
    uint8_t *payload = malloc(length);
    if (payload == NULL) return -1;
    window_size(payload);
    uint8_t *next = payload + WINDOW_SIZE_BYTES;
    next = (uint8_t *)stpcpy((char *)next, pane) + 1;
    next = (uint8_t *)stpcpy((char *)next, directory) + 1;
    for (char **entry = environ; *entry != NULL; entry++) next = (uint8_t *)stpcpy((char *)next, *entry) + 1;
    int result = send_frame(sock, FRAME_ATTACH, payload, (uint32_t)length);
    free(payload);
    return result;
}

int main(void) {
    const char *pane = getenv("BEAM_PANE_ID");
    const char *path = getenv("BEAM_SOCKET");
    if (pane == NULL || path == NULL) run_shell_here("this pane has no session");
    int sock = connect_to(path);
    if (sock < 0) run_shell_here("beamd is not running");
    if (send_attach(sock, pane) < 0) run_shell_here("beamd did not take the pane");

    // Raw, so every key reaches the session as typed, and the session's own
    // terminal settings decide what Ctrl+C and friends mean.
    if (tcgetattr(STDIN_FILENO, &original) == 0) {
        struct termios settings = original;
        cfmakeraw(&settings);
        if (tcsetattr(STDIN_FILENO, TCSANOW, &settings) == 0) {
            raw = 1;
            atexit(restore_terminal);
        }
    }

    // kqueue records SIGWINCH even while it is ignored, which is its default.
    int queue = kqueue();
    struct kevent changes[3];
    EV_SET(&changes[0], STDIN_FILENO, EVFILT_READ, EV_ADD, 0, 0, NULL);
    EV_SET(&changes[1], sock, EVFILT_READ, EV_ADD, 0, 0, NULL);
    EV_SET(&changes[2], SIGWINCH, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
    if (queue < 0 || kevent(queue, changes, 3, NULL, 0, NULL) < 0) {
        perror("beam: kqueue");
        return 1;
    }

    uint8_t buffer[65536];
    for (;;) {
        struct kevent events[3];
        int count = kevent(queue, NULL, 0, events, 3, NULL);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) return 1;
        for (int i = 0; i < count; i++) {
            if (events[i].filter == EVFILT_SIGNAL) {
                uint8_t size[WINDOW_SIZE_BYTES];
                window_size(size);
                if (send_frame(sock, FRAME_RESIZE, size, sizeof size) < 0) return 0;
            } else if ((int)events[i].ident == STDIN_FILENO) {
                ssize_t read_count = read(STDIN_FILENO, buffer, sizeof buffer);
                if (read_count < 0 && errno == EINTR) continue;
                // The pane closed or Beam quit: the session carries on.
                if (read_count <= 0) return 0;
                if (send_frame(sock, FRAME_INPUT, buffer, (uint32_t)read_count) < 0) return 0;
            } else {
                ssize_t read_count = read(sock, buffer, sizeof buffer);
                if (read_count < 0 && errno == EINTR) continue;
                // The session ended, so the pane closes.
                if (read_count <= 0) return 0;
                if (write_all(STDOUT_FILENO, buffer, (size_t)read_count) < 0) return 0;
            }
        }
    }
}
