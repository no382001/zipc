#include <inttypes.h>
#include <stdio.h>

#include "image.h"

#define IMAGE_BYTES 65536

static uint8_t image_bytes[IMAGE_BYTES];
static zip_image_t image;
static zip_machine_t machine;

static void print_term(const zip_machine_t *m, word_t t) {
  t = zip_dereference(t);
  switch (TAG(t)) {
  case TAG_REFERENCE:
    printf("_G%td", POINTER(t) - m->global_stack);
    break;
  case TAG_INTEGER:
    printf("%" PRIdPTR, INTEGER_VALUE(t));
    break;
  case TAG_ATOM:
    if (t == ATOM_NIL)
      printf("[]");
    else
      printf("'$atom%" PRIuPTR "'", ATOM_INDEX(t));
    break;
  case TAG_CONS:
    putchar('[');
    for (;;) {
      print_term(m, POINTER(t)[0]);
      t = zip_dereference(POINTER(t)[1]);
      if (TAG(t) != TAG_CONS)
        break;
      putchar(',');
    }
    if (t != ATOM_NIL) {
      putchar('|');
      print_term(m, t);
    }
    putchar(']');
    break;
  }
}

static void print_answer(const zip_machine_t *m, const zip_query_t *q) {
  if (q->variable_count == 0) {
    printf("true");
    return;
  }
  for (uint8_t i = 0; i < q->variable_count; i++) {
    printf("%s%s = ", i > 0 ? ", " : "", q->variables[i]);
    print_term(m, zip_query_variable(m, FRAME_ARGUMENTS + i));
  }
}

// Prints all answers
static bool run_query(const zip_query_t *q) {
  zip_machine_t *m = &machine;

  printf("?- %s\n", q->text);
  zip_initialize(m, &q->clause);
  zip_status_t status = zip_run(m);
  const char *lead = "   ";

  for (;;) {
    switch (status) {
    case ZIP_HALT:
      printf("%s", lead);
      print_answer(m, q);
      if (m->backtrack_frame == NULL) {
        printf(".\n");
        return true;
      }
      printf("\n");
      lead = ";  ";
      status = zip_redo(m);
      break;
    case ZIP_FAIL:
      printf("%sfalse.\n", lead);
      return true;
    case ZIP_ERROR:
      printf("%serror: %s\n", lead, m->error);
      return false;
    }
  }
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s IMAGE\n", argv[0]);
    return 2;
  }
  FILE *f = fopen(argv[1], "rb");
  if (f == NULL) {
    perror(argv[1]);
    return 1;
  }
  size_t length = fread(image_bytes, 1, sizeof image_bytes, f);
  bool too_large = length == sizeof image_bytes && fgetc(f) != EOF;
  bool read_error = ferror(f) != 0;
  fclose(f);
  if (read_error || too_large) {
    fprintf(stderr, "%s: %s\n", argv[1],
            read_error ? "read error" : "image too large");
    return 1;
  }
  if (!zip_load(&image, image_bytes, length)) {
    fprintf(stderr, "%s: byte %zu: %s\n", argv[1], image.error_offset,
            image.error);
    return 1;
  }

  bool ok = true;
  for (uint8_t i = 0; i < image.query_count; i++)
    if (!run_query(&image.queries[i]))
      ok = false;
  return ok ? 0 : 1;
}
