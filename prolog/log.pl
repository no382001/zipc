:- module(log, [step/3]).

:- use_module(library(format)).

%% step(+Tag, +Format, +Args) is det.
%  Prints a progress line to stderr, in the same layout as the Makefile's.
step(Tag, Format, Args) :-
    format(user_error, "  ~s~t~12|", [Tag]),
    format(user_error, Format, Args),
    nl(user_error).
