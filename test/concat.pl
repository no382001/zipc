% concatenate(Xs, Ys, Zs): Zs is Xs followed by Ys.
concatenate([], L, L).
concatenate([X|L1], L2, [X|L3]) :- concatenate(L1, L2, L3).

?- concatenate([1,2],[3],Z).
?- concatenate(X,Y,[1,2,3]).
?- concatenate([1],[2],[1,3]).
