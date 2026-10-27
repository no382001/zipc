:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(dcgs)).
:- use_module(library(charsio)).
:- use_module(library(pairs)).
:- use_module('../build/gen/gen').

% a program file may define no queries, or no procedures.
:- dynamic(zip_procedure/2).
:- dynamic(zip_query/3).

%%%% Entry

main :-
    catch(generate, E, (format(user_error, "zipasm: ~q~n", [E]), halt(1))).

generate :-
    findall(P-Cs, zip_procedure(P, Cs), Procedures),
    findall(query(T, Vs, Is), zip_query(T, Vs, Is), Queries),
    phrase(image(Procedures, Queries), Bytes),
    open('zipd.bin', write, S, [type(binary)]),
    maplist(put_byte(S), Bytes),
    close(S).

%%%% Image
% image//2 describes the bytes of the image, in the format documented in
% src/image.h.

image(Procedures, Queries) -->
    { image_magic(Magic),
      image_version(Version),
      pairs_keys(Procedures, Names),
      length(Procedures, NP),
      length(Queries, NQ) },
    seq(Magic), [Version], u8(NP), u8(NQ),
    procedures(Procedures, Names),
    queries(Queries, Names).

procedures([], _) --> [].
procedures([Name/Arity-Clauses|Ps], Names) -->
    { atom_chars(Name, Cs),
      length(Clauses, N) },
    string(Cs), u8(Arity), u8(N),
    clauses(Clauses, Names),
    procedures(Ps, Names).

clauses([], _) --> [].
clauses([clause(Key, Instructions)|Cs], Names) -->
    key(Key),
    code(Instructions, Names),
    clauses(Cs, Names).

key(any) --> term(any).
key(nil) --> term(nil).
key(cons) --> term(cons).
key(N) --> { integer(N) }, term(integer), i32(N).
key(K) -->
    { \+ memberchk(K, [any, nil, cons]), \+ integer(K),
      throw(error(domain_error(zip_key, K), key//1)) }.

queries([], _) --> [].
queries([query(Text, Variables, Instructions)|Qs], Names) -->
    { length(Variables, N) },
    string(Text), u8(N), strings(Variables),
    code(Instructions, Names),
    queries(Qs, Names).

%%%% Code

% The instructions are assembled first because that fills the external
% reference table, which comes before them in the image.
code(Instructions, Names) -->
    { phrase(instructions(Instructions, [], References), Bytes),
      length(References, NR),
      length(Bytes, NB) },
    u8(NR), references(References, Names),
    u16(NB), seq(Bytes).

instructions([], References, References) --> [].
instructions([I|Is], References0, References) -->
    instruction(I, References0, References1),
    instructions(Is, References1, References).

instruction(I, References0, References) -->
    { I =.. [Mnemonic|Operands],
      (   opcode(Mnemonic, Opcode, Kinds) -> true
      ;   throw(error(existence_error(zip_instruction, I), instruction//3))
      ),
      length(Kinds, N),
      (   length(Operands, N) -> true
      ;   throw(error(domain_error(operand_count(Mnemonic, N), I), instruction//3))
      ) },
    [Opcode],
    operands(Kinds, Operands, References0, References).

operands([], [], References, References) --> [].
operands([K|Ks], [O|Os], References0, References) -->
    operand(K, O, References0, References1),
    operands(Ks, Os, References1, References).

operand(byte, X, References, References) --> { must_be_byte(X) }, [X].
operand(local, X, References, References) --> { must_be_byte(X) }, [X].
operand(procedure, P, References0, References) -->
    { (   zip_procedure(P, _) -> true
      ;   throw(error(existence_error(procedure, P), instruction//3))
      ),
      reference_slot(procedure(P), Slot, References0, References) },
    [Slot].
operand(constant, C, References0, References) -->
    { (   (C == [] ; integer(C)) -> true
      ;   throw(error(domain_error(zip_constant, C), instruction//3))
      ),
      reference_slot(constant(C), Slot, References0, References) },
    [Slot].

reference_slot(R, Slot, References0, References) :-
    (   nth1(Slot, References0, R) -> References = References0
    ;   append(References0, [R], References),
        length(References, Slot)
    ),
    must_be_byte(Slot).

references([], _) --> [].
references([R|Rs], Names) --> reference(R, Names), references(Rs, Names).

reference(procedure(P), Names) --> { nth0(I, Names, P) }, term(procedure), u8(I).
reference(constant([]), _) --> term(nil).
reference(constant(N), _) --> { integer(N) }, term(integer), i32(N).

%%%% Encoding

term(Name) --> { image_term(Name, Tag) }, [Tag].

strings([]) --> [].
strings([S|Ss]) --> string(S), strings(Ss).

% A string is its UTF-8 length, its bytes and a terminating 0.
string(Cs) -->
    { chars_utf8bytes(Cs, Bs),
      (   memberchk(0, Bs) -> throw(error(domain_error(zip_string, Cs), string//1))
      ;   true
      ),
      length(Bs, N) },
    u8(N), seq(Bs), [0].

u8(N) --> { must_be_byte(N) }, [N].

must_be_byte(X) :-
    (   integer(X), X >= 0, X =< 255 -> true
    ;   throw(error(domain_error(byte, X), _))
    ).

u16(N) -->
    { (   integer(N), N >= 0, N =< 0xFFFF -> true
      ;   throw(error(domain_error(u16, N), u16//1))
      ),
      B0 is N /\ 0xFF,
      B1 is N >> 8 },
    [B0, B1].

% Two's complement, least significant byte first.
i32(N) -->
    { (   N >= -0x80000000, N =< 0x7FFFFFFF -> true
      ;   throw(error(domain_error(i32, N), i32//1))
      ),
      U is N /\ 0xFFFFFFFF,
      B0 is U /\ 0xFF,
      B1 is (U >> 8) /\ 0xFF,
      B2 is (U >> 16) /\ 0xFF,
      B3 is U >> 24 },
    [B0, B1, B2, B3].
