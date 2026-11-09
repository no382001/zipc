#include <inttypes.h>
#include <stdio.h>

#include "image.h"

static const char *operand_name(zip_operand_t kind) {
  switch (kind) {
  case OPERAND_BYTE:
    return "byte";
  case OPERAND_LOCAL:
    return "local";
  case OPERAND_PROCEDURE:
    return "procedure";
  case OPERAND_CONSTANT:
    return "constant";
  }
  return "?";
}

int main(void) {
  printf("%% auto-generated from zip_opcodes in src/zip.c\n");
  printf(":- module(gen, [opcode/3, frame_arguments/1, image_magic/1, "
         "image_version/1, image_term/2]).\n\n");

  printf("%% opcode(Name, Opcode, OperandKinds).\n");
  for (size_t i = 0; i < zip_opcode_count; i++) {
    const zip_opcode_info_t *info = &zip_opcodes[i];
    printf("opcode(%s, %" PRIu8 ", [", info->name, (uint8_t)info->code);
    for (uint8_t j = 0; j < info->operand_count; j++)
      printf("%s%s", j > 0 ? "," : "", operand_name(info->operands[j]));
    printf("]).\n");
  }

  printf("\n%% frame_arguments(Offset): frame offset of the first argument "
         "slot.\n");
  printf("frame_arguments(%" PRIu8 ").\n", (uint8_t)FRAME_ARGUMENTS);

  printf("\n%% auto-generated from src/image.h\n");
  printf("image_magic([");
  for (size_t i = 0; i < sizeof ZIP_IMAGE_MAGIC - 1; i++)
    printf("%s%" PRIu8, i > 0 ? "," : "", (uint8_t)ZIP_IMAGE_MAGIC[i]);
  printf("]).\n");
  printf("image_version(%" PRIu8 ").\n", (uint8_t)ZIP_IMAGE_VERSION);
  printf("image_term(any, %" PRIu8 ").\n", (uint8_t)IMAGE_TERM_ANY);
  printf("image_term(nil, %" PRIu8 ").\n", (uint8_t)IMAGE_TERM_NIL);
  printf("image_term(cons, %" PRIu8 ").\n", (uint8_t)IMAGE_TERM_CONS);
  printf("image_term(integer, %" PRIu8 ").\n", (uint8_t)IMAGE_TERM_INTEGER);
  printf("image_term(procedure, %" PRIu8 ").\n", (uint8_t)IMAGE_TERM_PROCEDURE);
  return 0;
}
