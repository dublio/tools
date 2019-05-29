/*
 * cgroup_cpu_util.c - Cgroup cpu utilization monitor in milliseconds
 *
 * Copyright (C) Weiping Zhang <zwp10758@gmail.com>
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
#include <time.h>
#include <errno.h>
#include <string.h>

char path[PATH_MAX];
struct timespec t, last_t;
unsigned long long u, last_u, delta_s, delta_ns, delta_t;
unsigned long long interval = 1000;
float util;
struct tm *tm;
char buf[32];
char usage[32];

int main(int argc, char **argv)
{
        int ret, fd;

        if (argc != 3 && argc != 2) {
                printf("cgroup_cpu_util path [interval(ms)]\n");
                return 0;
        }

        if (argc == 3)
                interval = strtoull(argv[2], NULL, 10);
        if (interval == ULLONG_MAX)
                interval = 1000;

        snprintf(path, sizeof(path), "%s/cpuacct.usage", argv[1]);
        fd = open(path, O_RDONLY);
        if (fd < 0) {
                printf("failed to open:%s\n", path);
                return 0;
        }

        while (1) {
                ret = pread(fd, usage, sizeof(usage), 0);
                if (ret < 0) {
                        printf("failed to read:%s, %s\n", path, strerror(errno));
                        goto out;
                }
                u = strtoull(usage, NULL, 10);
                if (u == ULLONG_MAX) {
                        printf("failed to strtoull %s\n", usage);
                        goto out;

                }
                clock_gettime(CLOCK_REALTIME, &t);
                if (last_u == 0)
                        goto next;

                tm = localtime(&t.tv_sec);
                if (!strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", tm)) {
                        printf("failed to format time\n");
                        goto out;
                }

                if (t.tv_sec > last_t.tv_sec) {
                        delta_s = (t.tv_sec - last_t.tv_sec - 1);
                        delta_ns = (1000000000 + t.tv_nsec) - last_t.tv_nsec;
                        delta_t = delta_s * 1000000000 + delta_ns;
                } else {
                        delta_t = t.tv_nsec - last_t.tv_nsec;
                }

                util = (float)(u - last_u) * 100 / (float)delta_t;
                printf("%s.%03lu: %.2f\n", buf, t.tv_nsec/1000000, util);

next:
                last_u = u;
                last_t = t;
                usleep (1000 * interval);
        }


out:
        close(fd);
}
