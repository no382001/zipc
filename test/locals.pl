% variables that live in frames, and the last goal that may take a frame over

same(X, X).
id(_).
wrap(Y, f(Y)).

% writes over the frames above its caller
clobber(0) :- !.
clobber(N) :- z(_, _, _), N1 is N - 1, clobber(N1).
z(1, 2, 3).

% Y is unbound in this frame when the last goal takes the frame over.
mk(X) :- id(Y), wrap(Y, X).

% the older X is not bound to the younger Y, whose frame goes on return.
older(X) :- same(X, Y), id(Y).

% a structure holding a frame variable, built by a goal that is not last
inside(X) :- id(Y), same(X, g(Y)), clobber(5).

% a variable passed down through several frames taken over
down(X) :- down1(X).
down1(X) :- down2(X).
down2(7).

% frame variables bound in one clause, undone on backtracking into the next
pick(X) :- same(X, Y), same(Y, a).
pick(X) :- same(X, Y), same(Y, b).

?- mk(X), clobber(10), same(X, f(Z)), same(Z, 1).
?- mk(X), clobber(10).
?- older(X), clobber(10), same(X, 5).
?- older(X), clobber(10).
?- inside(X), clobber(10), same(X, g(1)).
?- down(X).
?- pick(X), clobber(3).
?- id(X), id(Y), same(X, Y), clobber(5), same(Y, 2).
