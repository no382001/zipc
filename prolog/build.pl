:- module(build, [build/4, assemble/2]).

:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(pairs)).
:- use_module(library(dcgs)).
:- use_module(library(lambda)).
:- use_module('../build/gen/gen').
:- use_module(log).
:- use_module(consult).
:- use_module(compile).
:- use_module(assemble).
:- use_module(dump).

% Compiles a file of clauses and ?- queries with compile.pl, then writes the
% image with assemble.pl. The command line is in cli.pl.

%% build(+Source, +Dump, +Color, +Image) is det.
%  Reads the program in the file Source once, prints its listing if Dump is
%  true, and writes its image to Image unless that is none. Throws on a file
%  it cannot read or compile, and as check_defined/2 does.
build(Source, Dump, Color, Image) :-
    read_file(Source, Clauses, Goals),
    length(Clauses, NC), length(Goals, NQ),
    step("compile", "~d clauses, ~d queries", [NC, NQ]),
    (   Dump == true -> dump_program(Clauses, Goals, Color) ; true ),
    (   Image == none -> true
    ;   maplist(\ (C-_)^compile_clause(C), Clauses, Pairs),
        group_pairs_by_key(Pairs, Procedures), % the clauses of a procedure must be together
        maplist(compile_goal, Goals, Queries),
        write_image(Procedures, Queries, Image)
    ).

%% assemble(+Asm, +Image) is det.
%  Writes the image for the hand-written code in the file Asm, its
%  zip_procedure/2 and zip_query/3 facts, to the file Image. Throws like
%  build/4.
assemble(Asm, Image) :-
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

write_image(Procedures, Queries, Image) :-
    check_defined(Procedures, Queries),
    step("write", "~a", [Image]),
    generate(Procedures, Queries, Image).

%% check_defined(+Procedures, +Queries) is det.
%  Throws error(existence_error(procedures, Undefined), check_defined/2) if
%  the code calls procedures that are not defined. Undefined are P-From, From
%  the procedure or query that calls P, as chars.
check_defined(Procedures, Queries) :-
    phrase((procedures_calls(Procedures), queries_calls(Queries)), Calls0),
    sort(Calls0, Calls),
    length(Calls, NC),
    step("check", "~d calls", [NC]),
    pairs_keys(Procedures, Defined),
    findall(P-From, (member(P-From, Calls), \+ memberchk(P, Defined)), Undefined),
    (   Undefined == [] -> true
    ;   throw(error(existence_error(procedures, Undefined), check_defined/2))
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
