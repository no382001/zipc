:- module(main, [zipc/0, main/2, assemble/2]).

:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(pairs)).
:- use_module(library(dcgs)).
:- use_module(library(lambda)).
:- use_module(library(os)).
:- use_module('../build/gen/gen').
:- use_module(log).
:- use_module(consult).
:- use_module(compile).
:- use_module(assemble).
:- use_module(dump).

% The zipc command: compiles a file of clauses and ?- queries with compile.pl,
% then writes the image with assemble.pl.

zipc :-
    argv(Args0),
    (   select("--color", Args0, Args) -> Color = true ; Color = false, Args = Args0 ),
    zipc(Args, Color).

zipc(["-d", Source], Color) :- !, atom_chars(S, Source), dump(S, Color).
zipc(["-a", Asm, Image], _) :- !, atom_chars(A, Asm), atom_chars(I, Image), assemble(A, I).
zipc([Source, Image], _) :- !, atom_chars(S, Source), atom_chars(I, Image), main(S, I).
zipc(_, _) :-
    format(user_error, "usage: zipc FILE.pl IMAGE | zipc -d FILE.pl | zipc -a FILE.asm.pl IMAGE~n", []),
    halt(2).

%% main(+Source, +Image) is det.
%  Writes the image for the program in the file Source to the file Image.
main(Source, Image) :-
    catch(build(Source, Image), E, (format(user_error, "main: ~q~n", [E]), halt(1))).

%% assemble(+Asm, +Image) is det.
%  Writes the image for the hand-written code in the file Asm, its
%  zip_procedure/2 and zip_query/3 facts, to the file Image.
assemble(Asm, Image) :-
    catch(assemble_(Asm, Image), E, (format(user_error, "assemble: ~q~n", [E]), halt(1))).

assemble_(Asm, Image) :-
    step("load", "~a", [Asm]),
    read_terms(Asm, Ts),
    phrase(asm_procedures(Ts), Procedures),
    phrase(asm_queries(Ts), Queries),
    write_image(Procedures, Queries, Image).

asm_procedures([]) --> [].
asm_procedures([T-_|Ts]) -->
    (   { T = zip_procedure(P, Cs) } -> [P-Cs]
    ;   { T = zip_query(_, _, _) } -> []
    ;   { throw(error(domain_error(zip_fact, T), assemble/2)) }
    ),
    asm_procedures(Ts).

asm_queries([]) --> [].
asm_queries([T-_|Ts]) --> ( { T = zip_query(_, _, _) } -> [T] ; [] ), asm_queries(Ts).

build(Source, Image) :-
    read_file(Source, Clauses, Goals),
    length(Clauses, NC), length(Goals, NQ),
    step("compile", "~d clauses, ~d queries", [NC, NQ]),
    maplist(\ (C-_)^compile_clause(C), Clauses, Pairs),
    group_pairs_by_key(Pairs, Procedures), % the clauses of a procedure must be together
    maplist(compile_goal, Goals, Queries),
    write_image(Procedures, Queries, Image).

write_image(Procedures, Queries, Image) :-
    check_defined(Procedures, Queries),
    step("write", "~a", [Image]),
    generate(Procedures, Queries, Image).

%% check_defined(+Procedures, +Queries) is det.
%  Halts after listing every procedure that the code calls but that is not
%  defined, with the procedure or query that calls it.
check_defined(Procedures, Queries) :-
    phrase((procedures_calls(Procedures), queries_calls(Queries)), Calls0),
    sort(Calls0, Calls),
    length(Calls, NC),
    step("check", "~d calls", [NC]),
    pairs_keys(Procedures, Defined),
    findall(P-From, (member(P-From, Calls), \+ memberchk(P, Defined)), Undefined),
    (   Undefined == [] -> true
    ;   maplist(\ (P-From)^format(user_error, "undefined procedure ~w, called by ~s~n", [P, From]), Undefined),
        halt(1)
    ).

% The calls are P-From: the procedure P is called by From, a procedure name or
% a query, as chars.
procedures_calls([]) --> [].
procedures_calls([F-Cs|Ps]) -->
    { phrase(format_("~w", [F]), From) },
    clauses_calls(Cs, From),
    procedures_calls(Ps).

clauses_calls([], _) --> [].
clauses_calls([clause(_, Is)|Cs], From) --> instructions_calls(Is, From), clauses_calls(Cs, From).

queries_calls([]) --> [].
queries_calls([zip_query(T, _, Is)|Qs]) -->
    { append("?- ", T, From) },
    instructions_calls(Is, From),
    queries_calls(Qs).

instructions_calls([], _) --> [].
instructions_calls([I|Is], From) --> instruction_calls(I, From), instructions_calls(Is, From).

% The procedure operands of I; an unknown instruction is left to assemble.pl.
instruction_calls(I, From) -->
    { I =.. [M|Os] },
    (   { gen:opcode(M, _, Kinds) } -> operands_calls(Kinds, Os, From)
    ;   []
    ).

operands_calls([K|Ks], [O|Os], From) --> !,
    (   { K == procedure } -> [O-From] ; [] ),
    operands_calls(Ks, Os, From).
operands_calls(_, _, _) --> [].
