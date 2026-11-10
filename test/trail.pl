% a cut drops the trail entries no remaining choice point needs

% each call leaves a choice point that the cut removes, with F trailed under it
fib(N, N) :- N < 2, !.
fib(N, F) :- A is N - 1, B is N - 2, fib(A, FA), fib(B, FB), F is FA + FB.

c(1).
c(2).
same(X, X).

% Y is bound under the choice point of c(_), which the cut removes, but the
% one in c(X) is older than Y and must still undo it.
k(X, Y) :- c(_), same(Y, X), !.

?- fib(21, F).
?- c(X), k(X, Y).
