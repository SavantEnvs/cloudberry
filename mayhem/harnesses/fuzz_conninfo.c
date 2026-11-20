/* libpq connection-string / URI parser: PQconninfoParse (fe-connect.c conninfo_parse,
 * conninfo_uri_parse, percent-decoding, option validation). */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "libpq-fe.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char	   *s = malloc(size + 1);
	char	   *err = NULL;
	PQconninfoOption *opts;

	memcpy(s, data, size);
	s[size] = '\0';
	opts = PQconninfoParse(s, &err);
	if (opts)
	{
		/* walk the result like a client would */
		for (PQconninfoOption *o = opts; o->keyword; o++)
			if (o->val)
				(void) strlen(o->val);
		PQconninfoFree(opts);
	}
	if (err)
		PQfreemem(err);
	free(s);
	return 0;
}
