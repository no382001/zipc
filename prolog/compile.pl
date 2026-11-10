:- module(compile, [
    compile_clause/2,
    compile_goal/2,
    compile_procedure/2,
    compile_query/2,
    clause_key/2,
    clause_parts/3,
    singletons/2,
    assign_slots/5
]).

:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(dcgs)).
:- use_module(library(pairs)).
:- use_module(library(lambda)).
:- use_module(library(charsio)).

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

%% compile_clause(+Clause, -Pair) is det.
%  Pair is Func/Arity-clause(Key, Instrs), ready to group into procedures.
%  Throws on a clause the compiler does not handle yet.
compile_clause(Clause, P-clause(Key, Instrs)) :-
    clause_parts(Clause, Head, Body),
    supported((Head, Body), Clause),
    compile_or_throw(compile_procedure(Clause, procedure(P, Instrs)), Clause),
    clause_key(Clause, Key).

%% compile_goal(+Query, -ZipQuery) is det.
%  ZipQuery is zip_query(Text, Names, Instrs) for Query, a Goal-VariableNames
%  as read from a ?- Goal directive. Throws on a goal it does not handle yet.
compile_goal(Goal-VNs, Q) :-
    query_text(Goal, VNs, Text),
    supported(Goal, Goal),
    compile_or_throw(compile_query(Text, Q), Goal).

%% query_text(+Goal, +VNs, -Text) is det.
%  Text is Goal as the VM prints it after ?-, with its variable names and the dot.
query_text(Goal, VNs, Text) :-
    write_term_to_chars(Goal, [quoted(true), variable_names(VNs)], Cs),
    append(Cs, ".", Text).

%% supported(+Goals, +Term) is det.
%  Throws, naming Term, if one of Goals is a control construct the compiler
%  does not handle yet, or evaluates what the VM cannot.
supported(Goals, Term) :-
    (   goal(Goals, G), callable(G), functor(G, F, N), control(F/N)
    ->  throw(error(representation_error(control_construct(F/N)), Term))
    ;   goal(Goals, G), arithmetic(G), expressions(G, E), unsupported(E, Bad)
    ->  throw(error(representation_error(evaluable(Bad)), Term))
    ;   true
    ).

%% arithmetic(+Goal) is semidet.
%  Goal is an arithmetic built-in, which compiles to instructions, not a call.
arithmetic(G) :- functor(G, Op, 2), arithmetic_op(Op, _).

arithmetic_op(is, _).
arithmetic_op(<, lt).
arithmetic_op(=<, le).
arithmetic_op(>, gt).
arithmetic_op(>=, ge).
arithmetic_op(=:=, eq).
arithmetic_op(=\=, ne).

% The expressions of an arithmetic goal: the left of is/2 is not one.
expressions(_ is E, E) :- !.
expressions(G, E) :- arg(1, G, E) ; arg(2, G, E).

%% unsupported(+E, -Bad) is semidet.
%  Bad, as Name/Arity, is a part of the expression E the VM cannot evaluate;
%  it evaluates integers and variables under + and -.
unsupported(E, Bad) :-
    nonvar(E), \+ integer(E),
    (   ( E = A + B ; E = A - B ) -> ( unsupported(A, Bad) ; unsupported(B, Bad) )
    ;   functor(E, F, N), Bad = F/N
    ).

control((;)/2).
control((->)/2).
control((\+)/1).
control(call/_).

?- catch(supported((X is Y + 1, X < 300), t), error(E, _), true).
   true.
?- catch(supported((X is Y * 2), t), error(E, _), true).
   E = representation_error(evaluable((*)/2)).
?- supported((p([1,X]), q(f(a))), t).
   true.
?- catch(supported((p(X), (q(X) ; r)), t), error(E, _), true).
   E = representation_error(control_construct((;)/2)).

goal((A, B), G) :- !, ( goal(A, G) ; goal(B, G) ).
goal(G, G).

compile_or_throw(Goal, Term) :-
    (   catch(Goal, error(instantiation_error, _),
              throw(error(instantiation_error, Term)))
    ->  true
    ;   throw(error(domain_error(compilable, Term), compile/2))
    ).

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
    arg_slots(Args, 8, [], ArgSeen),
    phrase((slots(Instrs0, Singles, Locals, ArgSeen, Seen), body(Body, Singles, Locals, Seen, FrameSize)), Instrs).

