:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(dcgs)).
:- use_module(library(pairs)).
:- use_module('../build/gen/gen').
:- use_module(encode).

compile_procedure(Clause, procedure(Func/Arity, Instrs)) :-
    functor(Clause, Func, Arity),
    Clause =.. [_|Args],
    phrase(match_args(Args, 8), Instrs0),
    FirstLocal is 8 + Arity,
    phrase(slots(Instrs0, [], FirstLocal), Instrs).

% First pass: Argument I lives in slot 8+I-1; a variable that is a whole argument stays there.
match_args([], _) --> [].
match_args([X|Xs], Slot0) -->
    (   { var(X) } -> [argvar(X, Slot0)] % the whole argument is a variable
    ;   match_arg(X)
    ),
    { Slot is Slot0 + 1 },
    match_args(Xs, Slot).

match_arg(V)     --> { var(V) }, [firstvar(V)]. % variable inside the structure
match_arg([])    --> [constnil].
% match_arg(N)     --> { integer(N) }, [immed(N)].
% match_arg([H|T]) --> [conslist], match_arg(H), match_arg(T).

% Second pass: Seen pairs each variable already met with its slot, Free is the next free local slot.
slots([], _, _) --> [].
slots([Instr|Instrs], Seen0, Free0) -->
    slot(Instr, Seen0, Seen, Free0, Free),
    slots(Instrs, Seen, Free).

slot(argvar(V, ArgSlot), Seen0, Seen, Free, Free) -->
    (   { var_slot(V, Seen0, Slot) } -> [var(Slot)], { Seen = Seen0 } % seen: unify with its slot
    ;   [skipvar], { Seen = [V-ArgSlot|Seen0] } % first: already in its arg slot
    ).
slot(firstvar(V), Seen0, Seen, Free0, Free) -->
    (   { var_slot(V, Seen0, Slot) } -> [var(Slot)], { Seen = Seen0, Free = Free0 } % seen: unify with its slot
    ;   [firstvar(Free0)], { Seen = [V-Free0|Seen0], Free is Free0 + 1 } % first: store in a new local slot
    ).
slot(Instr, Seen, Seen, Free, Free) -->
    { Instr \= argvar(_, _), Instr \= firstvar(_) }, % not a variable
    [Instr]. % pass through unchanged

var_slot(V, [V1-Slot1|Seen], Slot) :-
    (   V == V1 -> Slot = Slot1 % == so an unseen V never unifies with another
    ;   var_slot(V, Seen, Slot) % keep looking
    ).

?- compile_procedure(concatenate([], L, L), Proc).
   Proc = procedure(concatenate/3, [
       constnil,
       skipvar,
       var(9)
   ]).

?- compile_procedure((concatenate([X|L1], L2, [X|L3]) :- concatenate(L1, L2, L3)), Proc).
   Proc = procedure(concatenate/3, [
       conslist,
       firstvar(13),
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
