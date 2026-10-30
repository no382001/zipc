:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(pairs)).
:- use_module(library(charsio)).
:- use_module(library(lambda)).

% Compiles a file of clauses and ?- queries with compile.pl, then writes the
% image with assemble.pl.
%   scryer-prolog -f prolog/compile.pl prolog/assemble.pl prolog/main.pl \
%       -g "main('test/concat.pl', 'build/gen/concat.bin')" -g halt

%% main(+Source, +Image) is det.
%  Writes the image for the program in the file Source to the file Image.
main(Source, Image) :-
    catch(build(Source, Image), E, (format(user_error, "main: ~q~n", [E]), halt(1))).

build(Source, Image) :-
    read_file(Source, Clauses, Queries),
    maplist(compile_clause, Clauses, Pairs),
    group_pairs_by_key(Pairs, Procedures), % the clauses of a procedure must be together
    maplist(\ (P-Cs)^assertz(zip_procedure(P, Cs)), Procedures),
    maplist(\ (zip_query(T, Vs, Is))^assertz(zip_query(T, Vs, Is)), Queries),
    generate(Image).

%% read_file(+Source, -Clauses, -Queries) is det.
%  Clauses are the clauses of the file, Queries its ?- queries already compiled.
read_file(Source, Clauses, Queries) :-
    open(Source, read, S),
    read_items(S, Clauses, Queries),
    close(S).

read_items(S, Clauses, Queries) :-
    read_term(S, T, [variable_names(VNs)]),
    (   T == end_of_file -> Clauses = [], Queries = []
    ;   T = (?- Goal) ->
        query_text(Goal, VNs, Text),
        compile_or_throw(compile_query(Text, Q), Goal),
        Queries = [Q|Queries1],
        read_items(S, Clauses, Queries1)
    ;   Clauses = [T|Clauses1],
        read_items(S, Clauses1, Queries)
    ).

%% query_text(+Goal, +VNs, -Text) is det.
%  Text is Goal as the VM prints it after ?-, with its variable names and the dot.
query_text(Goal, VNs, Text) :-
    write_term_to_chars(Goal, [quoted(true), variable_names(VNs)], Cs),
    append(Cs, ".", Text).

%% compile_clause(+Clause, -Pair) is det.
%  Pair is Func/Arity-clause(Key, Instrs), ready to group into procedures.
compile_clause(Clause, P-clause(Key, Instrs)) :-
    compile_or_throw(compile_procedure(Clause, procedure(P, Instrs)), Clause),
    clause_key(Clause, Key).

compile_or_throw(Goal, Term) :-
    (   call(Goal) -> true
    ;   throw(error(domain_error(compilable, Term), main/2))
    ).
