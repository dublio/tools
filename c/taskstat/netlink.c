#include "include.h"

/*
 * Generic macros for dealing with netlink sockets. Might be duplicated
 * elsewhere. It is recommended that commercial grade applications use
 * libnl or libnetlink and use the interfaces provided by the library
 */
#define GENLMSG_DATA(glh)       ((void *)(NLMSG_DATA(glh) + GENL_HDRLEN))
#define GENLMSG_PAYLOAD(glh)    (NLMSG_PAYLOAD(glh, 0) - GENL_HDRLEN)
#define NLA_DATA(na)            ((void *)((char*)(na) + NLA_HDRLEN))
#define NLA_PAYLOAD(len)        (len - NLA_HDRLEN)


/* Maximum size of response requested or message sent */
#define MAX_MSG_SIZE    2048
struct msgtemplate {
	struct nlmsghdr n;
	struct genlmsghdr g;
	char buf[MAX_MSG_SIZE];
};

int g_socket_fd;
uint16_t g_family_id;
static int nl_send_cmd(int sd, uint16_t nlmsg_type, uint32_t nlmsg_pid,
			uint8_t genl_cmd, uint16_t nla_type,
			void *nla_data, int nla_payload_len)
{
	struct nlattr *na;
	struct sockaddr_nl nladdr;
	int r, buflen, retry = 0;
	char *buf;
	struct msgtemplate msg;

	memset(&msg, 0, sizeof(msg));
	msg.n.nlmsg_len = NLMSG_LENGTH(GENL_HDRLEN);
	msg.n.nlmsg_type = nlmsg_type;
	msg.n.nlmsg_flags = NLM_F_REQUEST;
	msg.n.nlmsg_seq = 0;
	msg.n.nlmsg_pid = nlmsg_pid;
	msg.g.cmd = genl_cmd;
	msg.g.version = 0x1;
	na = (struct nlattr *) GENLMSG_DATA(&msg);
	na->nla_type = nla_type;
	na->nla_len = nla_payload_len + NLA_HDRLEN;
	memcpy(NLA_DATA(na), nla_data, nla_payload_len);
	msg.n.nlmsg_len += NLMSG_ALIGN(na->nla_len);

	buf = (char *) &msg;
	buflen = msg.n.nlmsg_len ;
	memset(&nladdr, 0, sizeof(nladdr));
	nladdr.nl_family = AF_NETLINK;
	while ((r = sendto(sd, buf, buflen, 0, (struct sockaddr *) &nladdr,
			   sizeof(nladdr))) < buflen) {
		if (r > 0) {
			buf += r;
			buflen -= r;
		} else {
			if (errno == EAGAIN) {
				/* retry 5 times before return failure */
				if (retry > 5)
					return -1;
				retry ++;
			} else
				return -1;
		}
	}

	return 0;
}

int pid_track_get_delay_netlink(struct pid_track *pt)
{
	int len, msg_len, len2, aggr_len;
	struct msgtemplate msg;
	struct nlattr *na;

	len = nl_send_cmd(g_socket_fd, g_family_id, getpid(), TASKSTATS_CMD_GET,
				TASKSTATS_CMD_ATTR_PID, &pt->pid, sizeof(__u32));
	if (len < 0) {
#ifdef DBG
		fprintf(stderr, "send cgroupstats command failed %d\n", pt->pid);
#endif
		return -1;
	}

	len = recv(g_socket_fd, &msg, sizeof(msg), 0);
	if (len < 0 || msg.n.nlmsg_type == NLMSG_ERROR ||
	   !NLMSG_OK((&msg.n), len)) {
#ifdef DBG
		fprintf(stderr, "get msg failed, %d\n", pt->pid);
#endif
		return -1;
	}

	na = (struct nlattr *) GENLMSG_DATA(&msg);
	if (na->nla_type != TASKSTATS_TYPE_AGGR_PID) {
#ifdef DBG
		fprintf(stderr, "wrong GENLMSG_DATA nla_type, %d\n", pt->pid);
#endif
		return -1;
	}
	msg_len = GENLMSG_PAYLOAD(&msg.n);

	/* all receive data */
	len = 0;
	while (len < msg_len) {
		len += NLA_ALIGN(na->nla_len);

		if (na->nla_type != TASKSTATS_TYPE_AGGR_PID &&
			na->nla_type != TASKSTATS_TYPE_AGGR_TGID) {
#ifdef DBG
		fprintf(stderr, "wrong GENLMSG_DATA nla_type, %d\n", pt->pid);
#endif
			goto next;
		}
		aggr_len = NLA_PAYLOAD(na->nla_len);
		na = (struct nlattr *) NLA_DATA(na);
		len2 = 0;
		while (len2 < aggr_len) {
			if (na->nla_type == TASKSTATS_TYPE_STATS) {
				memcpy(&pt->pts[g_index], (struct taskstats *) NLA_DATA(na),
					sizeof(struct taskstats));
			}
			len2 += NLA_ALIGN(na->nla_len);
			na = (struct nlattr *) ((char *) na + len2);
		}
next:
		na = (struct nlattr *) (GENLMSG_DATA(&msg) + len);
	}

	return 0;
}
static int pid_lat_nl_socket_init(void)
{
	struct sockaddr_nl addr;
	int fd;

	fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_GENERIC);
	if (fd < 0) {
		printf("failed to create socket\n");
		return -1;
	}

	memset(&addr, 0, sizeof(addr));
	addr.nl_family = AF_NETLINK;

	if (bind(fd, (struct sockaddr *) &addr, sizeof(addr)) < 0) {
		printf("failed to bind socket\n");
		goto close;
	}

	g_socket_fd = fd;

	return 0;

close:
	close(fd);
	return -1;

}

static void pid_lat_nl_socket_deint(void)
{
	close(g_socket_fd);
}

static int pid_lat_get_family_id(void)
{
	struct msgtemplate msg;
	struct nlattr *na;
	int len, sd = g_socket_fd;
	char name[100];

	strcpy(name, TASKSTATS_GENL_NAME);
	len = nl_send_cmd(sd, GENL_ID_CTRL, getpid(), CTRL_CMD_GETFAMILY,
			CTRL_ATTR_FAMILY_NAME, (void *)name,
			strlen(TASKSTATS_GENL_NAME) + 1);
	if (len < 0) {
		printf("send getfamily command failed\n");
		return -1;
	}

	len = recv(sd, &msg, sizeof(msg), 0);
	if (len < 0 || msg.n.nlmsg_type == NLMSG_ERROR ||
	    !NLMSG_OK((&msg.n), len)) {
		printf("tailed to get msg\n");
		return -1;
	}

	/* FAMILY_NAME */
	na = (struct nlattr *) GENLMSG_DATA(&msg);
	/* FAMILY_ID */
	na = (struct nlattr *) ((char *) na + NLA_ALIGN(na->nla_len));
	if (na->nla_type != CTRL_ATTR_FAMILY_ID) {
		printf("get wrong nla_type\n");
		return -1;
	}

	g_family_id = *(uint16_t *) NLA_DATA(na);

	return 0;
}

int pid_lat_init_netlink(void)
{
	if (pid_lat_nl_socket_init())
		return -1;

	if (pid_lat_get_family_id())
		goto deinit_socket;

	return 0;

deinit_socket:
	pid_lat_nl_socket_deint();
	return -1;
}

void pid_lat_deinit_netlink(void)
{
	pid_lat_nl_socket_deint();
}
