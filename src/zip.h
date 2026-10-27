#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef uintptr_t word_t;

enum {
  TAG_REFERENCE = 0,
  TAG_INTEGER = 1,
  TAG_ATOM = 2,
  TAG_CONS = 3,
  TAG_MASK = 3,
};

#define TAG(w) ((w) & TAG_MASK)
#define POINTER(w) ((word_t *)((w) & ~(word_t)TAG_MASK))
#define MAKE_REFERENCE(p) ((word_t)(p))
#define MAKE_CONS(p) ((word_t)(p) | TAG_CONS)
#define MAKE_INTEGER(n) (((word_t)(intptr_t)(n) << 2) | TAG_INTEGER)
#define INTEGER_VALUE(w) ((intptr_t)(w) >> 2)
#define MAKE_ATOM(i) (((word_t)(i) << 2) | TAG_ATOM)
#define ATOM_INDEX(w) ((w) >> 2)

#define ATOM_NIL MAKE_ATOM(0)

typedef enum {
  OPCODE_VAR = 4,       // unify subsequent occurrence of variable
  OPCODE_FIRSTVAR = 5,  // unify first occurrence of local or temporary variable
  OPCODE_POP = 7,       // complete a compound term
  OPCODE_SKIPVAR = 8,   // unify first occurrence of an argument variable
  OPCODE_CONSTANT = 11, // unify constant
  OPCODE_ENTER = 12,    // the neck of a clause
  OPCODE_RETURN = 13,   // the neck of a unit clause
  OPCODE_ARGMODE = 14,  // the neck of a doublet clause
  OPCODE_DEPART = 16,   // call the last goal in a clause
  OPCODE_CALL = 17,     // call a goal
  OPCODE_PROCEED = 18,  // call the only goal in a clause
  OPCODE_FAIL = 19,     // compiled fail
  OPCODE_IMMED = 27,    // unify constant small integer
  OPCODE_CONSLIST = 33, // unify the functor '.' of arity 2
  OPCODE_LASTCONSLIST =
      34, // unify the last functor '.' of arity 2 in a nested term
  OPCODE_CONSTNIL = 35, // unify the constant '[]'
  OPCODE_HALT = 63,     // not ZIP: return control to the host
} zip_opcode_t;

typedef enum {
  OPERAND_BYTE,      // literal 0..255
  OPERAND_LOCAL,     // frame offset from the current frame
  OPERAND_PROCEDURE, // external reference slot holding a procedure
  OPERAND_CONSTANT,  // external reference slot holding a constant word
} zip_operand_t;

#define ZIP_MAX_OPERANDS 2

typedef struct {
  zip_opcode_t code;
  const char *name;
  uint8_t operand_count;
  zip_operand_t operands[ZIP_MAX_OPERANDS];
} zip_opcode_info_t;

extern const zip_opcode_info_t zip_opcodes[];
extern const size_t zip_opcode_count;

typedef enum { MODE_MATCH = 0, MODE_COPY = 1, MODE_ARGUMENT = 2 } zip_mode_t;

enum {
  FRAME_SIZE = 0,
  FRAME_CONTINUATION = 1,       // [CP]  where to continue on success
  FRAME_CONTINUATION_FRAME = 2, // [CL0] frame to continue in
  FRAME_ALTERNATIVE = 3,        // [BP]  next clause to try on failure
  FRAME_GLOBAL_MARK = 4,        // [G0]  global stack top at the choice point
  FRAME_PREVIOUS_CHOICE = 5,    // [BL]  previous choice point frame
  FRAME_TRAIL_MARK = 6,         // [TR0] trail top at the choice point
  FRAME_CLAUSE = 7,             // [XC]  clause running in this frame
  FRAME_ARGUMENTS = 8,
};

#define KEY_ANY ((word_t)0)
#define KEY_CONS ((word_t)TAG_CONS)

typedef struct zip_procedure zip_procedure_t;
typedef struct zip_clause zip_clause_t;

typedef union {
  word_t value;
  const zip_procedure_t *procedure;
} zip_external_reference_t;

struct zip_clause {
  const uint8_t *code;
  const zip_external_reference_t *external_references;
  word_t key;
  const zip_procedure_t *procedure;
  const zip_clause_t *next;
};

struct zip_procedure {
  const char *name;
  uint8_t arity;
  const zip_clause_t *first;
};

typedef enum { ZIP_HALT, ZIP_FAIL, ZIP_ERROR } zip_status_t;

typedef struct {
  zip_mode_t mode;
  word_t *data;
} zip_context_t;

#define ZIP_LOCAL_STACK_WORDS 4096
#define ZIP_GLOBAL_STACK_WORDS 16384
#define ZIP_TRAIL_WORDS 4096
#define ZIP_SCRATCHPAD_DEPTH 256

typedef struct {
  const uint8_t *program_counter; // [PC]
  zip_mode_t mode;                // [PM]
  const zip_clause_t *clause;     // [XC]
  word_t *data;                   // [D]  cell the next instruction works on
  word_t *callee_frame;           // [L]  frame being built for the next call
  word_t *current_frame;          // [CL]
  word_t *global_top;             // [G]
  word_t *backtrack_frame;        // [BL] newest choice point, or NULL
  word_t **trail_top;             // [TR]
  zip_context_t *scratchpad_top;

  const char *error;

  word_t local_stack[ZIP_LOCAL_STACK_WORDS];
  word_t global_stack[ZIP_GLOBAL_STACK_WORDS];
  word_t *trail[ZIP_TRAIL_WORDS];
  zip_context_t scratchpad[ZIP_SCRATCHPAD_DEPTH];
} zip_machine_t;

void zip_initialize(zip_machine_t *m, const zip_clause_t *query);

zip_status_t zip_run(zip_machine_t *m);
zip_status_t zip_redo(zip_machine_t *m);

word_t zip_query_variable(const zip_machine_t *m, uint8_t slot);

word_t zip_dereference(word_t w);
