#include <string.h>

#include "image.h"

typedef struct {
  const uint8_t *start;
  const uint8_t *next;
  const uint8_t *end;
  zip_image_t *image;
} reader_t;

static bool fail(reader_t *r, const char *error) {
  r->image->error = error;
  r->image->error_offset = (size_t)(r->next - r->start);
  return false;
}

static bool read_bytes(reader_t *r, size_t count, const uint8_t **bytes) {
  if ((size_t)(r->end - r->next) < count)
    return fail(r, "truncated image");
  *bytes = r->next;
  r->next += count;
  return true;
}

static bool read_u8(reader_t *r, uint8_t *value) {
  const uint8_t *p;
  if (!read_bytes(r, 1, &p))
    return false;
  *value = p[0];
  return true;
}

static bool read_u16(reader_t *r, uint16_t *value) {
  const uint8_t *p;
  if (!read_bytes(r, 2, &p))
    return false;
  *value = (uint16_t)(p[0] | p[1] << 8);
  return true;
}

// an i32 must fit in a tagged integer word.
static bool read_integer(reader_t *r, word_t *value) {
  const uint8_t *p;
  if (!read_bytes(r, 4, &p))
    return false;
  uint32_t u = (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
               (uint32_t)p[3] << 24;
  int32_t n = u <= INT32_MAX ? (int32_t)u : -(int32_t)(UINT32_MAX - u) - 1;
  word_t w = MAKE_INTEGER(n);
  if (INTEGER_VALUE(w) != n)
    return fail(r, "integer too large for a tagged word");
  *value = w;
  return true;
}

static bool read_string(reader_t *r, const char **string) {
  uint8_t length;
  const uint8_t *p;
  if (!read_u8(r, &length) || !read_bytes(r, (size_t)length + 1, &p))
    return false;
  if (p[length] != 0 || memchr(p, 0, length) != NULL)
    return fail(r, "malformed string");
  *string = (const char *)p;
  return true;
}

static bool read_key(reader_t *r, word_t *key) {
  uint8_t term;
  if (!read_u8(r, &term))
    return false;
  switch (term) {
  case IMAGE_TERM_ANY:
    *key = KEY_ANY;
    return true;
  case IMAGE_TERM_NIL:
    *key = ATOM_NIL;
    return true;
  case IMAGE_TERM_CONS:
    *key = KEY_CONS;
    return true;
  case IMAGE_TERM_INTEGER:
    return read_integer(r, key);
  }
  return fail(r, "bad clause key");
}

static bool read_reference(reader_t *r, zip_external_reference_t *reference,
                           zip_operand_t *kind) {
  uint8_t term, index;
  if (!read_u8(r, &term))
    return false;
  switch (term) {
  case IMAGE_TERM_NIL:
    reference->value = ATOM_NIL;
    *kind = OPERAND_CONSTANT;
    return true;
  case IMAGE_TERM_INTEGER:
    *kind = OPERAND_CONSTANT;
    return read_integer(r, &reference->value);
  case IMAGE_TERM_PROCEDURE:
    if (!read_u8(r, &index))
      return false;
    if (index >= r->image->procedure_count)
      return fail(r, "procedure index out of range");
    reference->procedure = &r->image->procedures[index];
    *kind = OPERAND_PROCEDURE;
    return true;
  }
  return fail(r, "bad external reference");
}

static const zip_opcode_info_t *opcode_info(uint8_t code) {
  for (size_t i = 0; i < zip_opcode_count; i++)
    if (zip_opcodes[i].code == code)
      return &zip_opcodes[i];
  return NULL;
}

static bool ends_clause(zip_opcode_t code) {
  return code == OPCODE_RETURN || code == OPCODE_DEPART ||
         code == OPCODE_PROCEED || code == OPCODE_FAIL || code == OPCODE_HALT;
}

// sanity checks
static bool verify(reader_t *r, const uint8_t *code, uint16_t length,
                   const zip_operand_t *kinds, uint8_t reference_count) {
  const zip_opcode_info_t *info = NULL;
  uint16_t i = 0;
  while (i < length) {
    info = opcode_info(code[i++]);
    if (info == NULL)
      return fail(r, "unknown opcode");
    for (uint8_t j = 0; j < info->operand_count; j++) {
      if (i == length)
        return fail(r, "truncated instruction");
      uint8_t operand = code[i++];
      zip_operand_t kind = info->operands[j];
      if ((kind == OPERAND_PROCEDURE || kind == OPERAND_CONSTANT) &&
          (operand == 0 || operand > reference_count || kinds[operand] != kind))
        return fail(r, "bad external reference operand");
    }
  }
  if (info == NULL || !ends_clause(info->code))
    return fail(r, "code falls off its end");
  return true;
}

static bool read_code(reader_t *r, zip_clause_t *clause) {
  zip_image_t *image = r->image;
  zip_operand_t kinds[UINT8_MAX + 1];
  uint8_t reference_count;
  if (!read_u8(r, &reference_count))
    return false;
  if ((size_t)(ZIP_IMAGE_REFERENCES - image->reference_count) <
      (size_t)reference_count + 1)
    return fail(r, "too many external references");

  zip_external_reference_t *references =
      &image->references[image->reference_count];
  image->reference_count =
      (uint16_t)(image->reference_count + reference_count + 1);
  references[0].value = 0;
  for (uint16_t i = 1; i <= reference_count; i++)
    if (!read_reference(r, &references[i], &kinds[i]))
      return false;

  uint16_t length;
  const uint8_t *code;
  if (!read_u16(r, &length) || !read_bytes(r, length, &code) ||
      !verify(r, code, length, kinds, reference_count))
    return false;
  clause->code = code;
  clause->external_references = references;
  return true;
}

static bool read_procedure(reader_t *r, zip_procedure_t *procedure) {
  zip_image_t *image = r->image;
  uint8_t clause_count;
  if (!read_string(r, &procedure->name) || !read_u8(r, &procedure->arity) ||
      !read_u8(r, &clause_count))
    return false;
  // enter_procedure needs a first clause to find the procedure from.
  if (clause_count == 0)
    return fail(r, "procedure has no clauses");
  if (ZIP_IMAGE_CLAUSES - image->clause_count < clause_count)
    return fail(r, "too many clauses");

  zip_clause_t *clauses = &image->clauses[image->clause_count];
  image->clause_count = (uint16_t)(image->clause_count + clause_count);
  for (uint8_t i = 0; i < clause_count; i++) {
    zip_clause_t *c = &clauses[i];
    if (!read_key(r, &c->key) || !read_code(r, c))
      return false;
    c->procedure = procedure;
    c->next = i + 1 < clause_count ? &clauses[i + 1] : NULL;
  }
  procedure->first = clauses;
  return true;
}

static bool read_query(reader_t *r, zip_query_t *query) {
  if (!read_string(r, &query->text) || !read_u8(r, &query->variable_count))
    return false;
  if (query->variable_count > ZIP_QUERY_VARIABLES)
    return fail(r, "too many query variables");
  for (uint8_t i = 0; i < query->variable_count; i++)
    if (!read_string(r, &query->variables[i]))
      return false;
  query->clause = (zip_clause_t){.key = KEY_ANY};
  return read_code(r, &query->clause);
}

bool zip_load(zip_image_t *image, const uint8_t *bytes, size_t length) {
  reader_t r = {bytes, bytes, bytes + length, image};
  image->procedure_count = 0;
  image->query_count = 0;
  image->clause_count = 0;
  image->reference_count = 0;
  image->error = NULL;
  image->error_offset = 0;

  const uint8_t *magic;
  uint8_t version, procedure_count, query_count;
  if (!read_bytes(&r, sizeof ZIP_IMAGE_MAGIC - 1, &magic))
    return false;
  if (memcmp(magic, ZIP_IMAGE_MAGIC, sizeof ZIP_IMAGE_MAGIC - 1) != 0)
    return fail(&r, "not a ZIP image");
  if (!read_u8(&r, &version))
    return false;
  if (version != ZIP_IMAGE_VERSION)
    return fail(&r, "unsupported image version");
  if (!read_u8(&r, &procedure_count) || !read_u8(&r, &query_count))
    return false;
  if (procedure_count > ZIP_IMAGE_PROCEDURES)
    return fail(&r, "too many procedures");
  if (query_count > ZIP_IMAGE_QUERIES)
    return fail(&r, "too many queries");

  // set first so that references to later procedures can be checked.
  image->procedure_count = procedure_count;
  for (uint8_t i = 0; i < procedure_count; i++)
    if (!read_procedure(&r, &image->procedures[i]))
      return false;
  for (uint8_t i = 0; i < query_count; i++)
    if (!read_query(&r, &image->queries[i]))
      return false;
  if (r.next != r.end)
    return fail(&r, "trailing bytes after image");
  image->query_count = query_count;
  return true;
}
