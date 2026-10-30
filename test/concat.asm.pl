zip_procedure(concatenate/3, [
    % concatenate([], L, L).
    clause(nil, [
        constnil,
        skipvar,
        var(9),
        return(11)
    ]),
    % concatenate([X|L1], L2, [X|L3]) :- concatenate(L1, L2, L3).
    clause(cons, [
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
    ])
]).

zip_query("concatenate([1,2],[3],Z).", ["Z"], [
    argmode(9),
    conslist, immed(1), lastconslist, immed(2), constnil, pop,
    conslist, immed(3), constnil, pop,
    firstvar(8),
    call(concatenate/3),
    halt
]).

zip_query("concatenate(X,Y,[1,2,3]).", ["X", "Y"], [
    argmode(10),
    firstvar(8),
    firstvar(9),
    conslist, immed(1), lastconslist, immed(2),
    lastconslist, immed(3), constnil, pop,
    call(concatenate/3),
    halt
]).

zip_query("concatenate([1],[2],[1,3]).", [], [
    argmode(8),
    conslist, immed(1), constnil, pop,
    conslist, immed(2), constnil, pop,
    conslist, immed(1), lastconslist, immed(3), constnil, pop,
    call(concatenate/3),
    halt
]).
