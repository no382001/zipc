#include "zip.h"

#define DISPATCH(mode, opcode) (((uint32_t)(mode) << 6) | (uint32_t)(opcode))
#define ANY_MODE(opcode)                                                       \
  case DISPATCH(MODE_MATCH, opcode):                                           \
  case DISPATCH(MODE_COPY, opcode):                                            \
  case DISPATCH(MODE_ARGUMENT, opcode)

#define MAX_ARITY 255
#define UNIFY_DEPTH 256

const zip_opcode_info_t zip_opcodes[] = {
    {OPCODE_VAR, "var", 1, {OPERAND_LOCAL}},
    {OPCODE_FIRSTVAR, "firstvar", 1, {OPERAND_LOCAL}},
    {OPCODE_POP, "pop", 0, {0}},
    {OPCODE_SKIPVAR, "skipvar", 0, {0}},
    {OPCODE_CONSTANT, "constant", 1, {OPERAND_CONSTANT}},
    {OPCODE_ENTER, "enter", 1, {OPERAND_BYTE}},
    {OPCODE_RETURN, "return", 1, {OPERAND_BYTE}},
    {OPCODE_ARGMODE, "argmode", 1, {OPERAND_BYTE}},
    {OPCODE_DEPART, "depart", 2, {OPERAND_PROCEDURE, OPERAND_BYTE}},
    {OPCODE_CALL, "call", 1, {OPERAND_PROCEDURE}},
    {OPCODE_PROCEED, "proceed", 2, {OPERAND_PROCEDURE, OPERAND_BYTE}},
    {OPCODE_FAIL, "fail", 0, {0}},
    {OPCODE_IMMED, "immed", 1, {OPERAND_BYTE}},
    {OPCODE_CONSLIST, "conslist", 0, {0}},
    {OPCODE_LASTCONSLIST, "lastconslist", 0, {0}},
    {OPCODE_CONSTNIL, "constnil", 0, {0}},
    {OPCODE_HALT, "halt", 0, {0}},
};

const size_t zip_opcode_count = sizeof zip_opcodes / sizeof zip_opcodes[0];

word_t zip_dereference(word_t w) {
  while (TAG(w) == TAG_REFERENCE) {
    word_t v = *POINTER(w);
    if (v == w)
      break;
    w = v;
  }
  return w;
}

static word_t *new_global(zip_machine_t *m, size_t count) {
  if ((size_t)(m->global_stack + ZIP_GLOBAL_STACK_WORDS - m->global_top) <
      count) {
    m->error = "global stack overflow";
    return NULL;
  }
  word_t *p = m->global_top;
  m->global_top += count;
  return p;
}

static bool bind(zip_machine_t *m, word_t *variable, word_t value) {
  *variable = value;
  // only variables older than the newest choice point need undoing.
  if (m->backtrack_frame != NULL &&
      variable < (word_t *)m->backtrack_frame[FRAME_GLOBAL_MARK]) {
    if (m->trail_top == m->trail + ZIP_TRAIL_WORDS) {
      m->error = "trail overflow";
      return false;
    }
    *m->trail_top++ = variable;
  }
  return true;
}

// returns true on success, false on failure or error
static bool unify(zip_machine_t *m, word_t a, word_t b) {
  word_t pending[2 * UNIFY_DEPTH];
  size_t n = 0;

  for (;;) {
    a = zip_dereference(a);
    b = zip_dereference(b);
    if (a != b) {
      if (TAG(a) == TAG_REFERENCE && TAG(b) == TAG_REFERENCE) {
        // bind the younger variable to the older one
        // bc of conditional trailing
        // and every variable is global now!
        if (POINTER(a) < POINTER(b)) {
          if (!bind(m, POINTER(b), a))
            return false;
        } else if (!bind(m, POINTER(a), b)) {
          return false;
        }
      } else if (TAG(a) == TAG_REFERENCE) {
        if (!bind(m, POINTER(a), b))
          return false;
      } else if (TAG(b) == TAG_REFERENCE) {
        if (!bind(m, POINTER(b), a))
          return false;
      } else if (TAG(a) == TAG_CONS && TAG(b) == TAG_CONS) {
        if (n == 2 * UNIFY_DEPTH) {
          m->error = "unify: term nested too deeply";
          return false;
        }
        pending[n++] = POINTER(a)[1];
        pending[n++] = POINTER(b)[1];
        a = POINTER(a)[0];
        b = POINTER(b)[0];
        continue;
      } else {
        return false;
      }
    }
    if (n == 0)
      return true;
    b = pending[--n];
    a = pending[--n];
  }
}