%% arg_slots(+Args, +Slot, +Seen0, -Seen) is det.
%  Seen pairs each argument variable with its argument slot, the first if it
%  is in several. They hold their value before the head runs, so a variable
%  met inside an earlier argument already has a slot.
arg_slots([], _, Seen, Seen).
arg_slots([A|As], Slot, Seen0, Seen) :-
    (   var(A), \+ var_slot(A, Seen0, _) -> Seen1 = [A-Slot|Seen0] ; Seen1 = Seen0 ),
    Slot1 is Slot + 1,
    arg_slots(As, Slot1, Seen1, Seen).

%% clause_key(+Clause, -Key) is det.
%  Key is what the VM indexes the clause on: the type of its first argument.
clause_key(Clause, Key) :-
    clause_parts(Clause, Head, _),
    (   functor(Head, _, 0) -> Key = any
    ;   arg(1, Head, A),
        (   var(A) -> Key = any
        ;   A == [] -> Key = nil
        ;   A = [_|_] -> Key = cons
        ;   integer(A) -> Key = A
        ;   atom(A) -> Key = atom(A)
        ;   functor(A, F, N), Key = functor(F/N)
        )
    ).

?- clause_key(concatenate([], L, L), Key).
   Key = nil.
?- clause_key((concatenate([X|L1], L2, [X|L3]) :- concatenate(L1, L2, L3)), Key).
   Key = cons.
?- clause_key(f(3), Key).
   Key = 3.
% An atom is wrapped, so that p(any) is not keyed like p(X).
?- clause_key(colour(any), Key).
   Key = atom(any).
% A structure is keyed on its functor, a list on cons whatever its length.
?- clause_key(solve((A, B)), Key).
   Key = functor((',')/2).
% A variable first argument matches anything, and so does no argument at all.
?- clause_key(f(X), Key).
   Key = any.
?- clause_key(g, Key).
   Key = any.

%% clause_parts(+Clause, -Head, -Body) is det.
%  Splits a rule at :-; a fact has the body true.
clause_parts((Head :- Body), Head, Body) :- !.
clause_parts(Head, Head, true).

%% body(+Goal, +Singles, +Locals, +Seen, +FrameSize)// is semidet.
%  A fact returns; a single goal pushes its arguments and jumps to it;
%  several goals call all but the last, which departs.
body(true, _, _, _, FrameSize) --> !, [return(FrameSize)].
body(!, _, _, _, FrameSize) --> !, [enter(FrameSize), cut, return(FrameSize)]. % TODO: fast path, but fine for now
body(fail, _, _, _, FrameSize) --> !, [argmode(FrameSize), fail]. % TODO: fast path, but fine for now
body(G, Singles, Locals, Seen, FrameSize) --> { arithmetic(G) }, !,
    [enter(FrameSize)],
    arithmetic(G, Singles, Locals, Seen, _),
    [return(FrameSize)].
body((A,B), Singles, Locals, Seen, FrameSize) --> !,
    [enter(FrameSize)],
    goals((A,B), Singles, Locals, Seen, Seen, FrameSize).
body(Goal, Singles, Locals, Seen, FrameSize) -->
    { functor(Goal, F, N), Goal =.. [_|Args] },
    [argmode(FrameSize)],
    last_goal_args(Args, Singles, Locals, Seen, Seen),
    [proceed(F/N, N)].

%% goals(+Goals, +Singles, +Locals, +Seen, +Head, +FrameSize)// is semidet.
%  Each goal pushes its arguments; all but the last are called, the last departs.
%  Head are the variables the head met, which never live in this frame.
goals((!,B), Singles, Locals, Seen, Head, FrameSize) --> !,
    [cut],
    goals(B, Singles, Locals, Seen, Head, FrameSize).
goals((fail,_), _, _, _, _, _) --> !, [fail].
goals((A,B), Singles, Locals, Seen0, Head, FrameSize) --> { arithmetic(A) }, !,
    arithmetic(A, Singles, Locals, Seen0, Seen),
    goals(B, Singles, Locals, Seen, Head, FrameSize).
goals((A,B), Singles, Locals, Seen0, Head, FrameSize) --> !,
    { functor(A, F, N), A =.. [_|Args] },
    goal_args(Args, Singles, Locals, Seen0, Seen),
    [call(F/N)],
    goals(B, Singles, Locals, Seen, Head, FrameSize).
