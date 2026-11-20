/* libpq client parsing SERVER bytes: the fuzz input is served as the server side of a Unix
 * socket that PQconnectdb() connects to. Reaches fe-connect.c's startup/auth state machine
 * (cleartext/MD5/SCRAM in fe-auth*.c), fe-protocol3.c message parsing (ParameterStatus,
 * BackendKeyData, ErrorResponse/NoticeResponse fields, RowDescription, DataRow, CopyData ...)
 * and fe-exec.c result building via PQexec.
 *
 * State kept across inputs: one listening socket in a private temp dir, created once. Each
 * input gets its own accepted connection and server thread, both torn down before returning. */
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include "libpq-fe.h"

static int	listen_fd = -1;
static char conninfo[512];

struct serve
{
	const uint8_t *data;
	size_t		size;
};

static void *
server(void *arg)
{
	struct serve *s = arg;
	char		buf[4096];
	int			fd = accept(listen_fd, NULL, NULL);
	size_t		off = 0;

	if (fd < 0)
		return NULL;
	/* the input is small next to the socket buffer, so this does not wait on the client */
	while (off < s->size)
	{
		ssize_t		n = write(fd, s->data + off, s->size - off);
		if (n <= 0)
			break;
		off += n;
	}
	shutdown(fd, SHUT_WR);
	/* drain whatever the client sends until it hangs up */
	while (read(fd, buf, sizeof(buf)) > 0)
		;
	close(fd);
	return NULL;
}

static void
notice_sink(void *arg, const PGresult *res)
{
	(void) arg;
	(void) PQresultErrorField(res, PG_DIAG_MESSAGE_PRIMARY);
}

int
LLVMFuzzerInitialize(int *argc, char ***argv)
{
	const char *tmp = getenv("TMPDIR");
	char		dir[256];
	struct sockaddr_un addr;

	(void) argc;
	(void) argv;
	snprintf(dir, sizeof(dir), "%s/pqfuzzXXXXXX", tmp && *tmp ? tmp : "/tmp");
	if (!mkdtemp(dir))
		abort();
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	snprintf(addr.sun_path, sizeof(addr.sun_path), "%s/.s.PGSQL.5432", dir);
	listen_fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (listen_fd < 0 || bind(listen_fd, (struct sockaddr *) &addr, sizeof(addr)) != 0 ||
		listen(listen_fd, 4) != 0)
		abort();
	/* no password file / service file lookups: the result depends only on the input */
	setenv("PGPASSFILE", "/nonexistent", 1);
	setenv("PGSERVICEFILE", "/nonexistent", 1);
	unsetenv("PGSERVICE");
	snprintf(conninfo, sizeof(conninfo),
			 "host=%s port=5432 user=fuzz dbname=fuzz password=fuzzpass sslmode=disable "
			 "application_name=fuzz", dir);
	return 0;
}

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct serve s = {data, size};
	pthread_t	th;
	PGconn	   *conn;

	if (pthread_create(&th, NULL, server, &s) != 0)
		abort();
	conn = PQconnectdb(conninfo);
	if (conn)
	{
		PQsetNoticeReceiver(conn, notice_sink, NULL);
		if (PQstatus(conn) == CONNECTION_OK)
		{
			PGresult   *res;

			(void) PQparameterStatus(conn, "server_version");
			(void) PQbackendPID(conn);
			if (PQsendQuery(conn, "SELECT 1"))
			{
				while ((res = PQgetResult(conn)) != NULL)
				{
					int			nf = PQnfields(res), nt = PQntuples(res);
					for (int i = 0; i < nf; i++)
						(void) PQfname(res, i);
					for (int r = 0; r < nt; r++)
						for (int c = 0; c < nf; c++)
							(void) PQgetlength(res, r, c);
					(void) PQresultErrorField(res, PG_DIAG_SQLSTATE);
					PQclear(res);
				}
			}
		}
		PQfinish(conn);
	}
	pthread_join(th, NULL);
	return 0;
}