static bool push_context(zip_machine_t *m) {
  if (m->scratchpad_top == m->scratchpad + ZIP_SCRATCHPAD_DEPTH) {
    m->error = "scratchpad stack overflow";
    return false;
  }
  m->scratchpad_top->mode = m->mode;
  m->scratchpad_top->data = m->data + 1;
  m->scratchpad_top++;
  return true;
}

static bool key_matches(word_t key, word_t argument) {
  if (key == KEY_ANY || TAG(argument) == TAG_REFERENCE)
    return true;
  if (TAG(argument) == TAG_CONS)
    return key == KEY_CONS;
  return key == argument;
}

static const zip_clause_t *next_match(const zip_clause_t *c, word_t argument) {
  for (; c != NULL; c = c->next)
    if (key_matches(c->key, argument))
      return c;
  return NULL;
}

// Start the first clause from c on that matches the goal in frame f. Looks
// ahead for a second candidate (Clocksin 1984, section 7): only if there is
// one does f become a choice point.
static bool enter_procedure(zip_machine_t *m, word_t *f,
                            const zip_clause_t *c) {
  const zip_procedure_t *procedure = c->procedure;
  // A word tagged REFERENCE matches every key, which is right for arity 0.
  word_t argument = procedure->arity > 0 ? zip_dereference(f[FRAME_ARGUMENTS])
                                         : (word_t)TAG_REFERENCE;

  c = next_match(c, argument);
  if (c == NULL)
    return false;

  const zip_clause_t *alternative = next_match(c->next, argument);
  if (alternative != NULL) {
    f[FRAME_ALTERNATIVE] = (word_t)alternative;
    f[FRAME_GLOBAL_MARK] = (word_t)m->global_top;
    f[FRAME_PREVIOUS_CHOICE] = (word_t)m->backtrack_frame;
    f[FRAME_TRAIL_MARK] = (word_t)m->trail_top;
    m->backtrack_frame = f;
  }

  f[FRAME_SIZE] = FRAME_ARGUMENTS + procedure->arity;
  f[FRAME_CLAUSE] = (word_t)c;
  m->current_frame = f;
  m->clause = c;
  m->program_counter = c->code;
  m->mode = MODE_MATCH;
  m->data = f + FRAME_ARGUMENTS;
  m->scratchpad_top = m->scratchpad;
  return true;
}

static bool backtrack(zip_machine_t *m) {
  while (m->backtrack_frame != NULL) {
    word_t *f = m->backtrack_frame;

    while (m->trail_top > (word_t **)f[FRAME_TRAIL_MARK]) {
      word_t *variable = *--m->trail_top;
      *variable = MAKE_REFERENCE(variable);
    }
    m->global_top = (word_t *)f[FRAME_GLOBAL_MARK];
    m->backtrack_frame = (word_t *)f[FRAME_PREVIOUS_CHOICE];
    if (enter_procedure(m, f, (const zip_clause_t *)f[FRAME_ALTERNATIVE]))
      return true;
  }
  return false;
}

// Lowest local stack address not used by the current frame or a choice point.
static word_t *frame_top(const zip_machine_t *m) {
  word_t *top = m->current_frame + m->current_frame[FRAME_SIZE];
  if (m->backtrack_frame != NULL) {
    word_t *b = m->backtrack_frame + m->backtrack_frame[FRAME_SIZE];
    if (b > top)
      top = b;
  }
  return top;
}

