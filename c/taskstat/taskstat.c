/*
 * taskstat - the statistics of a process
 *
 * Copyright (C) 2020 Weiping Zhang <zwp10758@gmail.com>
 *
 * The license below covers all files distributed with cputil unless otherwise
 * noted in the file itself.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2 as
 *  published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, see <https://www.gnu.org/licenses/>.
 *
 */

#include "include.h"

LIST_HEAD(g_list);

int g_index;
int g_loop;
char g_ts[64];
int g_interval_ms = 1000;
unsigned int g_nr_pid;


static inline unsigned long long
timespec_delta_ns(struct timespec t1, struct timespec t2)
{
	unsigned long long delta_s, delta_ns;

	/*
	 * calculate time diff , t2 alwasy >= t1, that we can
	 * calculate it like fowllowing, no need care negative value.
	 */
	if (t2.tv_sec > t1.tv_sec) {
		delta_s = (t2.tv_sec - t1.tv_sec - 1);
		delta_ns = (1000000000 + t2.tv_nsec) -
			t1.tv_nsec;
		delta_ns += delta_s * 1000000000;
	} else {
		delta_ns = t2.tv_nsec - t1.tv_nsec;
	}

	return delta_ns;
}

/**
 * read_pid_file - read /proc/$pid/FILE
 */
static int read_pid_file(int pid, const char *const name,
				char *buf, int len)
{
	int fd, ret;
	char path[128];

	memset(buf, 0, len);
	snprintf(path, sizeof(path), "/proc/%d/%s", pid, name);
	fd = open(path, O_RDONLY, 0444);
	if (fd == -1) {
#ifdef DBG
		fprintf(stderr, "failed to open %s\n", path);
#endif
		return -1;
	}

	ret = read(fd, buf, len - 1);
	if (ret < 0) {
#ifdef DBG
		fprintf(stderr, "failed to read %s\n", path);
#endif
		ret = -1;
		goto close;
	}
	ret = 0;

close:
	close(fd);
	return ret;
}

static inline int pidtrack_is_monitored(int pid)
{
	struct pid_track *p, *t;

	list_for_each_entry(p, &g_list, node) {
		if (pid == p->pid)
			return 1;
	}

	return 0;
}

static inline struct pid_track *pidtrack_lookup_pid(int pid)
{
	struct pid_track *p;

	list_for_each_entry(p, &g_list, node) {
		if (p->pid == pid)
			return p;
	}

	return NULL;
}

static void pidtrack_convert_cmdline(char *cmdline, size_t len)
{
	size_t i = 0;

	cmdline[len - 1] = '\0';

	for (i = 0; i < len - 1; i++) {
		if (cmdline[i] == '\0') {
			if (cmdline[i + 1] != '\0')
				cmdline[i] = ' ';
			else
				return;
		}
	}
}

static struct pid_track *pid_track_init_one(int pid)
{
	struct pid_track *pt;

	pt = malloc(sizeof(*pt));
	if (!pt) {
		fprintf(stderr, "failed to alloc memory\n");
		return NULL;
	}
	memset(pt, 0, sizeof(*pt));

	INIT_LIST_HEAD(&pt->node);

	pt->pid = pid;

	/* get comm */
	if (read_pid_file(pid, "cmdline", pt->cmdline,
					sizeof(pt->cmdline)))
		snprintf(pt->cmdline, sizeof(pt->cmdline), "NULL");
	else {
		pidtrack_convert_cmdline(pt->cmdline, sizeof(pt->cmdline));
		strtok(pt->cmdline, "\n");
	}

	if (read_pid_file(pid, "comm", pt->comm, sizeof(pt->comm)))
		snprintf(pt->comm, sizeof(pt->comm), "NULL");
	else
		strtok(pt->comm, "\n");

	return pt;
}

static void pid_track_deinit_pid(struct pid_track *pt)
{
	g_nr_pid--;
	list_del(&pt->node);
	free(pt);
}

