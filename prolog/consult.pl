:- module(consult, [read_file/3, read_terms/2]).

:- use_module(library(lists)).
:- use_module(library(dcgs)).
:- use_module(log).

% Reads source files, following :- consult(File) directives.

%% read_file(+Source, -Clauses, -Queries) is det.
%  Clauses are the clauses of the file as Clause-VariableNames, Queries the
%  goals of its ?- directives as Goal-VariableNames. A :- consult(File) directive reads the clauses of
%  File in its place, but not its queries; each file is read at most once.
read_file(Source, Clauses, Queries) :-
    step("read", "~a", [Source]),
    phrase(source(Source, main, [], _), Items),
    items_clauses_queries(Items, Clauses, Queries).

items_clauses_queries([], [], []).
items_clauses_queries([clause(C)|Is], [C|Cs], Qs) :- items_clauses_queries(Is, Cs, Qs).
items_clauses_queries([query(Q)|Is], Cs, [Q|Qs]) :- items_clauses_queries(Is, Cs, Qs).

% source(+Source, +Role, +Seen0, -Seen)// describes the clause(C) and query(Q)
% items of the file Source. Role is main or consulted; Seen are the files read
% so far.
source(Source, Role, Seen0, Seen) -->
    { read_terms(Source, Ts) },
    terms(Ts, Source, Role, [Source|Seen0], Seen).

terms([], _, _, Seen, Seen) --> [].
terms([T-VNs|Ts], Source, Role, Seen0, Seen) -->
    term(T, VNs, Source, Role, Seen0, Seen1),
    terms(Ts, Source, Role, Seen1, Seen).

term((:- consult(File)), _, Source, _, Seen0, Seen) --> !,
    { consulted_path(Source, File, Path) },
    (   { memberchk(Path, Seen0) } ->
        { step("consult", "~a (already read)", [Path]), Seen = Seen0 }
    ;   { step("consult", "~a", [Path]) },
        source(Path, consulted, Seen0, Seen)
    ).
term((:- Directive), _, _, _, _, _) --> !,
    { throw(error(domain_error(directive, Directive), read_file/3)) }.
term((?- Goal), VNs, _, Role, Seen, Seen) --> !,
    (   { Role == main } ->
        [query(Goal-VNs)]
    ;   []
    ).
term(Clause, VNs, _, _, Seen, Seen) --> [clause(Clause-VNs)].

%% read_terms(+Source, -Terms) is det.
%  Terms are the terms of the file Source as Term-VariableNames.
read_terms(Source, Ts) :-
    open(Source, read, S),
    read_terms_(S, Ts),
    close(S).

read_terms_(S, Ts) :-
    read_term(S, T, [variable_names(VNs)]),
    (   T == end_of_file -> Ts = []
    ;   Ts = [T-VNs|Ts1],
        read_terms_(S, Ts1)
    ).

%% consulted_path(+Source, +File, -Path) is det.
%  Path is File relative to the directory of Source, with .pl added if missing.
consulted_path(Source, File, Path) :-
    atom_chars(Source, Ss),
    atom_chars(File, Fs),
    phrase((relative_dir(Fs, Ss), seq(Fs), pl_ext(Fs)), Ps),
    atom_chars(Path, Ps).

relative_dir(['/'|_], _) --> !, [].
relative_dir(_, Ss) --> { once(phrase((seq(Dir), basename), Ss)) }, seq(Dir).

basename --> [].
basename --> [C], { C \== (/) }, basename.

pl_ext(Fs) --> ( { append(_, ".pl", Fs) } -> [] ; ".pl" ).
