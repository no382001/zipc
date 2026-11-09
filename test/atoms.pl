% Atoms: in heads, in arguments, inside lists, and as indexing keys.

colour(red).
colour(green).
colour(blue).

complement(red, green).
complement(green, red).
complement(blue, orange).

pair(X, Y) :- colour(X), complement(X, Y).

first([X|_], X).

?- colour(red).
?- colour(C).
?- colour(purple).
?- colour(1).
?- complement(blue, X).
?- pair(X, Y).
?- first([a,b,c], X).
?- first(L, a).
?- first(['hello world'], X).
?- first([[]], X).
?- first(['[]'], []).
