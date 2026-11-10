% structures

point(p(1, 2)).
point(p(3, 4)).

x(p(X, _), X).

shape(circle(p(0, 0), 5)).
shape(square(p(1, 1), 2)).

area(circle(_, R), A) :- A is R + R + R.
area(square(_, S), A) :- A is S + S.

% a meta-interpreter, keyed on true, ','/2 and anything else
solve(true) :- !.
solve((A, B)) :- !, solve(A), solve(B).
solve(H) :- rule(H, B), solve(B).

rule(app([], L, L), true).
rule(app([H|T], L, [H|R]), app(T, L, R)).
rule(nrev([], []), true).
rule(nrev([H|T], R), (nrev(T, RT), app(RT, [H], R))).

same(X, X).

?- point(P).
?- point(p(3, Y)).
?- point(p(5, _)).
?- x(p(7, 8), X).
?- shape(circle(C, R)).
?- shape(S), area(S, A).
?- same(f(X, b), f(a, Y)).
?- same(f(X), g(X)).
?- same(f(a), [a]).
?- same([f(X)|T], [f(1), g(2)]).
?- same(X, f(Y)), same(Y, 'hello world'(g)).
?- solve(app(X, Y, [1, 2])).
?- solve(nrev([1, 2, 3], R)).
