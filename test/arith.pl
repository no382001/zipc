% integer arithmetic, compiled inline: is/2 and comparisons over + and -

fib(N, N) :- N < 2, !.
fib(N, F) :- A is N - 1, B is N - 2, fib(A, FA), fib(B, FB), F is FA + FB.

range(N, N, [N]) :- !.
range(I, N, [I|T]) :- I < N, I1 is I + 1, range(I1, N, T).

five(5).

% an is/2 whose left side is used once still evaluates the right
count(X) :- _ is X + 1.

?- fib(10, F).
?- range(298, 302, L).
?- X is 1 + 2 - 300.
?- X is -7 - 1.
?- 3 is 1 + 2.
?- 4 is 1 + 2.
?- a is 1.
?- five(X), X >= 5, X =< 5, X > 4, X =:= 5, X =\= 6.
?- five(X), X > 5.
?- count(1).
