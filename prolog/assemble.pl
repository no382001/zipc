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
      image_atoms(Procedures, Queries, Atoms),
      maplist(\A^Cs^atom_chars(A, Cs), Atoms, AtomNames),
      length(Atoms, NA),
      length(Procedures, NP),
      length(Queries, NQ) },
    seq(Magic), [Version],
    encode:u16(NA), encode:strings(AtomNames),
    encode:u16(NP), encode:u16(NQ),
    procedures(Procedures, Names-Atoms),
    queries(Queries, Names-Atoms).

%% image_atoms(+Procedures, +Queries, -Atoms) is det.
%  Atoms are the atoms the keys and constants use, but not [], in the order
%  they are first used. Atom I of the image is the Ith of them.
image_atoms(Procedures, Queries, Atoms) :-
    phrase((procedures_atoms(Procedures), queries_atoms(Queries)), Atoms0),
    first_occurrences(Atoms0, Atoms).

procedures_atoms([]) --> [].
procedures_atoms([_-Cs|Ps]) --> clauses_atoms(Cs), procedures_atoms(Ps).

clauses_atoms([]) --> [].
clauses_atoms([clause(Key, Is)|Cs]) -->
    (   { Key = atom(A) } -> [A]
    ;   { Key = functor(F/_), F \== [] } -> [F]
    ;   []
    ),
    instructions_atoms(Is),
    clauses_atoms(Cs).

queries_atoms([]) --> [].
queries_atoms([query(_, _, Is)|Qs]) --> instructions_atoms(Is), queries_atoms(Qs).

instructions_atoms([]) --> [].
instructions_atoms([I|Is]) -->
    (   { I = constant(A), atom(A), A \== [] } -> [A]
    ;   { I =.. [Op, F/_, _], memberchk(Op, [functor, lastfunctor]), F \== [] } -> [F]
    ;   []
    ),
    instructions_atoms(Is).

first_occurrences(Xs, Ys) :- first_occurrences(Xs, [], Ys).
first_occurrences([], _, []).
first_occurrences([X|Xs], Seen, Ys) :-
    (   memberchk(X, Seen) -> Ys = Ys1
    ;   Ys = [X|Ys1]
    ),
    first_occurrences(Xs, [X|Seen], Ys1).

atom_index(A, _-Atoms, I) :- nth1(I, Atoms, A), !.

% Atom 0 is [], which can name a functor aswell.
functor_atom_index(F, Tables, I) :- ( F == [] -> I = 0 ; atom_index(F, Tables, I) ).

procedures([], _) --> [].

procedures([Name/Arity-Clauses|Ps], Tables) -->
    { atom_chars(Name, Cs),
      length(Clauses, N) },
    encode:string(Cs), encode:u8(Arity), encode:u16(N),
    clauses(Clauses, Tables),
    procedures(Ps, Tables).

clauses([], _) --> [].
clauses([clause(Key, Instructions)|Cs], Tables) -->
    key(Key, Tables),
    code(Instructions, Tables),
    clauses(Cs, Tables).

key(any, _) --> term(any).
key(nil, _) --> term(nil).
key(cons, _) --> term(cons).
key(N, _) --> { integer(N) }, term(integer), encode:i32(N).
key(atom(A), Tables) --> { atom_index(A, Tables, I) }, term(atom), encode:u16(I).
key(functor(F/N), Tables) --> functor(F/N, Tables).
key(K, _) -->
    { \+ memberchk(K, [any, nil, cons]), \+ integer(K), K \= atom(_), K \= functor(_),
      throw(error(domain_error(zip_key, K), key//2)) }.

queries([], _) --> [].
queries([query(Text, Variables, Instructions)|Qs], Tables) -->
    { length(Variables, N) },
    encode:string(Text), encode:u8(N), encode:strings(Variables),
    code(Instructions, Tables),
    queries(Qs, Tables).

%%%% Code

% The instructions are assembled first because that fills the external
% reference table, which comes before them in the image.
code(Instructions, Tables) -->
    { phrase(instructions(Instructions, Tables, [], References), Bytes),
      length(References, NR),
      length(Bytes, NB) },
    encode:u8(NR), references(References, Tables),
    encode:u16(NB), seq(Bytes).

instructions([], _, References, References) --> [].
instructions([I|Is], Tables, References0, References) -->
    instruction(I, Tables, References0, References1),
    instructions(Is, Tables, References1, References).

instruction(I, Tables, References0, References) -->
    { I =.. [Mnemonic|Operands],
      (   gen:opcode(Mnemonic, Opcode, Kinds) -> true
      ;   throw(error(existence_error(zip_instruction, I), instruction//3))
      ),
      length(Kinds, N),
      (   length(Operands, N) -> true
      ;   throw(error(domain_error(operand_count(Mnemonic, N), I), instruction//3))
      ) },
    [Opcode],
    operands(Kinds, Operands, Tables, References0, References).

operands([], [], _, References, References) --> [].
operands([K|Ks], [O|Os], Tables, References0, References) -->
    operand(K, O, Tables, References0, References1),
    operands(Ks, Os, Tables, References1, References).

operand(byte, X, _, References, References) --> { encode:must_be_byte(X) }, [X].
operand(local, X, _, References, References) --> { encode:must_be_byte(X) }, [X].
operand(procedure, P, Tables, References0, References) -->
    { Tables = Names-_,
      (   memberchk(P, Names) -> true
      ;   throw(error(existence_error(procedure, P), instruction//3))
      ),
      reference_slot(procedure(P), Slot, References0, References) },
    [Slot].
operand(constant, C, _, References0, References) -->
    { (   (atom(C) ; integer(C)) -> true
      ;   throw(error(domain_error(zip_constant, C), instruction//3))
      ),
      reference_slot(constant(C), Slot, References0, References) },
    [Slot].
operand(functor, F/N, _, References0, References) -->
    { (   atom(F), integer(N), N >= 1, N =< 255 -> true
      ;   throw(error(domain_error(zip_functor, F/N), instruction//3))
      ),
      reference_slot(functor(F/N), Slot, References0, References) },
    [Slot].

reference_slot(R, Slot, References0, References) :-
    (   nth1(Slot, References0, R) -> References = References0
    ;   append(References0, [R], References),
        length(References, Slot)
    ),
    encode:must_be_byte(Slot).

references([], _) --> [].
references([R|Rs], Tables) --> reference(R, Tables), references(Rs, Tables).

reference(procedure(P), Names-_) --> { nth0(I, Names, P) }, term(procedure), encode:u16(I).
reference(constant([]), _) --> !, term(nil).
reference(constant(A), Tables) --> { atom(A), atom_index(A, Tables, I) }, term(atom), encode:u16(I).
reference(constant(N), _) --> { integer(N) }, term(integer), encode:i32(N).
reference(functor(F/N), Tables) --> functor(F/N, Tables).

functor(F/N, Tables) -->
    { functor_atom_index(F, Tables, I) }, term(functor), encode:u16(I), encode:u8(N).

%%%% Encoding

term(Name) --> { gen:image_term(Name, Tag) }, [Tag].