goals(!, _, _, _, _, FrameSize) --> !, [cut, return(FrameSize)].
goals(fail, _, _, _, _, _) --> !, [fail].
goals(A, Singles, Locals, Seen, _, FrameSize) --> { arithmetic(A) }, !,
    arithmetic(A, Singles, Locals, Seen, _),
    [return(FrameSize)].
goals(A, Singles, Locals, Seen0, Head, _) -->
    { functor(A, F, N), A =.. [_|Args] },
    last_goal_args(Args, Singles, Locals, Seen0, Head),
    [depart(F/N, N)].

%% goal_args(+Args, +Singles, +Locals, +Seen0, -Seen)// is semidet.
%  Builds each argument in ARG mode, so every list ends in pop. A variable met
%  for the first time is a firstvar in its slot from Locals, and joins Seen.
goal_args(Args, Singles, Locals, Seen0, Seen) -->
    { phrase(foldl(\A^match_arg(A, notlast), Args), Instrs0) },
    slots(Instrs0, Singles, Locals, Seen0, Seen).

%% last_goal_args(+Args, +Singles, +Locals, +Seen, +Head)// is semidet.
%  Like goal_args//5, but the last goal can take over the frame, so a variable
%  that is a whole argument and may live in the frame is glofirvar or glovar,
%  which make it global. A variable of the head never lives in the frame.
last_goal_args(Args, Singles, Locals, Seen, Head) -->
    { phrase(goal_args(Args, Singles, Locals, Seen, _), Is0),
      foldl(Head+\I0^I^D0^D^global_arg(I0, I, Head, D0, D), Is0, Is, 0, _) },
    seq(Is).

%% global_arg(+Instr0, -Instr, +Head, +Depth0, -Depth) is det.
%  Depth counts the structures Instr0 is in; inside one a variable is copied
%  to the global stack anyway.
global_arg(firstvar(S), glofirvar(S), _, 0, 0) :- !.
global_arg(var(S), I, Head, 0, 0) :- !,
    ( member(_-S0, Head), S0 == S -> I = var(S) ; I = glovar(S) ).
global_arg(I, I, _, D0, D) :-
    (   ( I == conslist ; I = functor(_, _) ) -> D is D0 + 1
    ;   I == pop -> D is D0 - 1
    ;   D = D0
    ).

?- phrase(last_goal_args([X, f(X, Y), Y], [], [X-9, Y-10], [], []), Is).
   Is = [glofirvar(9), functor(f/2, 2), var(9), firstvar(10), pop, glovar(10)].
% The head's X is passed as it is, the body's Y may live in the frame.
?- phrase(last_goal_args([X, Y], [], [], [X-8, Y-10], [X-8]), Is).
   Is = [var(8), glovar(10)].

% A fact: no goal to call, just return.
?- phrase(body(true, [], [], [], 11), Is).
   Is = [return(11)].

% Each argument is pushed from the slot the head gave it, in argument order.
?- phrase(body(f(A, B), [], [], [A-9, B-11], 12), Is).
   Is = [argmode(12), var(9), var(11), proceed(f/2, 2)].

% An argument can be pushed more than once.
?- phrase(body(f(A, A), [], [], [A-11], 12), Is).
   Is = [argmode(12), var(11), var(11), proceed(f/2, 2)].

% An atom goal has no arguments to push.
?- phrase(body(g, [], [], [], 11), Is).
   Is = [argmode(11), proceed(g/0, 0)].

% A variable the head never saw is a glofirvar in the last goal: it goes global.
?- phrase(body(f(C), [], [C-11], [], 12), Is).
   Is = [argmode(12), glofirvar(11), proceed(f/1, 1)].

% A list argument is built, and ends in pop.
?- phrase(body(f([A]), [], [], [A-8], 9), Is).
   Is = [argmode(9), conslist, var(8), constnil, pop, proceed(f/1, 1)].

?- phrase(body((f(A), g(A)), [], [], [A-8], 9), Is).
   Is = [enter(9), var(8), call(f/1), var(8), depart(g/1, 1)].

% A variable first met in one goal lives in the frame, and is a glovar in the last.
?- phrase(body((f(C), g(C)), [], [C-9], [], 10), Is).
   Is = [enter(10), firstvar(9), call(f/1), glovar(9), depart(g/1, 1)].

