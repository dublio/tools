#include "include.h"

#define TASKSTATS_DEV "/proc/taskstats"
#define TASKSTATS_IOC_ATTR_PID  _IO('T', TASKSTATS_CMD_ATTR_PID)
#define TASKSTATS_IOC_ATTR_TGID _IO('T', TASKSTATS_CMD_ATTR_TGID)

static int g_ioctl_fd;

int pid_lat_init_ioctl(void)
{
	int fd;

	fd = open(TASKSTATS_DEV, O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "failed to open %s\n", TASKSTATS_DEV);
		return -1;
	}
	g_ioctl_fd = fd;

	return 0;
}

void pid_lat_deinit_ioctl(void)
{
	close(g_ioctl_fd);
}

int pid_track_get_delay_ioctl(struct pid_track *pt)
{
	int ret;
	struct taskstats *ts = &pt->pts[g_index];

	ts->ac_pid = pt->pid;

	ret = ioctl(g_ioctl_fd, TASKSTATS_IOC_ATTR_PID, ts);
	if (ret) {
		fprintf(stderr, "pid(%d) ioctl error %lx, %s\n", pt->pid, ret, strerror(ret));
		return -1;
	}

	return 0;
}