static int pid_track_init_pid(int pid)
{
	struct pid_track *pt;

	/* create dummy pt node when first time monitor this pid */
	if (!pidtrack_is_monitored(pid)) {
		pt = pid_track_init_one(pid);
		if (!pt)
			return -1;

		list_add_tail(&pt->node, &g_list);
		g_nr_pid++;
	} else {
		pt = pidtrack_lookup_pid(pid);
		if (!pt) {
			fprintf(stderr, "bug: not found struct for pid %d\n", pid);
			_exit(EXIT_FAILURE);
		}
	}

	return 0;
}

/**
 * monitor all process whose's comm contains @comm
 *
 * @comm: the intrested process name
 *
 */
static int pid_track_init(char *comm)
{
	int pid;
	DIR *dirp;
	struct dirent *entry;
	char tmp[1024];	/* big enough for comm */
	const char *dir_path = "/proc/";
	struct pid_track *p;

	dirp = opendir(dir_path);
	if (!dirp) {
		fprintf(stderr, "failed to open %s\n", dir_path);
		return -1;
	}

	for (;;) {
		errno = 0;
		entry = readdir(dirp);
		if (!entry && errno) {
			fprintf(stderr, "failed to readdir %s\n", dir_path);
			goto out;
		}

		/* end of directory stream is reached */
		if (NULL == entry)
			break;

		/* skip . , .. and non-number directories */
		if (!strcmp(".", entry->d_name) || !strcmp("..", entry->d_name)
				|| (entry->d_type != DT_DIR))
			continue;

		if (1 != sscanf(entry->d_name, "%d", &pid))
			continue;

		memset(tmp, 0, sizeof(tmp));
		/* filter process name */
		if (read_pid_file(pid, "comm", tmp, sizeof(tmp)))
			continue;

		if (!strstr(tmp, comm))
			continue;

		if (pid_track_init_pid(pid)) {
			fprintf(stderr, "wrong pid, skip it %d\n", pid);
			continue;
		}
	}
	closedir(dirp);

	return 0;

out:
	closedir(dirp);
	return -1;
}

static void pid_track_deinit(void)
{
	struct pid_track *p, *tmp;

	list_for_each_entry_safe(p, tmp, &g_list, node)
		pid_track_deinit_pid(p);
}

static inline int pid_track_read_data_pid(struct pid_track *pt)
{
	/* read taskstats by netlink socket */
	return pid_track_get_delay_netlink(pt);
}

static int pid_track_read_data(void)
{
	struct pid_track *p, *tmp;

	list_for_each_entry_safe(p, tmp, &g_list, node) {
		if (pid_track_read_data_pid(p))
			pid_track_deinit_pid(p);
	}

	return 0;
}

static void usage(void)
{
	fprintf(stderr, "taskstat process-name\n");
}

static int pid_lat_init(void)
{
	return pid_lat_init_netlink();
}

static void pid_lat_deinit(void)
{
	pid_lat_deinit_netlink();
}


int main(int argc, char **argv)
{
	long sleep_us;
	struct timespec ts_start, ts_end;
	unsigned long long run_ns, interval_ns;
	struct timeval t_sleep;

	if (argc != 2) {
		usage();
		return -1;
	}

	if (pid_track_init(argv[1])) {
		fprintf(stderr, "failed to init pids\n");
		goto cleanup;
	}

	if (pid_lat_init()) {
		fprintf(stderr, "failed to init pid latency\n");
		goto cleanup;
	}

	interval_ns = g_interval_ms * 1000000ULL;

	while (1) {
		clock_gettime(CLOCK_MONOTONIC, &ts_start);

		/* stop loop if there is no pid */
		if (g_nr_pid == 0)
			break;

		if (pid_track_read_data())
			goto cleanup;


		if (g_loop == 0)
			goto sleep;
sleep:
		clock_gettime(CLOCK_MONOTONIC, &ts_end);
		run_ns = timespec_delta_ns(ts_start, ts_end);
		printf("nr_process: %-6d cost: %3d.%09d\n", g_nr_pid, run_ns / 1000000000, run_ns % 1000000000);
		sleep_us = (long)(interval_ns - run_ns) / 1000;
		t_sleep.tv_sec = sleep_us / 1000000L;
		t_sleep.tv_usec = sleep_us % 1000000L;
		select(0, NULL, NULL, NULL, &t_sleep);
		g_loop++;
	}

cleanup:
	pid_track_deinit();
	pid_lat_deinit();

	return 0;
}
