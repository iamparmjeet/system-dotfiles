// Minimal replacement for Omarchy's old seamless-login helper.
// Switch to tty1, put it in graphics mode (no console text/cursor between
// Plymouth and the compositor), then exec the given command as the session.
#include <fcntl.h>
#include <linux/kd.h>
#include <linux/vt.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s command [args...]\n", argv[0]);
        return 2;
    }
    int fd = open("/dev/tty1", O_RDWR);
    if (fd < 0) {
        perror("seamless-login: open /dev/tty1");
        return 1;
    }
    if (ioctl(fd, VT_ACTIVATE, 1) < 0) perror("seamless-login: VT_ACTIVATE");
    if (ioctl(fd, VT_WAITACTIVE, 1) < 0) perror("seamless-login: VT_WAITACTIVE");
    if (ioctl(fd, KDSETMODE, KD_GRAPHICS) < 0) perror("seamless-login: KDSETMODE");
    close(fd);
    execvp(argv[1], &argv[1]);
    perror("seamless-login: exec");
    return 1;
}
