/* src/common decoders that see attacker bytes: pglz_decompress (TOAST), pg_saslprep
 * and unicode_normalize (SCRAM auth), pg_b64_decode (SCRAM messages) and
 * pg_encoding_verifymbstr (client encoding verification). First byte selects. */
#include "postgres_fe.h"
#include "common/base64.h"
#include "common/pg_lzcompress.h"
#include "common/saslprep.h"
#include "common/unicode_norm.h"
#include "mb/pg_wchar.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	const char *p;
	int			len;

	if (size < 2)
		return -1;
	p = (const char *) data + 2;
	len = (int) size - 2;

	switch (data[0] % 5)
	{
		case 0:
		{
			/* rawsize is the caller-supplied output capacity (TOAST header) */
			int32		rawsize = (data[1] + 1) * 64;
			char	   *dst = malloc(rawsize);
			(void) pglz_decompress(p, len, dst, rawsize, (data[1] & 1) != 0);
			free(dst);
			break;
		}
		case 1:
		{
			char	   *s = malloc(len + 1), *out = NULL;
			memcpy(s, p, len);
			s[len] = '\0';
			if (pg_saslprep(s, &out) == SASLPREP_SUCCESS && out)
				free(out);
			free(s);
			break;
		}
		case 2:
		{
			/* unicode_normalize takes a 0-terminated pg_wchar string of valid code points */
			int			n = len / 4;
			pg_wchar   *in = malloc((n + 1) * sizeof(pg_wchar));
			pg_wchar   *out;
			for (int i = 0; i < n; i++)
			{
				pg_wchar	c;
				memcpy(&c, p + 4 * i, 4);
				c %= 0x110000;
				in[i] = c ? c : 0x20;
			}
			in[n] = 0;
			out = unicode_normalize((UnicodeNormalizationForm) (data[1] % 4), in);
			if (out)
				free(out);
			free(in);
			break;
		}
		case 3:
		{
			int			dlen = pg_b64_dec_len(len);
			char	   *dst = malloc(dlen + 1);
			(void) pg_b64_decode(p, len, dst, dlen);
			free(dst);
			break;
		}
		case 4:
		{
			int			enc = data[1] % _PG_LAST_ENCODING_;
			(void) pg_encoding_verifymbstr(enc, p, len);
			break;
		}
	}
	return 0;
}