void zip_initialize(zip_machine_t *m, const zip_clause_t *query) {
  word_t *f = m->local_stack;

  f[FRAME_SIZE] = FRAME_ARGUMENTS;
  f[FRAME_CONTINUATION] = 0;
  f[FRAME_CONTINUATION_FRAME] = 0;
  f[FRAME_CLAUSE] = (word_t)query;

  m->program_counter = query->code;
  m->mode = MODE_ARGUMENT;
  m->clause = query;
  m->current_frame = f;
  m->callee_frame = f + FRAME_ARGUMENTS;
  m->data = m->callee_frame + FRAME_ARGUMENTS;
  m->global_top = m->global_stack;
  m->backtrack_frame = NULL;
  m->trail_top = m->trail;
  m->scratchpad_top = m->scratchpad;
  m->error = NULL;
}

word_t zip_query_variable(const zip_machine_t *m, uint8_t slot) {
  return m->local_stack[slot];
}

zip_status_t zip_run(zip_machine_t *m) {
  for (;;) {
    uint8_t opcode = *m->program_counter++;
    word_t c;
    bool push;

    switch (DISPATCH(m->mode, opcode)) {
    case DISPATCH(MODE_MATCH, OPCODE_CONSTNIL):
      c = ATOM_NIL;
      goto match_constant;
    case DISPATCH(MODE_MATCH, OPCODE_IMMED):
      c = MAKE_INTEGER(*m->program_counter++);
      goto match_constant;
    case DISPATCH(MODE_MATCH, OPCODE_CONSTANT):
      c = m->clause->external_references[*m->program_counter++].value;
    match_constant: {
      word_t t = zip_dereference(*m->data++);
      if (TAG(t) == TAG_REFERENCE) {
        if (!bind(m, POINTER(t), c))
          goto fail;
      } else if (t != c) {
        goto fail;
      }
      break;
    }
    case DISPATCH(MODE_COPY, OPCODE_CONSTNIL):
    case DISPATCH(MODE_ARGUMENT, OPCODE_CONSTNIL):
      *m->data++ = ATOM_NIL;
      break;
    case DISPATCH(MODE_COPY, OPCODE_IMMED):
    case DISPATCH(MODE_ARGUMENT, OPCODE_IMMED):
      *m->data++ = MAKE_INTEGER(*m->program_counter++);
      break;
    case DISPATCH(MODE_COPY, OPCODE_CONSTANT):
    case DISPATCH(MODE_ARGUMENT, OPCODE_CONSTANT):
      *m->data++ = m->clause->external_references[*m->program_counter++].value;
      break;

      ANY_MODE(OPCODE_SKIPVAR) : m->data++;
      break;

    case DISPATCH(MODE_MATCH, OPCODE_FIRSTVAR):
      m->current_frame[*m->program_counter++] = *m->data++;
      break;
    case DISPATCH(MODE_COPY, OPCODE_FIRSTVAR): {
      word_t *p = m->data++;
      *p = MAKE_REFERENCE(p);
      m->current_frame[*m->program_counter++] = MAKE_REFERENCE(p);
      break;
    }
    case DISPATCH(MODE_ARGUMENT, OPCODE_FIRSTVAR): {
      word_t *p = new_global(m, 1);
      if (p == NULL)
        goto fail;
      *p = MAKE_REFERENCE(p);
      m->current_frame[*m->program_counter++] = *m->data++ = MAKE_REFERENCE(p);
      break;
    }

    case DISPATCH(MODE_MATCH, OPCODE_VAR):
      if (!unify(m, m->current_frame[*m->program_counter++], *m->data++))
        goto fail;
      break;
    case DISPATCH(MODE_COPY, OPCODE_VAR):
    case DISPATCH(MODE_ARGUMENT, OPCODE_VAR):
      *m->data++ = m->current_frame[*m->program_counter++];
      break;

    case DISPATCH(MODE_MATCH, OPCODE_CONSLIST):
      push = true;
      goto match_cons;
    case DISPATCH(MODE_MATCH, OPCODE_LASTCONSLIST):
      push = false;
    match_cons: {
      word_t t = zip_dereference(*m->data);
      if (TAG(t) == TAG_CONS) {
        if (push && !push_context(m))
          goto fail;
        m->data = POINTER(t);
      } else if (TAG(t) == TAG_REFERENCE) {
        word_t *p = new_global(m, 2);
        if (p == NULL || !bind(m, POINTER(t), MAKE_CONS(p)))
          goto fail;
        if (push && !push_context(m))
          goto fail;
        m->data = p;
        m->mode = MODE_COPY;
      } else {
        goto fail;
      }
      break;
    }
    case DISPATCH(MODE_COPY, OPCODE_CONSLIST):
    case DISPATCH(MODE_ARGUMENT, OPCODE_CONSLIST):
      push = true;
      goto build_cons;
    case DISPATCH(MODE_COPY, OPCODE_LASTCONSLIST):
    case DISPATCH(MODE_ARGUMENT, OPCODE_LASTCONSLIST):
      push = false;
    build_cons: {
      word_t *p = new_global(m, 2);
      if (p == NULL)
        goto fail;
      *m->data = MAKE_CONS(p);
      if (push && !push_context(m))
        goto fail;
      m->data = p;
      m->mode = MODE_COPY;
      break;
    }

      ANY_MODE(OPCODE_POP) : if (m->scratchpad_top == m->scratchpad) {
        m->error = "pop with empty scratchpad stack";
        return ZIP_ERROR;
      }
      m->scratchpad_top--;
      m->mode = m->scratchpad_top->mode;
      m->data = m->scratchpad_top->data;
      break;

      ANY_MODE(OPCODE_RETURN)
          : m->current_frame[FRAME_SIZE] = *m->program_counter++;
      m->program_counter =
          (const uint8_t *)m->current_frame[FRAME_CONTINUATION];
      m->current_frame = (word_t *)m->current_frame[FRAME_CONTINUATION_FRAME];
      m->clause = (const zip_clause_t *)m->current_frame[FRAME_CLAUSE];
      goto body;
      ANY_MODE(OPCODE_ARGMODE)
          : ANY_MODE(OPCODE_ENTER)
          : m->current_frame[FRAME_SIZE] = *m->program_counter++;
    body:
      m->callee_frame = frame_top(m);
      if ((size_t)(m->callee_frame - m->local_stack) + FRAME_ARGUMENTS +
              MAX_ARITY >
          ZIP_LOCAL_STACK_WORDS) {
        m->error = "local stack overflow";
        return ZIP_ERROR;
      }
      m->mode = MODE_ARGUMENT;
      m->data = m->callee_frame + FRAME_ARGUMENTS;
      m->scratchpad_top = m->scratchpad;
      break;

      ANY_MODE(OPCODE_CALL) : {
        const zip_procedure_t *procedure =
            m->clause->external_references[*m->program_counter++].procedure;
        word_t *f = m->callee_frame;
        f[FRAME_CONTINUATION] = (word_t)m->program_counter;
        f[FRAME_CONTINUATION_FRAME] = (word_t)m->current_frame;
        if (!enter_procedure(m, f, procedure->first))
          goto fail;
        break;
      }
      ANY_MODE(OPCODE_PROCEED) : ANY_MODE(OPCODE_DEPART) : {
        const zip_procedure_t *procedure =
            m->clause->external_references[*m->program_counter++].procedure;
        uint8_t arity = *m->program_counter++;
        word_t *f;
        if (m->backtrack_frame == NULL ||
            m->backtrack_frame < m->current_frame) {
          // the callee takes over this frame.
          f = m->current_frame;
          for (uint8_t i = 0; i < arity; i++)
            f[FRAME_ARGUMENTS + i] = m->callee_frame[FRAME_ARGUMENTS + i];
        } else {
          f = m->callee_frame;
          f[FRAME_CONTINUATION] = m->current_frame[FRAME_CONTINUATION];
          f[FRAME_CONTINUATION_FRAME] =
              m->current_frame[FRAME_CONTINUATION_FRAME];
        }
        if (!enter_procedure(m, f, procedure->first))
          goto fail;
        break;
      }

      ANY_MODE(OPCODE_FAIL) : goto fail;

      ANY_MODE(OPCODE_HALT) : return ZIP_HALT;

    default:
      m->error = "illegal instruction";
      return ZIP_ERROR;
    }
    continue;

  fail:
    if (m->error != NULL)
      return ZIP_ERROR;
    if (!backtrack(m))
      return ZIP_FAIL;
  }
}

zip_status_t zip_redo(zip_machine_t *m) {
  if (!backtrack(m))
    return ZIP_FAIL;
  return zip_run(m);
}
