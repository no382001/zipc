:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(dcgs)).
:- use_module(library(pairs)).
:- use_module(library(lambda)).

:- use_module('../build/gen/gen').
:- use_module(encode).

%% include(:Goal, +List, -Included) is det.
%  Included are the elements of List for which Goal succeeds. Copied from clpz.pl.
:- meta_predicate(include(1, ?, ?)).
include(_, [], []).
include(Goal, [L|Ls0], Ls) :-
        (   call(Goal, L) ->
            Ls = [L|Rest]
        ;   Ls = Rest
        ),
        include(Goal, Ls0, Rest).

%% compile_procedure(+Clause, -Procedure) is semidet.
%  Procedure is procedure(Func/Arity, Instrs), the ZIP code for the fact or rule Clause.
%  Fails on terms the compiler does not handle yet.
compile_procedure(Clause, procedure(Func/Arity, Instrs)) :-
    clause_parts(Clause, Head, Body),
    functor(Head, Func, Arity),
    Head =.. [_|Args],
    singletons(Clause, Singles),
    assign_slots(Head, Body, Singles, Locals, FrameSize),
    phrase(match_args(Args, 8), Instrs0),
    phrase((slots(Instrs0, Singles, Locals, [], Seen), body(Body, Seen, FrameSize)), Instrs).

%% clause_parts(+Clause, -Head, -Body) is det.
%  Splits a rule at :-; a fact has the body true.
clause_parts((Head :- Body), Head, Body) :- !.
clause_parts(Head, Head, true).

%% body(+Goal, +Seen, +FrameSize)// is semidet.
%  A fact returns; a single goal pushes its arguments and jumps to it.
body(true, _, FrameSize) --> !, [return(FrameSize)].
body(Goal, Seen, FrameSize) -->
    { functor(Goal, F, N), Goal =.. [_|Args] },
    [argmode(FrameSize)],
    body_args(Args, Seen),
    [proceed(F/N, N)].

%% body_args(+Args, +Seen)// is semidet.
%  Pushes each argument from its slot in Seen; fails on one that is not there.
body_args([], _) --> [].
body_args([A|As], Seen) -->
    { var_slot(A, Seen, Slot) }, [var(Slot)], % TODO: only variables seen in the head for now
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

%% match_args(+Args, +Slot0)// is semidet.
%  First pass: Argument I lives in slot 8+I-1; a variable that is a whole argument stays there.
%  Variables come out as argvar(V, Slot) and firstvar(V), for slots//6 to number.
match_args([], _) --> [].
match_args([X|Xs], Slot0) -->
    { last_flag(Xs, Last) },
    (   { var(X) } -> [argvar(X, Slot0)] % the whole argument is a variable
    ;   match_arg(X, Last) % reuse to determine if its last or not
    ),
    { Slot is Slot0 + 1 },
    match_args(Xs, Slot).

%% last_flag(+Rest, -Last) is det.
%  Last is last when nothing follows, notlast otherwise.
last_flag([], last).
last_flag([_|_], notlast).

%% match_arg(+Term, +Last)// is semidet.
%  Matches Term inside an argument; Last says whether anything follows it at this level.
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

%% slots(+Instrs, +Singles, +Locals, +Seen0, -Seen)// is det.
%  Second pass: Seen pairs each variable already met with its slot, Locals gives each local's slot.
slots([], _, _, Seen, Seen) --> [].
slots([Instr|Instrs], Singles, Locals, Seen0, Seen) -->
    slot(Instr, Singles, Locals, Seen0, Seen1),
    slots(Instrs, Singles, Locals, Seen1, Seen).

%% slot(+Instr, +Singles, +Locals, +Seen0, -Seen)// is det.
%  Numbers one first-pass instruction; anything but a variable passes through.
slot(argvar(V, ArgSlot), _, _, Seen0, Seen) -->
    (   { var_slot(V, Seen0, Slot) } -> [var(Slot)], { Seen = Seen0 } % seen: unify with its slot
    ;   [skipvar], { Seen = [V-ArgSlot|Seen0] } % first: already in its arg slot
    ).
slot(firstvar(V), Singles, Locals, Seen0, Seen) -->
    (   { var_slot(V, Seen0, Slot) } -> [var(Slot)], { Seen = Seen0 }
    ;   { member(S, Singles), S == V } -> [void], { Seen = Seen0 } % used once: no slot
    ;   { var_slot(V, Locals, Slot) }, [firstvar(Slot)], { Seen = [V-Slot|Seen0] } % slot decided by assign_slots
    ).
slot(Instr, _, _, Seen, Seen) -->
    { Instr \= argvar(_, _), Instr \= firstvar(_) }, % not a variable
    [Instr]. % pass through unchanged

%% var_slot(+V, +Seen, -Slot) is semidet.
%  Slot is V's slot in Seen; fails if V has not been seen.
var_slot(V, [V1-Slot1|Seen], Slot) :-
    (   V == V1 -> Slot = Slot1 % == so an unseen V never unifies with another
    ;   var_slot(V, Seen, Slot) % keep looking
    ).

%% occurrences(+Term)// is det.
%  Every variable occurrence in Term, left to right, repeats included.
occurrences(T) -->
    (   { var(T) } -> [T]
    ;   { T =.. [_|Args] }, foldl(occurrences, Args)
    ).

%% singletons(+Term, -Singles) is det.
%  Singles are the variables that occur exactly once in Term.
singletons(T, Singles) :-
    phrase(occurrences(T), Occs),
    term_variables(T, Vs),
    include(Occs+\V^include(==(V), Occs, [_]), Vs, Singles).


%% assign_slots(+Head, +Body, +Singles, -Locals, -FrameSize) is det.
%  Decides every local's slot: body variables first, then head-only.
%  Locals pairs each variable with its slot, FrameSize is the first slot after them.
assign_slots(Head, Body, Singles, Locals, FrameSize) :-
    functor(Head, _, Arity),
    Head =.. [_|Args],
    include(var, Args, ArgVars), % already live in their argument slot
    append(ArgVars, Singles, NoSlot), % singletons are void: no slot either
    term_variables(Body-Head, Vars), % body first, each variable once
    include(NoSlot+\V^(\+ (member(W, NoSlot), W == V)), Vars, LocalVars),
    FirstLocal is 8 + Arity,
    number_slots(LocalVars, FirstLocal, Locals, FrameSize).

%% number_slots(+Vars, +Slot0, -Locals, -FrameSize) is det.
%  Pairs each of Vars with consecutive slots from Slot0.
number_slots(Vars, Slot0, Locals, FrameSize) :- % the next free slot is the frame size
    foldl(\V^(V-S0)^S0^S^(S is S0 + 1), Vars, Locals, Slot0, FrameSize).

% Body variables get the low slots, the head-only X comes last; L2 keeps argument slot 9.
?- assign_slots(concatenate([X|L1], L2, [X|L3]), concatenate(L1, L2, L3), [], Locals, FrameSize).
   Locals = [L1-11, L3-12, X-13], FrameSize = 14.

% Only whole-argument variables: no locals, the frame is just 8 + arity.
?- assign_slots(concatenate([], L, L), true, [], Locals, FrameSize).
   Locals = [], FrameSize = 11.

% Singletons are void and get no slot.
?- assign_slots(concatenate([X|L1], L2, [X|L3]), true, [L1, L3], Locals, FrameSize).
   Locals = [X-11], FrameSize = 12.

% A variable first met in the body still needs a local.
?- assign_slots(f(X), g(X, Y, Y), [], Locals, FrameSize).
   Locals = [Y-9], FrameSize = 10.

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
