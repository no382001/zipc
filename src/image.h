#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "zip.h"

// An image written by prolog/assemble.pl. The inntegers are little-endian.
//
//   image     = "ZIP" version:u8 procedure_count:u8 query_count:u8
//               procedure* query*
//   procedure = name:string arity:u8 clause_count:u8 clause*
//   clause    = key:term code
//   query     = text:string variable_count:u8 name:string* code
//   code      = reference_count:u8 term* code_length:u16 byte*
//   term      = IMAGE_TERM_ANY | IMAGE_TERM_NIL | IMAGE_TERM_CONS
//             | IMAGE_TERM_INTEGER value:i32
//             | IMAGE_TERM_PROCEDURE procedure_index:u8
//   string    = length:u8 byte* 0
//
// A key is any, nil, cons or an integer. An external reference is nil, an
// integer or a procedure

#define ZIP_IMAGE_MAGIC "ZIP"
#define ZIP_IMAGE_VERSION 1

typedef enum {
  IMAGE_TERM_ANY = 0,
  IMAGE_TERM_NIL = 1,
  IMAGE_TERM_CONS = 2,
  IMAGE_TERM_INTEGER = 3,
  IMAGE_TERM_PROCEDURE = 4,
} zip_image_term_t;

#define ZIP_IMAGE_PROCEDURES 64
#define ZIP_IMAGE_CLAUSES 256
#define ZIP_IMAGE_REFERENCES 1024
#define ZIP_IMAGE_QUERIES 16
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
  uint8_t procedure_count;
  uint8_t query_count;
  uint16_t clause_count;
  uint16_t reference_count;

  const char *error;
  size_t error_offset; // bytes read before the error was found
} zip_image_t;


bool zip_load(zip_image_t *image, const uint8_t *bytes, size_t length);
