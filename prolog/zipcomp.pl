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
    clause_parts(Clause, Head, Body),
    functor(Head, Func, Arity),
    Head =.. [_|Args],
    singletons(Clause, Singles),
    phrase(match_args(Args, 8), Instrs0),
    FirstLocal is 8 + Arity,
    phrase((slots(Instrs0, Singles, [], Seen, FirstLocal, FrameSize), body(Body, Seen, FrameSize)), Instrs).

clause_parts((Head :- Body), Head, Body) :- !.
clause_parts(Head, Head, true).

% A fact returns; a single goal pushes its arguments and jumps to it.
body(true, _, FrameSize) --> !, [return(FrameSize)].
body(Goal, Seen, FrameSize) -->
    { functor(Goal, F, N), Goal =.. [_|Args] },
    [argmode(FrameSize)],
    body_args(Args, Seen),
    [proceed(F/N, N)].

body_args([], _) --> [].
body_args([A|As], Seen) -->
    { var_slot(A, Seen, Slot) }, [var(Slot)], % only variables seen in the head for now
    body_args(As, Seen).

% A fact: no goal to call, just return.
?- phrase(body(true, [], 11), Is).
   Is = [return(11)].

% Each argument is pushed from the slot the head gave it, in argument order.
?- phrase(body(f(A, B), [A-9, B-11], 12), Is).
   Is = [argmode(12), var(9), var(11), proceed(f/2, 2)].

% An argument can be pushed more than once.
?- phrase(body(f(A, A), [A-11], 12), Is).
   Is = [argmode(12), var(11), var(11), proceed(f/2, 2)].

% An atom goal has no arguments to push.
?- phrase(body(g, [], 11), Is).
   Is = [argmode(11), proceed(g/0, 0)].

% a variable the head never saw.
?- phrase(body(f(C), [], 11), Is).
   false.

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
match_arg(L, _) --> { L == [] }, [constnil].
match_arg(N, _)  --> { integer(N) }, [immed(N)].
match_arg(L, Last) -->
    { nonvar(L), L = [H|T] },
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

% An unbound tail is a variable, not a list: exactly one answer, T stays unbound.
?- phrase(match_args([[1|T]], 8), Is).
   Is = [lastconslist, immed(1), firstvar(T)].

% Second pass: Seen pairs each variable already met with its slot, Free is the next free local slot.
slots([], _, Seen, Seen, Free, Free) --> []. % the next free slot is the frame size
slots([Instr|Instrs], Singles, Seen0, Seen, Free0, FrameSize) -->
    slot(Instr, Singles, Seen0, Seen1, Free0, Free),
    slots(Instrs, Singles, Seen1, Seen, Free, FrameSize).

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
       var(9),
       return(11) % no locals: frame size is 8 + 3 arguments
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

?- compile_procedure((concatenate([X|L1], L2, [X|L3]) :- concatenate(L1, L2, L3)), Proc).
   Proc = procedure(concatenate/3, [
       conslist,
       firstvar(13), % X gets top slot bc its discarded first
       firstvar(11),
       pop,
       skipvar,
       lastconslist,
       var(13),
       firstvar(12),
       argmode(14),
       var(11),
       var(9),
       var(12),
       proceed(concatenate/3, 3)
   ]).
