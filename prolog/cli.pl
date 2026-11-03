:- module(cli, [zipc/0]).

:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(lambda)).
:- use_module(library(os)).
:- use_module(library(files)).
:- use_module(getopt).
:- use_module(log).
:- use_module(build).

% The zipc command line. The zipc script sets ZIP, the VM, and ZIPC_TMP, a
% temporary file for the image of -r without IMAGE.

specs([
    flag(asm,   a, set(asm),   "FILE is hand-written code (FILE.asm.pl)"),
    flag(dump,  d, set(dump),  "print the code for each clause and query"),
    flag(run,   r, set(run),   "run the image on the VM ($ZIP); IMAGE is optional"),
    flag(color, -, set(color), "ANSI colors in the listing"),
    flag(help,  h, set(help),  "print this help")
]).

usage(U) :- specs(Specs), phrase(usage("zipc", "FILE [IMAGE]", Specs), U).

:- dynamic(is_set/1).
set(X) :- assertz(is_set(X)).

%% zipc is det.
%  Runs the command line from argv/1, then halts: 0 on success, 1 on an
%  error, 2 on a usage error.
zipc :-
    argv(Args),
    catch(zipc(Args), E, (report(E, Code), halt(Code))).

zipc(Args) :-
    retractall(is_set(_)),
    specs(Specs),
    getopt(Specs, Args, Positional),
    (   is_set(help) -> usage(U), format("~s", [U])
    ;   files(Positional, Source, Image0),
        (   is_set(run) -> vm(Zip) ; true ),
        (   is_set(run), Image0 == none -> temporary_image(Image) ; Image = Image0 ),
        (   is_set(asm) ->
            (   is_set(dump) -> throw(usage("-d does not work with -a")) ; true ),
            (   Image == none -> throw(usage("-a needs an IMAGE, or -r")) ; true ),
            assemble(Source, Image)
        ;   flag_value(dump, Dump),
            flag_value(color, Color),
            (   Image == none, Dump == false -> throw(usage("give an IMAGE, -d or -r")) ; true ),
            build(Source, Dump, Color, Image)
        ),
        (   is_set(run) -> run(Zip, Source, Image) ; true )
    ).

temporary_image(Image) :-
    (   getenv("ZIPC_TMP", T) -> atom_chars(Image, T)
    ;   throw(usage("-r without IMAGE needs ZIPC_TMP, as the zipc script sets"))
    ).

%% vm(-Zip) is det.
%  Zip is the VM from ZIP, default build/zip. Throws no_vm(Zip) if it is not there.
vm(Zip) :-
    (   getenv("ZIP", Zip) -> true ; Zip = "build/zip" ),
    (   file_exists(Zip) -> true ; throw(no_vm(Zip)) ).

%% run(+Zip, +Source, +Image) is det.
%  Runs Image on the VM Zip. Throws vm(Status) if the VM exits with a nonzero
%  Status.
run(Zip, Source, Image) :-
    step("run", "~a", [Source]),
    atom_chars(Image, I),
    phrase((quoted(Zip), " ", quoted(I)), Command),
    flush_output,
    shell(Command, Status),
    (   Status =:= 0 -> true ; throw(vm(Status)) ).

% A shell word for Cs: in single quotes, a ' in it as '\''.
quoted(Cs) --> "'", quoted_(Cs), "'".
quoted_([]) --> [].
quoted_([C|Cs]) --> ( { C == '\'' } -> "'\\''" ; [C] ), quoted_(Cs).

files([S], Source, none) :- !, atom_chars(Source, S).
files([S, I], Source, Image) :- !, atom_chars(Source, S), atom_chars(Image, I).
files(_, _, _) :- throw(usage("give FILE and an optional IMAGE")).

flag_value(F, V) :- ( is_set(F) -> V = true ; V = false ).

%% report(+Error, -Code) is det.
%  Prints Error to stderr; Code is the exit code for it.
report(usage(Why), 2) :- !,
    usage(U), format(user_error, "~szipc: ~s~n", [U, Why]).
report(error(existence_error(option, Opt), getopt/3), 2) :- !,
    usage(U), format(user_error, "~szipc: unknown option ~a~n", [U, Opt]).
report(error(E, getopt/3), 2) :- !,
    usage(U), format(user_error, "~szipc: ~q~n", [U, E]).
report(no_vm(Zip), 1) :- !,
    format(user_error, "zipc: no VM at ~s, run make~n", [Zip]).
report(vm(Status), Status) :- !. % the VM has said why
report(error(existence_error(procedures, Undefined), _), 1) :- !,
    maplist(\ (P-From)^format(user_error, "undefined procedure ~w, called by ~s~n", [P, From]), Undefined).
report(E, 1) :-
    format(user_error, "zipc: ~q~n", [E]).
