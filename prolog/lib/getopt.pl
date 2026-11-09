:- module(getopt, [getopt/3, usage//3]).

:- use_module(library(lists)).
:- use_module(library(dcgs)).
:- use_module(library(format)).
:- use_module(library(lambda)).

%% getopt(:Specs, +Args, -Positional) is det.
:- meta_predicate(getopt(:, ?, ?)).

getopt(M:Specs, Args, Positional) :-
    phrase(args(Specs, M, Positional), Args).

args(_, _, Ps) --> [['-', '-']], !, seq(Ps).
args(Specs, M, Ps) --> [['-', '-'|L]], !, long(L, Specs, M), args(Specs, M, Ps).
args(Specs, M, Ps) --> [['-', C|Cs]], !, shorts([C|Cs], Specs, M), args(Specs, M, Ps).
args(Specs, M, [A|Ps]) --> [A], !, args(Specs, M, Ps).
args(_, _, []) --> [].

long(L, Specs, M) -->
    { (   append(Cs, ['='|V], L) -> Value = given(V) ; Cs = L, Value = none ),
      atom_chars(Name, Cs),
      atom_chars(Opt, ['-', '-'|Cs]) },
    (   { member(S, Specs), spec(S, flag, Name, _, G) } ->
        { Value == none -> call(M:G) ; throw(error(domain_error(flag, Opt), getopt/3)) }
    ;   { member(S, Specs), spec(S, option, Name, _, G) } ->
        (   { Value = given(V) } -> []
        ;   [V] -> []
        ;   { throw(error(existence_error(option_value, Opt), getopt/3)) }
        ),
        { call(M:G, V) }
    ;   { throw(error(existence_error(option, Opt), getopt/3)) }
    ).

shorts([], _, _) --> [].
shorts([C|Cs], Specs, M) -->
    (   { member(S, Specs), spec(S, flag, _, C, G) } -> { call(M:G) }, shorts(Cs, Specs, M)
    ;   { member(S, Specs), spec(S, option, _, C, G) } ->
        (   { Cs = [_|_] } -> { V = Cs } % the rest of this argument is the value
        ;   [V] -> []
        ;   { atom_chars(Opt, ['-', C]),
              throw(error(existence_error(option_value, Opt), getopt/3)) }
        ),
        { call(M:G, V) }
    ;   { atom_chars(Opt, ['-', C]),
          throw(error(existence_error(option, Opt), getopt/3)) }
    ).

%% spec(+Spec, ?Kind, ?Long, ?Short, ?Goal) is semidet.
%  Spec, in any of its forms, is a Kind (flag or option) with Long, Short, Goal.
spec(flag(L, S, G), flag, L, S, G).
spec(flag(L, S, G, _), flag, L, S, G).
spec(option(L, S, G), option, L, S, G).
spec(option(L, S, G, _, _), option, L, S, G).

spec_value(option(_, _, _, V, _), V) :- !.
spec_value(_, "VALUE").

spec_help(flag(_, _, _, H), H) :- !.
spec_help(option(_, _, _, _, H), H) :- !.
spec_help(_, "").

%% usage(+Program, +Positional, +Specs)// is det.
%  The usage text for Specs: a synopsis line, Program and its options followed
%  by Positional (a string, such as "FILE [IMAGE]"), then a line per option
%  with its Help.
usage(Program, Positional, Specs) -->
    "usage: ", seq(Program), synopsis(Specs), " ", seq(Positional), "\n",
    { maplist(left_column, Specs, Lefts),
      foldl(\L^W0^W^(length(L, N), W is max(W0, N)), Lefts, 0, Width) },
    option_lines(Specs, Lefts, Width).

% [-adh] for the short flags, then [--long] and [-o VALUE] for the rest.
synopsis(Specs) -->
    { findall(C, (member(S, Specs), spec(S, flag, _, C, _), C \== (-)), Cs) },
    (   { Cs == [] } -> [] ; " [-", seq(Cs), "]" ),
    synopsis_rest(Specs).

synopsis_rest([]) --> [].
synopsis_rest([S|Ss]) -->
    (   { spec(S, flag, L, -, _) } -> " [--", atom(L), "]"
    ;   { spec(S, option, L, C, _), spec_value(S, V) } ->
        (   { C \== (-) } -> " [-", [C], " ", seq(V), "]"
        ;   " [--", atom(L), "=", seq(V), "]"
        )
    ;   []
    ),
    synopsis_rest(Ss).

% The left column: -a, --asm and --color, or -o, --out=FILE for an option.
left_column(S, Cs) :-
    spec(S, Kind, L, C, _),
    phrase(( (   { C \== (-) } -> "-", [C], ( { L \== (-) } -> ", " ; [] )
             ;   "    "
             ),
             ( { L \== (-) } -> "--", atom(L) ; [] ),
             ( { Kind == option } -> { spec_value(S, V) }, ( { L \== (-) } -> "=" ; " " ), seq(V) ; [] )
           ), Cs).

option_lines([], [], _) --> [].
option_lines([S|Ss], [L|Ls], Width) -->
    { spec_help(S, H), length(L, N), Pad is Width - N + 2, length(Spaces, Pad), maplist(=(' '), Spaces) },
    "  ", seq(L), ( { H == [] } -> [] ; seq(Spaces), seq(H) ), "\n",
    option_lines(Ss, Ls, Width).

atom(A) --> { atom_chars(A, Cs) }, seq(Cs).

?- getopt([flag(dump, d, D = true), flag(run, r, R = true)], ["-r", "--dump", "x"], Ps).
   D = true, R = true, Ps = ["x"].
?- getopt([flag(dump, d, D = true)], ["a", "-d", "b"], Ps).
   D = true, Ps = ["a","b"].

% Short flags chain.
?- getopt([flag(dump, d, D = true), flag(run, r, R = true)], ["-dr", "x"], Ps).
   D = true, R = true, Ps = ["x"].

% The four ways to give an option its value.
?- getopt([option(out, o, =(V))], ["--out=f"], Ps).
   V = "f", Ps = [].
?- getopt([option(out, o, =(V))], ["--out", "f"], Ps).
   V = "f", Ps = [].
?- getopt([option(out, o, =(V))], ["-of"], Ps).
   V = "f", Ps = [].
?- getopt([option(out, o, =(V))], ["-o", "f"], Ps).
   V = "f", Ps = [].

% An option ends a chain: the rest of the argument is its value.
?- getopt([flag(dump, d, D = true), option(out, o, =(V))], ["-dof", "x"], Ps).
   D = true, V = "f", Ps = ["x"].

% After -- everything is positional, and so is - on its own.
?- getopt([flag(dump, d, D = true), flag(run, r, R = true)], ["-d", "--", "-r", "x"], Ps).
   D = true, Ps = ["-r","x"].
?- getopt([], ["-"], Ps).
   Ps = ["-"].

% Unknown options, also in a chain.
?- getopt([], ["-x"], Ps).
   error(existence_error(option,'-x'),getopt/3).
?- getopt([flag(dump, d, D = true)], ["-dx"], Ps).
   error(existence_error(option,'-x'),getopt/3).
?- getopt([], ["--nope"], Ps).
   error(existence_error(option,'--nope'),getopt/3).

% An option without its value, and a flag with one.
?- getopt([option(out, o, =(V))], ["-o"], Ps).
   error(existence_error(option_value,'-o'),getopt/3).
?- getopt([option(out, o, =(V))], ["--out"], Ps).
   error(existence_error(option_value,'--out'),getopt/3).
?- getopt([flag(dump, d, D = true)], ["--dump=1"], Ps).
   error(domain_error(flag,'--dump'),getopt/3).
