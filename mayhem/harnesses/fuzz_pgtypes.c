/* ecpg pgtypeslib text parsers: numeric/decimal, date, timestamp and interval
 * *_from_asc, round-tripped through *_to_asc. First byte selects the type. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "pgtypes_numeric.h"
#include "pgtypes_date.h"
#include "pgtypes_timestamp.h"
#include "pgtypes_interval.h"
#include "pgtypes.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char	   *s, *end = NULL, *out;
	if (size < 1)
		return -1;
	s = malloc(size);
	memcpy(s, data + 1, size - 1);
	s[size - 1] = '\0';

	switch (data[0] % 4)
	{
		case 0:
		{
			numeric    *n = PGTYPESnumeric_from_asc(s, &end);
			if (n)
			{
				out = PGTYPESnumeric_to_asc(n, -1);
				if (out) PGTYPESchar_free(out);
				out = PGTYPESnumeric_to_asc(n, 2);
				if (out) PGTYPESchar_free(out);
				PGTYPESnumeric_free(n);
			}
			break;
		}
		case 1:
		{
			date		d = PGTYPESdate_from_asc(s, &end);
			out = PGTYPESdate_to_asc(d);
			if (out) PGTYPESchar_free(out);
			break;
		}
		case 2:
		{
			timestamp	t = PGTYPEStimestamp_from_asc(s, &end);
			out = PGTYPEStimestamp_to_asc(t);
			if (out) PGTYPESchar_free(out);
			break;
		}
		case 3:
		{
			interval   *iv = PGTYPESinterval_from_asc(s, &end);
			if (iv)
			{
				out = PGTYPESinterval_to_asc(iv);
				if (out) PGTYPESchar_free(out);
				PGTYPESinterval_free(iv);
			}
			break;
		}
	}
	free(s);
	return 0;
}
