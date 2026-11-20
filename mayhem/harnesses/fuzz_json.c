/* src/common/jsonapi.c: the frontend JSON lexer/parser (used by pg_verifybackup's
 * backup_manifest parser), through its public entry pg_parse_json. */
#include "postgres_fe.h"
#include "common/jsonapi.h"
#include "mb/pg_wchar.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char	   *s = malloc(size + 1);
	JsonLexContext *lex;
	JsonParseErrorType rc;

	memcpy(s, data, size);
	s[size] = '\0';
	lex = makeJsonLexContextCstringLen(s, (int) size, PG_UTF8, true);
	rc = pg_parse_json(lex, &nullSemAction);
	(void) rc;
	if (lex->strval)
	{
		pfree(lex->strval->data);
		pfree(lex->strval);
	}
	pfree(lex);
	free(s);
	return 0;
}
