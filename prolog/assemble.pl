:- module(assemble, [generate/3]).

:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(dcgs)).
:- use_module(library(pairs)).
:- use_module(library(lambda)).
:- use_module('../build/gen/gen').
:- use_module(encode).

%%%% Entry

%% generate(+Procedures, +Queries, +File) is det.
%  Writes the image to File. Procedures are Func/Arity-Clauses, Queries are
%  zip_query(Text, Names, Instrs); either list may be empty.
generate(Procedures, ZipQueries, File) :-
    maplist(\ (zip_query(T, Vs, Is))^query(T, Vs, Is)^true, ZipQueries, Queries),
    phrase(image(Procedures, Queries), Bytes),
    open(File, write, S, [type(binary)]),
    maplist(put_byte(S), Bytes),
    close(S).

%%%% Image
% image//2 describes the bytes of the image, in the format documented in
% src/image.h.

image(Procedures, Queries) -->
    { gen:image_magic(Magic),
      gen:image_version(Version),
      pairs_keys(Procedures, Names),
      length(Procedures, NP),
      length(Queries, NQ) },
    seq(Magic), [Version], encode:u8(NP), encode:u8(NQ),
    procedures(Procedures, Names),
    queries(Queries, Names).

procedures([], _) --> [].
procedures([Name/Arity-Clauses|Ps], Names) -->
    { atom_chars(Name, Cs),
      length(Clauses, N) },
    encode:string(Cs), encode:u8(Arity), encode:u8(N),
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
key(N) --> { integer(N) }, term(integer), encode:i32(N).
key(K) -->
    { \+ memberchk(K, [any, nil, cons]), \+ integer(K),
      throw(error(domain_error(zip_key, K), key//1)) }.

queries([], _) --> [].
queries([query(Text, Variables, Instructions)|Qs], Names) -->
    { length(Variables, N) },
    encode:string(Text), encode:u8(N), encode:strings(Variables),
    code(Instructions, Names),
    queries(Qs, Names).

%%%% Code

% The instructions are assembled first because that fills the external
% reference table, which comes before them in the image.
code(Instructions, Names) -->
    { phrase(instructions(Instructions, Names, [], References), Bytes),
      length(References, NR),
      length(Bytes, NB) },
    encode:u8(NR), references(References, Names),
    encode:u16(NB), seq(Bytes).

instructions([], _, References, References) --> [].
instructions([I|Is], Names, References0, References) -->
    instruction(I, Names, References0, References1),
    instructions(Is, Names, References1, References).

instruction(I, Names, References0, References) -->
    { I =.. [Mnemonic|Operands],
      (   gen:opcode(Mnemonic, Opcode, Kinds) -> true
      ;   throw(error(existence_error(zip_instruction, I), instruction//3))
      ),
      length(Kinds, N),
      (   length(Operands, N) -> true
      ;   throw(error(domain_error(operand_count(Mnemonic, N), I), instruction//3))
      ) },
    [Opcode],
    operands(Kinds, Operands, Names, References0, References).

operands([], [], _, References, References) --> [].
operands([K|Ks], [O|Os], Names, References0, References) -->
    operand(K, O, Names, References0, References1),
    operands(Ks, Os, Names, References1, References).

operand(byte, X, _, References, References) --> { encode:must_be_byte(X) }, [X].
operand(local, X, _, References, References) --> { encode:must_be_byte(X) }, [X].
operand(procedure, P, Names, References0, References) -->
    { (   memberchk(P, Names) -> true
      ;   throw(error(existence_error(procedure, P), instruction//3))
      ),
      reference_slot(procedure(P), Slot, References0, References) },
    [Slot].
operand(constant, C, _, References0, References) -->
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
    encode:must_be_byte(Slot).

references([], _) --> [].
references([R|Rs], Names) --> reference(R, Names), references(Rs, Names).

reference(procedure(P), Names) --> { nth0(I, Names, P) }, term(procedure), encode:u8(I).
reference(constant([]), _) --> term(nil).
reference(constant(N), _) --> { integer(N) }, term(integer), encode:i32(N).

%%%% Encoding

term(Name) --> { gen:image_term(Name, Tag) }, [Tag].
