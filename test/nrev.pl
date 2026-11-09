% nrev(Xs, Ys): Ys is Xs reversed, naively.
:- consult(concat).

nrev([], []).
nrev([H|T], R) :- nrev(T, RT), concatenate(RT, [H], R).

?- nrev([], R).
?- nrev([1,2,3], R).
?- nrev([1,2], [1,2]).
