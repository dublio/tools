#ifndef __TASKSTAT__H_
#define __TASKSTAT__H_
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <dirent.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <linux/taskstats.h>
#include <linux/genetlink.h>
#include <sys/ioctl.h>
#include "list.h"

struct pid_track {
	struct list_head node;
	int pid;
	struct taskstats pts[2];

	unsigned long long delta_io_delay_us, delta_mem_delay_us, delta_cpu_delay_us;
	unsigned long long delta_run;
	unsigned long delta_run_user, delta_run_sys;
	unsigned long long delta_read_bytes, delta_write_bytes;
	float wait_rate;
	float cpu_util, cpu_util_user, cpu_util_sys;
	float pct_run, pct_wait;
	float read_bps, write_bps;
	char cmdline[32]; /* only cut first 32 charactors */
	char comm[PR_SET_NAME];
};

extern int g_index;

/* netlink mode */
extern void pid_lat_deinit_netlink(void);
extern int pid_lat_init_netlink(void);
extern int pid_track_get_delay_netlink(struct pid_track *pt);

/* ioctl mode */
extern void pid_lat_deinit_ioctl(void);
extern int pid_lat_init_ioctl(void);
extern int pid_track_get_delay_ioctl(struct pid_track *pt);
#endif
