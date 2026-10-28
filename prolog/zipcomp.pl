:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(dcgs)).
:- use_module(library(pairs)).
:- use_module(library(lambda)).

:- use_module('../build/gen/gen').
:- use_module(encode).

% from clpz.pl
:- meta_predicate(include(1, ?, ?)).
include(_, [], []).
include(Goal, [L|Ls0], Ls) :-
        (   call(Goal, L) ->
            Ls = [L|Rest]
        ;   Ls = Rest
        ),
        include(Goal, Ls0, Rest).

compile_procedure(Clause, procedure(Func/Arity, Instrs)) :-
    functor(Clause, Func, Arity),
    Clause =.. [_|Args],
    singletons(Clause, Singles),
    phrase(match_args(Args, 8), Instrs0),
    FirstLocal is 8 + Arity,
    phrase(slots(Instrs0, Singles, [], FirstLocal), Instrs).

% First pass: Argument I lives in slot 8+I-1; a variable that is a whole argument stays there.
match_args([], _) --> [].
match_args([X|Xs], Slot0) -->
    { last_flag(Xs, Last) },
    (   { var(X) } -> [argvar(X, Slot0)] % the whole argument is a variable
    ;   match_arg(X, Last) % reuse to determine if its last or not
    ),
    { Slot is Slot0 + 1 },
    match_args(Xs, Slot).

last_flag([], last).
last_flag([_|_], notlast).

match_arg(V, _)  --> { var(V) }, [firstvar(V)]. % variable inside the structure
match_arg([], _) --> [constnil].
match_arg(N, _)  --> { integer(N) }, [immed(N)].
match_arg([H|T], Last) -->
    (   { Last == last } -> [lastconslist] ; [conslist] ),
    match_arg(H, notlast), % the tail still follows the head
    match_arg(T, last),    % the tail is the last part of the cell
    (   { Last == last } -> [] ; [pop] ).

% [] is a constant: nothing to go into.
?- phrase(match_args([[]], 8), Is).
   Is = [constnil].

% [1] is the last argument: nothing follows, so no pop.
?- phrase(match_args([[1]], 8), Is).
   Is = [lastconslist, immed(1), constnil].

% [1] is followed by the argument 2: pop to get back out first.
?- phrase(match_args([[1], 2], 8), Is).
   Is = [conslist, immed(1), constnil, pop, immed(2)].

% [1,2] is [1|[2|[]]]: the tail is the last part of a cell, so lastconslist.
?- phrase(match_args([[1, 2]], 8), Is).
   Is = [lastconslist, immed(1), lastconslist, immed(2), constnil].

% The whole [1,2] chain shares one pop.
?- phrase(match_args([[1, 2], 3], 8), Is).
   Is = [conslist, immed(1), lastconslist, immed(2), constnil, pop, immed(3)].

% [[1]]: the inner [1] is a head, its tail [] follows it, so it needs its own pop.
?- phrase(match_args([[[1]], 2], 8), Is).
   Is = [conslist, conslist, immed(1), constnil, pop, constnil, pop, immed(2)].

% Second pass: Seen pairs each variable already met with its slot, Free is the next free local slot.
slots([], _, _, _) --> [].
slots([Instr|Instrs], Singles, Seen0, Free0) -->
    slot(Instr, Singles, Seen0, Seen, Free0, Free),
    slots(Instrs, Singles, Seen, Free).

slot(argvar(V, ArgSlot), _, Seen0, Seen, Free, Free) -->
    (   { var_slot(V, Seen0, Slot) } -> [var(Slot)], { Seen = Seen0 } % seen: unify with its slot
    ;   [skipvar], { Seen = [V-ArgSlot|Seen0] } % first: already in its arg slot
    ).
slot(firstvar(V), Singles, Seen0, Seen, Free0, Free) -->
    (   { var_slot(V, Seen0, Slot) } -> [var(Slot)], { Seen = Seen0, Free = Free0 }
    ;   { member(S, Singles), S == V } -> [void], { Seen = Seen0, Free = Free0 } % used once: no slot
    ;   [firstvar(Free0)], { Seen = [V-Free0|Seen0], Free is Free0 + 1 }
    ).
slot(Instr, _, Seen, Seen, Free, Free) -->
    { Instr \= argvar(_, _), Instr \= firstvar(_) }, % not a variable
    [Instr]. % pass through unchanged

var_slot(V, [V1-Slot1|Seen], Slot) :-
    (   V == V1 -> Slot = Slot1 % == so an unseen V never unifies with another
    ;   var_slot(V, Seen, Slot) % keep looking
    ).

occurrences(T) -->
    (   { var(T) } -> [T]
    ;   { T =.. [_|Args] }, foldl(occurrences, Args)
    ).

singletons(T, Singles) :-
    phrase(occurrences(T), Occs),
    term_variables(T, Vs),
    include(Occs+\V^include(==(V), Occs, [_]), Vs, Singles).

?- compile_procedure(concatenate([], L, L), Proc).
   Proc = procedure(concatenate/3, [
       constnil,
       skipvar,
       var(9)
   ]).

?- compile_procedure(concatenate([X|L1], L2, [X|L3]), Proc).
   Proc = procedure(concatenate/3, [
       conslist,
       firstvar(11),
       void,
       pop,
       skipvar,
       lastconslist,
       var(11),
       void,
       return(12)
   ]).

% ?- compile_procedure((concatenate([X|L1], L2, [X|L3]) :- concatenate(L1, L2, L3)), Proc).
%    Proc = procedure(concatenate/3, [
%        conslist,
%        firstvar(13),
%        firstvar(11),
%        pop,
%        skipvar,
%        lastconslist,
%        var(13),
%        firstvar(12),
%        argmode(14),
%        var(11),
%        var(9),
%        var(12),
%        proceed(concatenate/3, 3)
%    ]).
