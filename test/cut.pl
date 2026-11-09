% cut, and fail

colour(red).
colour(green).
colour(blue).

first(X) :- colour(X), !.

t(1) :- !.
t(2).

p(X, Y) :- colour(X), !, colour(Y).

q(X) :- first(X).
q(yellow).

nope(X) :- colour(X), !, fail.
nope(_).

c :- !.
c :- c.
f :- fail.

?- first(X).
?- t(X).
?- t(2).
?- p(X,Y).
?- q(X).
?- nope(red).
?- nope(1).
?- c.
?- f.
?- colour(X), !.
?- colour(X), fail.
