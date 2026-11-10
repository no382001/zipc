#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "zip.h"

// An image written by prolog/assemble.pl. The integers are little-endian.
//
//   image     = "ZIP" version:u8 atom_count:u16 name:string*
//               procedure_count:u16 query_count:u16 procedure* query*
//   procedure = name:string arity:u8 clause_count:u16 clause*
//   clause    = key:term code
//   query     = text:string variable_count:u8 name:string* code
//   code      = reference_count:u8 term* code_length:u16 byte*
//   term      = IMAGE_TERM_ANY | IMAGE_TERM_NIL | IMAGE_TERM_CONS
//             | IMAGE_TERM_INTEGER value:i32
//             | IMAGE_TERM_PROCEDURE procedure_index:u16
//             | IMAGE_TERM_ATOM atom_index:u16
//             | IMAGE_TERM_FUNCTOR atom_index:u16 arity:u8
//   string    = length:u16 byte* 0
//
// The names are those of atoms 1, 2, ...; atom 0 is [], and has no name in
// the image. A key is any, nil, cons, an integer, an atom or a functor. An
// external reference is nil, an integer, an atom, a functor or a procedure.

#define ZIP_IMAGE_MAGIC "ZIP"
#define ZIP_IMAGE_VERSION 4

typedef enum {
  IMAGE_TERM_ANY = 0,
  IMAGE_TERM_NIL = 1,
  IMAGE_TERM_CONS = 2,
  IMAGE_TERM_INTEGER = 3,
  IMAGE_TERM_PROCEDURE = 4,
  IMAGE_TERM_ATOM = 5,
  IMAGE_TERM_FUNCTOR = 6,
} zip_image_term_t;

#define ZIP_IMAGE_PROCEDURES 64
#define ZIP_IMAGE_CLAUSES 256
#define ZIP_IMAGE_REFERENCES 1024
#define ZIP_IMAGE_QUERIES 16
#define ZIP_IMAGE_ATOMS 256
#define ZIP_QUERY_VARIABLES 8

typedef struct {
  const char *text;
  zip_clause_t clause;
  uint8_t variable_count;
  const char *variables[ZIP_QUERY_VARIABLES]; // at frame offsets 8, 9, ...
} zip_query_t;

typedef struct {
  zip_procedure_t procedures[ZIP_IMAGE_PROCEDURES];
  zip_clause_t clauses[ZIP_IMAGE_CLAUSES];
  zip_external_reference_t references[ZIP_IMAGE_REFERENCES];
  zip_query_t queries[ZIP_IMAGE_QUERIES];
  const char *atoms[ZIP_IMAGE_ATOMS]; // atoms[0] is "[]"
  uint16_t atom_count;
  uint16_t procedure_count;
  uint16_t query_count;
  uint16_t clause_count;
  uint16_t reference_count;

  const char *error;
  size_t error_offset; // bytes read before the error was found
} zip_image_t;

bool zip_load(zip_image_t *image, const uint8_t *bytes, size_t length);