?- phrase(body((f, !, g), [], [], [], 8), Is).
   Is = [enter(8), call(f/0), cut, depart(g/0, 0)].
?- phrase(body((f, !), [], [], [], 8), Is).
   Is = [enter(8), call(f/0), cut, return(8)].
?- phrase(body(!, [], [], [], 8), Is).
   Is = [enter(8), cut, return(8)].

% Nothing after a fail runs, so it is not compiled.
?- phrase(body((f, fail, g), [], [], [], 8), Is).
   Is = [enter(8), call(f/0), fail].

%% arithmetic(+Goal, +Singles, +Locals, +Seen0, -Seen)// is det.
%  Evaluates the expressions of Goal on the VM's arithmetic stack, then
%  compares them, or for is/2 unifies the left side with the value. A left
%  side met for the first time takes the value in its slot, and joins Seen.
arithmetic(X is E, Singles, Locals, Seen0, Seen) --> !,
    expression(E, Seen0),
    (   { var(X), var_slot(X, Seen0, Slot) } -> [isvar(Slot)], { Seen = Seen0 }
    ;   { var(X), member(S, Singles), S == X } -> [isvoid], { Seen = Seen0 }
    ;   { var(X) } -> { var_slot(X, Locals, Slot) }, [isfirst(Slot)], { Seen = [X-Slot|Seen0] }
    ;   { integer(X) } -> expression(X, Seen0), [eq], { Seen = Seen0 }
    ;   [isvoid, fail], { Seen = Seen0 } % not a number: never equal
    ).
arithmetic(G, _, _, Seen, Seen) -->
    { G =.. [Op, A, B], arithmetic_op(Op, I) },
    expression(A, Seen),
    expression(B, Seen),
    [I].

