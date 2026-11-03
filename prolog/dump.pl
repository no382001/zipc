:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(pairs)).
:- use_module(library(charsio)).
:- use_module(library(lambda)).

% Uses read_file/3 and compile_clause/2 from main.pl.

%% dump(+Source, +Color) is det.
%  Prints the code for the program in the file Source, a section per clause.
%  Color is true for ANSI colors.
dump(Source, Color) :-
    retractall(color),
    (   Color == true -> assertz(color) ; true ),
    catch(dump_file(Source), E, (format(user_error, "dump: ~q~n", [E]), halt(1))).

:- dynamic(color/0).

dump_file(Source) :-
    read_file(Source, Clauses, Queries),
    maplist(source_clause, Clauses, Pairs),
    group_pairs_by_key(Pairs, Procedures),
    maplist(dump_procedure, Procedures),
    maplist(dump_query, Queries).

% Pair is Func/Arity-(Text-Names-clause(Key, Instrs)), Text the clause as it
% was read.
source_clause(Clause-VNs, P-(Text-Names-C)) :-
    write_term_to_chars(Clause, [quoted(true), variable_names(VNs)], Text),
    slot_names(Clause, VNs, Names),
    compile_clause(Clause, P-C).

%% slot_names(+Clause, +VNs, -Names) is det.
%  Names are Slot-Name for the named variables of Clause, in the slots
%  compile_procedure/2 gives them.
slot_names(Clause, VNs, Names) :-
    clause_parts(Clause, Head, Body),
    Head =.. [_|Args],
    singletons(Clause, Singles),
    assign_slots(Head, Body, Singles, Locals, _),
    foldl(\A^(A-S0)^S0^S^(S is S0 + 1), Args, ArgSlots, 8, _),
    append(ArgSlots, Locals, VarSlots),
    foldl(VNs+\ (V-S)^Ns0^Ns^(
              (   var(V), member(N=W, VNs), W == V -> Ns = [S-N|Ns0] ; Ns = Ns0 )),
          VarSlots, [], Names).

dump_procedure(P-Cs) :-
    paint(procedure, format("~q", [P])), nl,
    maplist(\ (Text-Names-clause(Key, Is))^(
                paint(source, format("  % ~s.", [Text])), nl,
                format("  clause ~q~n", [Key]),
                dump_code(Names, Is)), Cs),
    nl.

dump_query(zip_query(Text, Names, Is)) :-
    paint(procedure, format("?- ~s", [Text])), nl,
    foldl(\Cs^(S0-Ns0)^(S-[S0-N|Ns0])^(atom_chars(N, Cs), S is S0 + 1), Names, 8-[], _-Slots),
    dump_code(Slots, Is),
    nl.

%% dump_code(+Names, +Instrs) is det.
%  Prints the head, neck and goals of the code of a clause or query, the
%  variable instructions with the names in Names.
dump_code(Names, Is) :-
    append(Head, [Neck|Body], Is), neck(Neck), !,
    dump_args(Names, head, Head),
    dump_line(Names, neck, '', [Neck]),
    dump_goals(Names, Body).

neck(argmode(_)).
neck(enter(_)).
neck(return(_)).

dump_goals(_, []).
dump_goals(_, [halt]) :- write('    '), paint(control, write(halt)), nl.
dump_goals(Names, Is) :-
    append(Args, [Call|Is1], Is), goal_end(Call), !,
    dump_line(Names, goal, '', [Call]),
    dump_args(Names, '', Args),
    dump_goals(Names, Is1).

goal_end(call(_)).
goal_end(depart(_, _)).
goal_end(proceed(_, _)).

%% dump_args(+Names, +Label, +Instrs) is det.
%  Prints Instrs an argument a line, numbered by the slot they unify with.
dump_args(Names, Label, Is) :-
    args(Is, Args),
    foldl(Names+\A^(L0-S0)^(''-S)^(dump_line(Names, L0, S0, A), S is S0 + 1), Args, Label-8, _).

%% args(+Instrs, -Args) is det.
%  Args are Instrs split into the instructions of each argument.
args([], []).
args(Is, [A|As]) :- arg_instrs(Is, 0, A, Is1), args(Is1, As).

% A lastconslist at the top is the last argument of a head, which has no pop.
arg_instrs([lastconslist|Is], 0, [lastconslist|Is], []) :- !.
arg_instrs([I|Is], D0, [I|A], Rest) :-
    depth(I, D0, D),
    (   D =:= 0 -> A = [], Rest = Is
    ;   arg_instrs(Is, D, A, Rest)
    ).

depth(conslist, D0, D) :- !, D is D0 + 1.
depth(pop, D0, D) :- !, D is D0 - 1.
depth(_, D, D).

dump_line(Names, Label, Slot, Is) :-
    dump_columns(Label, Slot),
    foldl([Names,Slot]+\I^Sep0^' '^(write(Sep0), dump_instruction(Names, Slot, I)), Is, '', _),
    nl.

dump_instruction(Names, Slot, I) :-
    paint(instruction(I), dump_term(I)),
    (   instruction_slot(I, Slot, S), memberchk(S-N, Names) -> paint(source, format(":~w", [N]))
    ;   true
    ).

% skipvar leaves the variable in the argument slot of its line.
instruction_slot(var(S), _, S).
instruction_slot(firstvar(S), _, S).
instruction_slot(skipvar, S, S).

% Escapes count as columns in format/2, so each column is formatted on its own.
dump_columns(Label, Slot) :-
    write('    '),
    paint(label, format("~w~t~6|", [Label])),
    paint(slot, format("~w~t~4|", [Slot])).

dump_term(T) :- % text and names are char lists, print them as "..."
    write_term(T, [quoted(true), double_quotes(true)]).

%% paint(+Style, :Goal) is det.
%  Calls Goal, its output in the attributes of Style if color is on.
paint(Style, Goal) :-
    (   color, style(Style, Attrs) ->
        maplist(\A^(sgr(A, Code), format("\x1b\[~sm", [Code])), Attrs),
        call(Goal),
        format("\x1b\[0m", [])
    ;   call(Goal)
    ).

%% style(+Style, -Attrs) is semidet.
%  Attrs are the attributes Style is printed in, it fails for plain output.
style(procedure, [bold]).
style(source, [grey]).
style(label, [blue]).
style(slot, [orange]).
style(control, [bold, green]).
style(structure, [purple]).
style(instruction(I), Attrs) :-
    functor(I, Name, _), instruction_style(Name, Style), style(Style, Attrs).

instruction_style(Name, control) :- memberchk(Name, [argmode, enter, return, call, depart, proceed, halt]), !.
instruction_style(Name, structure) :- memberchk(Name, [conslist, lastconslist, pop]).

%% sgr(?Attr, ?Code) is nondet.
%  Code is the ANSI select graphic rendition parameter of Attr, the colors
%  are from the 256 color palette.
sgr(bold, "1").
sgr(grey, "38;5;245").
sgr(blue, "38;5;110").
sgr(orange, "38;5;180").
sgr(green, "38;5;114").
sgr(purple, "38;5;140").
