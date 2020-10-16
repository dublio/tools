#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <string.h>
#include <errno.h>
#include <stdint.h>
#include <limits.h>


int main(int argc, char **argv)
{
        int fd, ret;
	char *file = "/dev/kmsg";
	char buf[PATH_MAX];
	struct stat st;
	int ret2;

        fd = open(file, O_WRONLY);
        if (fd < 0)
                return -1;

	snprintf(buf, sizeof(buf), "released cgroup:%s\n", argv[1]);
	ret = write(fd, buf, strlen(buf));
        if (ret <= 0) {
		close(fd);
                return -1;
        }

        close(fd);
        return 0;
}
