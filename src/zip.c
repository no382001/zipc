#include "zip.h"

#define DISPATCH(mode, opcode) (((uint32_t)(mode) << 6) | (uint32_t)(opcode))
#define ANY_MODE(opcode)                                                       \
  case DISPATCH(MODE_MATCH, opcode):                                           \
  case DISPATCH(MODE_COPY, opcode):                                            \
  case DISPATCH(MODE_ARGUMENT, opcode)

#define MAX_ARITY 255
#define UNIFY_DEPTH 256

const zip_opcode_info_t zip_opcodes[] = {
    {OPCODE_VOID, "void", 0, {0}},
    {OPCODE_VAR, "var", 1, {OPERAND_LOCAL}},
    {OPCODE_FIRSTVAR, "firstvar", 1, {OPERAND_LOCAL}},
    {OPCODE_POP, "pop", 0, {0}},
    {OPCODE_SKIPVAR, "skipvar", 0, {0}},
    {OPCODE_FUNCTOR, "functor", 2, {OPERAND_FUNCTOR, OPERAND_BYTE}},
    {OPCODE_LASTFUNCTOR, "lastfunctor", 2, {OPERAND_FUNCTOR, OPERAND_BYTE}},
    {OPCODE_CONSTANT, "constant", 1, {OPERAND_CONSTANT}},
    {OPCODE_ENTER, "enter", 1, {OPERAND_BYTE}},
    {OPCODE_RETURN, "return", 1, {OPERAND_BYTE}},
    {OPCODE_ARGMODE, "argmode", 1, {OPERAND_BYTE}},
    {OPCODE_DEPART, "depart", 2, {OPERAND_PROCEDURE, OPERAND_BYTE}},
    {OPCODE_CALL, "call", 1, {OPERAND_PROCEDURE}},
    {OPCODE_PROCEED, "proceed", 2, {OPERAND_PROCEDURE, OPERAND_BYTE}},
    {OPCODE_FAIL, "fail", 0, {0}},
    {OPCODE_CUT, "cut", 0, {0}},
    {OPCODE_IMMED, "immed", 1, {OPERAND_BYTE}},
    {OPCODE_GLOFIRVAR, "glofirvar", 1, {OPERAND_LOCAL}},
    {OPCODE_GLOVAR, "glovar", 1, {OPERAND_LOCAL}},
    {OPCODE_CONSLIST, "conslist", 0, {0}},
    {OPCODE_LASTCONSLIST, "lastconslist", 0, {0}},
    {OPCODE_CONSTNIL, "constnil", 0, {0}},
    {OPCODE_PUSHVAR, "pushvar", 1, {OPERAND_LOCAL}},
    {OPCODE_PUSHIMMED, "pushimmed", 1, {OPERAND_BYTE}},
    {OPCODE_PUSHCONST, "pushconst", 1, {OPERAND_CONSTANT}},
    {OPCODE_ADD, "add", 0, {0}},
    {OPCODE_SUB, "sub", 0, {0}},
    {OPCODE_ISVAR, "isvar", 1, {OPERAND_LOCAL}},
    {OPCODE_ISFIRST, "isfirst", 1, {OPERAND_LOCAL}},
    {OPCODE_ISVOID, "isvoid", 0, {0}},
    {OPCODE_LT, "lt", 0, {0}},
    {OPCODE_LE, "le", 0, {0}},
    {OPCODE_GT, "gt", 0, {0}},
    {OPCODE_GE, "ge", 0, {0}},
    {OPCODE_EQ, "eq", 0, {0}},
    {OPCODE_NE, "ne", 0, {0}},
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

static bool is_local(const zip_machine_t *m, const word_t *p) {
  return p >= m->local_stack && p < m->local_stack + ZIP_LOCAL_STACK_WORDS;
}

// Whether the variable at p is older than the newest choice point. Frames
// made since lie above the choice point frame, global cells above its mark.
static bool older_than_choice(const zip_machine_t *m, const word_t *p) {
  word_t *b = m->backtrack_frame;
  return b != NULL &&
         (is_local(m, p) ? p < b : p < (word_t *)b[FRAME_GLOBAL_MARK]);
}

static bool bind(zip_machine_t *m, word_t *variable, word_t value) {
  *variable = value;
  // only variables older than the newest choice point need undoing.
  if (older_than_choice(m, variable)) {
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
  word_t pending[2 * UNIFY_DEPTH]; // TODO move this to ctx
  size_t n = 0;

  for (;;) {
    a = zip_dereference(a);
    b = zip_dereference(b);
    if (a != b) {
      if (TAG(a) == TAG_REFERENCE && TAG(b) == TAG_REFERENCE) {
        // a frame variable is bound to a global one, so nothing global
        // points into a frame; otherwise the younger is bound to the older,
        // which needs no trailing and leaves no pointer into a newer frame.
        bool la = is_local(m, POINTER(a)), lb = is_local(m, POINTER(b));
        if (la != lb ? lb : POINTER(a) < POINTER(b)) { // bind b
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
      } else if (TAG(a) == TAG_COMPOUND && TAG(b) == TAG_COMPOUND) {
        // a cons cell is a head and a tail, a structure a functor and its
        // arguments; the functors are compared like any other word.
        word_t *pa = POINTER(a), *pb = POINTER(b);
        size_t first = 0, size = 2;
        if (IS_FUNCTOR(pa[0]) || IS_FUNCTOR(pb[0])) {
          if (pa[0] != pb[0])
            return false;
          first = 1;
          size = FUNCTOR_ARITY(pa[0]) + 1;
        }
        if (2 * (size - first - 1) > 2 * UNIFY_DEPTH - n) {
          m->error = "unify: term nested too deeply";
          return false;
        }
        for (size_t i = size - 1; i > first; i--) {
          pending[n++] = pa[i];
          pending[n++] = pb[i];
        }
        a = pa[first];
        b = pb[first];
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

// Moves the unbound frame variable *w to a new global cell, and makes *w a
// reference to it.
static bool globalize(zip_machine_t *m, word_t *w) {
  word_t *p = new_global(m, 1);
  if (p == NULL)
    return false;
  *p = MAKE_REFERENCE(p);
  if (!bind(m, POINTER(*w), MAKE_REFERENCE(p)))
    return false;
  *w = MAKE_REFERENCE(p);
  return true;
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
  if (TAG(argument) == TAG_COMPOUND)
    return key == (IS_STRUCTURE(argument) ? POINTER(argument)[0] : KEY_CONS);
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

  // This is also the choice point a cut in this frame goes back to.
  f[FRAME_PREVIOUS_CHOICE] = (word_t)m->backtrack_frame;
  const zip_clause_t *alternative = next_match(c->next, argument);
  if (alternative != NULL) {
    f[FRAME_ALTERNATIVE] = (word_t)alternative;
    f[FRAME_GLOBAL_MARK] = (word_t)m->global_top;
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
  f[FRAME_PREVIOUS_CHOICE] = 0;
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

// Tags r as an integer word; false, with m->error set, if it does not fit.
static bool make_integer(zip_machine_t *m, intptr_t r, word_t *w) {
  *w = MAKE_INTEGER(r);
  if (INTEGER_VALUE(*w) != r) {
    m->error = "integer overflow";
    return false;
  }
  return true;
}

zip_status_t zip_run(zip_machine_t *m) {
  intptr_t stack[ZIP_ARITHMETIC_DEPTH];
  int sp = 0;
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

    case DISPATCH(MODE_MATCH, OPCODE_VOID):
      m->data++;
      break;
    case DISPATCH(MODE_COPY, OPCODE_VOID): {
      word_t *p = m->data++;
      *p = MAKE_REFERENCE(p);
      break;
    }
    case DISPATCH(MODE_ARGUMENT, OPCODE_VOID): {
      word_t *p = new_global(m, 1);
      if (p == NULL)
        goto fail;
      *p = MAKE_REFERENCE(p);
      *m->data++ = MAKE_REFERENCE(p);
      break;
    }

    case DISPATCH(MODE_MATCH, OPCODE_FIRSTVAR):
    case DISPATCH(MODE_MATCH, OPCODE_GLOFIRVAR):
      m->current_frame[*m->program_counter++] = *m->data++;
      break;
    case DISPATCH(MODE_COPY, OPCODE_FIRSTVAR):
    case DISPATCH(MODE_COPY, OPCODE_GLOFIRVAR): {
      word_t *p = m->data++;
      *p = MAKE_REFERENCE(p);
      m->current_frame[*m->program_counter++] = MAKE_REFERENCE(p);
      break;
    }
    // A variable first met in a goal lives in its slot in this frame.
    case DISPATCH(MODE_ARGUMENT, OPCODE_FIRSTVAR): {
      word_t *p = &m->current_frame[*m->program_counter++];
      *p = MAKE_REFERENCE(p);
      *m->data++ = MAKE_REFERENCE(p);
      break;
    }
    // The last goal may take over this frame, so its variables go global.
    case DISPATCH(MODE_ARGUMENT, OPCODE_GLOFIRVAR): {
      word_t *p = new_global(m, 1);
      if (p == NULL)
        goto fail;
      *p = MAKE_REFERENCE(p);
      m->current_frame[*m->program_counter++] = *m->data++ = MAKE_REFERENCE(p);
      break;
    }

    case DISPATCH(MODE_MATCH, OPCODE_VAR):
    case DISPATCH(MODE_MATCH, OPCODE_GLOVAR):
      if (!unify(m, m->current_frame[*m->program_counter++], *m->data++))
        goto fail;
      break;
    case DISPATCH(MODE_ARGUMENT, OPCODE_VAR):
      *m->data++ = m->current_frame[*m->program_counter++];
      break;
    // A structure is global, so it must not point to a frame variable.
    case DISPATCH(MODE_COPY, OPCODE_VAR):
    case DISPATCH(MODE_COPY, OPCODE_GLOVAR):
      c = zip_dereference(m->current_frame[*m->program_counter++]);
      if (TAG(c) == TAG_REFERENCE && is_local(m, POINTER(c)) &&
          !globalize(m, &c))
        goto fail;
      *m->data++ = c;
      break;
    // Only a variable of this frame is unsafe: older frames outlive the call.
    case DISPATCH(MODE_ARGUMENT, OPCODE_GLOVAR):
      c = zip_dereference(m->current_frame[*m->program_counter++]);
      if (TAG(c) == TAG_REFERENCE && POINTER(c) >= m->current_frame &&
          is_local(m, POINTER(c)) && !globalize(m, &c))
        goto fail;
      *m->data++ = c;
      break;

    case DISPATCH(MODE_MATCH, OPCODE_CONSLIST):
      push = true;
      goto match_cons;
    case DISPATCH(MODE_MATCH, OPCODE_LASTCONSLIST):
      push = false;
    match_cons: {
      word_t t = zip_dereference(*m->data);
      if (TAG(t) == TAG_COMPOUND && !IS_STRUCTURE(t)) {
        if (push && !push_context(m))
          goto fail;
        m->data = POINTER(t);
      } else if (TAG(t) == TAG_REFERENCE) {
        word_t *p = new_global(m, 2);
        if (p == NULL || !bind(m, POINTER(t), MAKE_COMPOUND(p)))
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

    case DISPATCH(MODE_MATCH, OPCODE_FUNCTOR):
      push = true;
      goto match_structure;
    case DISPATCH(MODE_MATCH, OPCODE_LASTFUNCTOR):
      push = false;
    match_structure: {
      c = m->clause->external_references[*m->program_counter++].value;
      uint8_t arity = *m->program_counter++;
      word_t t = zip_dereference(*m->data);
      if (TAG(t) == TAG_COMPOUND && POINTER(t)[0] == c) {
        if (push && !push_context(m))
          goto fail;
        m->data = POINTER(t) + 1;
      } else if (TAG(t) == TAG_REFERENCE) {
        word_t *p = new_global(m, (size_t)arity + 1);
        if (p == NULL || !bind(m, POINTER(t), MAKE_COMPOUND(p)))
          goto fail;
        if (push && !push_context(m))
          goto fail;
        p[0] = c;
        m->data = p + 1;
        m->mode = MODE_COPY;
      } else {
        goto fail;
      }
      break;
    }
    case DISPATCH(MODE_COPY, OPCODE_FUNCTOR):
    case DISPATCH(MODE_ARGUMENT, OPCODE_FUNCTOR):
      push = true;
      goto build_structure;
    case DISPATCH(MODE_COPY, OPCODE_LASTFUNCTOR):
    case DISPATCH(MODE_ARGUMENT, OPCODE_LASTFUNCTOR):
      push = false;
    build_structure: {
      c = m->clause->external_references[*m->program_counter++].value;
      uint8_t arity = *m->program_counter++;
      word_t *p = new_global(m, (size_t)arity + 1);
      if (p == NULL)
        goto fail;
      p[0] = c;
      *m->data = MAKE_COMPOUND(p);
      if (push && !push_context(m))
        goto fail;
      m->data = p + 1;
      m->mode = MODE_COPY;
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
      *m->data = MAKE_COMPOUND(p);
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

      ANY_MODE(OPCODE_PUSHVAR) : {
        word_t w = zip_dereference(m->current_frame[*m->program_counter++]);
        if (TAG(w) != TAG_INTEGER) {
          m->error = TAG(w) == TAG_REFERENCE ? "instantiation error"
                                             : "type error: evaluable";
          return ZIP_ERROR;
        }
        c = (word_t)INTEGER_VALUE(w);
        goto push;
      }
      ANY_MODE(OPCODE_PUSHIMMED) : c = *m->program_counter++;
      goto push;
      ANY_MODE(OPCODE_PUSHCONST)
          : c = (word_t)INTEGER_VALUE(
                m->clause->external_references[*m->program_counter++].value);
    push:
      if (sp == ZIP_ARITHMETIC_DEPTH) {
        m->error = "arithmetic stack overflow";
        return ZIP_ERROR;
      }
      stack[sp++] = (intptr_t)c;
      break;

      ANY_MODE(OPCODE_ADD) : ANY_MODE(OPCODE_SUB) : {
        intptr_t r;
        bool overflow =
            opcode == OPCODE_ADD
                ? __builtin_add_overflow(stack[sp - 2], stack[sp - 1], &r)
                : __builtin_sub_overflow(stack[sp - 2], stack[sp - 1], &r);
        if (overflow) {
          m->error = "integer overflow";
          return ZIP_ERROR;
        }
        stack[--sp - 1] = r;
        break;
      }

      ANY_MODE(OPCODE_ISVAR) : {
        if (!make_integer(m, stack[--sp], &c))
          return ZIP_ERROR;
        if (!unify(m, m->current_frame[*m->program_counter++], c))
          goto fail;
        break;
      }
      ANY_MODE(OPCODE_ISFIRST)
          : if (!make_integer(m, stack[--sp], &c)) return ZIP_ERROR;
      m->current_frame[*m->program_counter++] = c;
      break;
      ANY_MODE(OPCODE_ISVOID) : sp--;
      break;

      ANY_MODE(OPCODE_LT) : ANY_MODE(OPCODE_LE) : ANY_MODE(OPCODE_GT)
          : ANY_MODE(OPCODE_GE) : ANY_MODE(OPCODE_EQ) : ANY_MODE(OPCODE_NE) : {
        intptr_t a = stack[sp - 2], b = stack[sp - 1];
        sp -= 2;
        bool holds;
        switch (opcode) {
        case OPCODE_LT:
          holds = a < b;
          break;
        case OPCODE_LE:
          holds = a <= b;
          break;
        case OPCODE_GT:
          holds = a > b;
          break;
        case OPCODE_GE:
          holds = a >= b;
          break;
        case OPCODE_EQ:
          holds = a == b;
          break;
        default:
          holds = a != b;
          break;
        }
        if (!holds)
          goto fail;
        break;
      }

      // Between goals, after a neck: the next goal's frame may now go lower.
      ANY_MODE(OPCODE_CUT)
          : m->backtrack_frame =
                (word_t *)m->current_frame[FRAME_PREVIOUS_CHOICE];
      goto body;

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
