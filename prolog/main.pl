:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(pairs)).
:- use_module(library(charsio)).
:- use_module(library(lambda)).
:- use_module(library(os)).

% Compiles a file of clauses and ?- queries with compile.pl, then writes the
% image with assemble.pl. Run it through zipc, which loads the files.

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
%  Writes the image for the hand-written code in the file Asm to the file Image.
assemble(Asm, Image) :-
    catch(assemble_(Asm, Image), E, (format(user_error, "assemble: ~q~n", [E]), halt(1))).

assemble_(Asm, Image) :-
    step("load", "~a", [Asm]),
    consult(Asm),
    step("write", "~a", [Image]),
    generate(Image).

build(Source, Image) :-
    compile_file(Source),
    step("write", "~a", [Image]),
    generate(Image).

%% step(+Tag, +Format, +Args) is det.
%  Prints a progress line to stderr, in the same layout as the Makefile's.
step(Tag, Format, Args) :-
    format(user_error, "  ~s~t~12|", [Tag]),
    format(user_error, Format, Args),
    nl(user_error).

%% compile_file(+Source) is det.
%  Asserts zip_procedure/2 and zip_query/3 for the program in the file Source.
compile_file(Source) :-
    step("read", "~a", [Source]),
    read_file(Source, Clauses, Queries),
    length(Clauses, NC), length(Queries, NQ),
    step("compile", "~d clauses, ~d queries", [NC, NQ]),
    maplist(\ (C-_)^compile_clause(C), Clauses, Pairs),
    group_pairs_by_key(Pairs, Procedures), % the clauses of a procedure must be together
    maplist(\ (P-Cs)^assertz(zip_procedure(P, Cs)), Procedures),
    maplist(\ (zip_query(T, Vs, Is))^assertz(zip_query(T, Vs, Is)), Queries).

%% read_file(+Source, -Clauses, -Queries) is det.
%  Clauses are the clauses of the file as Clause-VariableNames, Queries its ?-
%  queries already compiled.
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
    ;   Clauses = [T-VNs|Clauses1],
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