%% expression(+E, +Seen)// is det.
%  Pushes the value of E. A variable not met yet can have no value, which
%  would be an instantiation error every time, so it is one now.
expression(V, Seen) --> { var(V) }, !,
    (   { var_slot(V, Seen, Slot) } -> [pushvar(Slot)]
    ;   { throw(error(instantiation_error, expression//2)) }
    ).
expression(N, _) --> { integer(N) }, !,
    ( { N >= 0, N =< 255 } -> [pushimmed(N)] ; [pushconst(N)] ).
expression(A + B, Seen) --> !, expression(A, Seen), expression(B, Seen), [add].
expression(A - B, Seen) --> expression(A, Seen), expression(B, Seen), [sub].

?- phrase(body((A is B - 1, A < 300), [], [A-9], [B-8], 10), Is).
   Is = [enter(10), pushvar(8), pushimmed(1), sub, isfirst(9), pushvar(9), pushconst(300), lt, return(10)].
?- phrase(body(A =:= B, [], [], [A-8, B-9], 10), Is).
   Is = [enter(10), pushvar(8), pushvar(9), eq, return(10)].

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
match_arg(N, _)  --> { integer(N) }, ( { N >= 0, N =< 255 } -> [immed(N)] ; [constant(N)] ).
match_arg(A, _)  --> { atom(A), A \== [] }, [constant(A)].
match_arg(L, Last) -->
    { nonvar(L), L = [H|T] },
    (   { Last == last } -> [lastconslist] ; [conslist] ),
    match_arg(H, notlast), % the tail still follows the head
    match_arg(T, last),    % the tail is the last part of the cell
    (   { Last == last } -> [] ; [pop] ).
match_arg(S, Last) -->
    { compound(S), S \= [_|_], functor(S, F, N), S =.. [_|Args] },
    (   { Last == last } -> [lastfunctor(F/N, N)] ; [functor(F/N, N)] ),
    components(Args), % its last argument is the last part of the cell
    (   { Last == last } -> [] ; [pop] ).

%% components(+Args)// is semidet.
%  Matches the arguments of a structure, all but the last followed by more.
components([A]) --> !, match_arg(A, last).
components([A|As]) --> match_arg(A, notlast), components(As).

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

% A structure is like a list cell: functor, its arguments, then pop.
?- phrase(match_args([f(a, X), 1], 8), Is).
   Is = [functor(f/2, 2), constant(a), firstvar(X), pop, immed(1)].
?- phrase(match_args([g(f(1))], 8), Is).
   Is = [lastfunctor(g/1, 1), lastfunctor(f/1, 1), immed(1)].
?- phrase(match_args([[f(1)]], 8), Is).
   Is = [lastconslist, functor(f/1, 1), immed(1), pop, constnil].

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
    (   { var_slot(V, Seen0, Slot), Slot =\= ArgSlot } -> [var(Slot)], { Seen = Seen0 } % seen: unify with its slot
    ;   [skipvar], { Seen = [V-ArgSlot|Seen0] } % already in its arg slot
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

% RT is first met in the body: firstvar in the first goal, glovar in the last.
?- compile_procedure((nrev([H|T], R) :- nrev(T, RT), concatenate(RT, [H], R)), Proc).
   Proc = procedure(nrev/2, [
       conslist,
       firstvar(12),
       firstvar(10),
       pop,
       skipvar,
       enter(13),
       var(10),
       firstvar(11),
       call(nrev/2),
       glovar(11),
       conslist,
       var(12),
       constnil,
       pop,
       var(9),
       depart(concatenate/3, 3)
   ]).

%% compile_query(+Text, -Query) is semidet.
%  Query is zip_query(Text, Names, Instrs) for the query in the chars Text, ending in a dot.
%  Named variables get slots 8, 9, ... in the order of Names
compile_query(Text, zip_query(Text, Names, Instrs)) :-
    read_term_from_chars(Text, Goal, [variable_names(VNs)]),
    maplist(\ (Name=_)^Chars^atom_chars(Name, Chars), VNs, Names),
    maplist(\ (_=V)^V^true, VNs, Named),
    term_variables(Named-Goal, Vars), % named first, then any _
    number_slots(Vars, 8, Locals, FrameSize),
    (   Goal = (_,_) -> Neck = enter(FrameSize) ; Neck = argmode(FrameSize) ),
    phrase(([Neck], query_goals(Goal, Locals, []), [halt]), Instrs).

%% query_goals(+Goals, +Locals, +Seen)// is semidet.
%  Like goals//4, but every goal is called, and the query halts after the last.
query_goals((A,B), Locals, Seen0) --> !,
    query_goal(A, Locals, Seen0, Seen),
    query_goals(B, Locals, Seen).
query_goals(A, Locals, Seen0) -->
    query_goal(A, Locals, Seen0, _).

query_goal(!, _, Seen, Seen) --> !, [cut].
query_goal(fail, _, Seen, Seen) --> !, [fail].
query_goal(G, Locals, Seen0, Seen) --> { arithmetic(G) }, !,
    arithmetic(G, [], Locals, Seen0, Seen).
query_goal(Goal, Locals, Seen0, Seen) -->
    { functor(Goal, F, N), Goal =.. [_|Args] },
    goal_args(Args, [], Locals, Seen0, Seen),
    [call(F/N)].

% The three queries from concat.pl.
?- compile_query("concatenate([1,2],[3],Z).", Q).
   Q = zip_query("concatenate([1,2],[3],Z).", ["Z"], [
       argmode(9),
       conslist, immed(1), lastconslist, immed(2), constnil, pop,
       conslist, immed(3), constnil, pop,
       firstvar(8),
       call(concatenate/3),
       halt
   ]).

?- compile_query("concatenate(X,Y,[1,2,3]).", Q).
   Q = zip_query("concatenate(X,Y,[1,2,3]).", ["X", "Y"], [
       argmode(10),
       firstvar(8),
       firstvar(9),
       conslist, immed(1), lastconslist, immed(2),
       lastconslist, immed(3), constnil, pop,
       call(concatenate/3),
       halt
   ]).

% No variables
?- compile_query("concatenate([1],[2],[1,3]).", Q).
   Q = zip_query("concatenate([1],[2],[1,3]).", [], [
       argmode(8),
       conslist, immed(1), constnil, pop,
       conslist, immed(2), constnil, pop,
       conslist, immed(1), lastconslist, immed(3), constnil, pop,
       call(concatenate/3),
       halt
   ]).

% A variable used twice is var after its firstvar.
?- compile_query("f(X,X).", Q).
   Q = zip_query("f(X,X).", ["X"], [argmode(9), firstvar(8), var(8), call(f/2), halt]).

% Several goals: each is called, and a variable is first met only once.
?- compile_query("f(X),g(X).", Q).
   Q = zip_query("f(X),g(X).", ["X"], [enter(9), firstvar(8), call(f/1), var(8), call(g/1), halt]).
