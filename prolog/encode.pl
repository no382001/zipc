:- module(encode, [
    strings//1,
    string//1,
    u8//1,
    must_be_byte/1,
    u16//1,
    i32//1
]).

:- use_module(library(lists)).
:- use_module(library(dcgs)).
:- use_module(library(charsio)).

strings([]) --> [].
strings([S|Ss]) --> string(S), strings(Ss).

% A string is its UTF-8 length, its bytes and a terminating 0.
string(Cs) -->
    { chars_utf8bytes(Cs, Bs),
      (   memberchk(0, Bs) -> throw(error(domain_error(zip_string, Cs), string//1))
      ;   true
      ),
      length(Bs, N) },
    u8(N), seq(Bs), [0].

u8(N) --> { must_be_byte(N) }, [N].

must_be_byte(X) :-
    (   integer(X), X >= 0, X =< 255 -> true
    ;   throw(error(domain_error(byte, X), _))
    ).

u16(N) -->
    { (   integer(N), N >= 0, N =< 0xFFFF -> true
      ;   throw(error(domain_error(u16, N), u16//1))
      ),
      B0 is N /\ 0xFF,
      B1 is N >> 8 },
    [B0, B1].

% Two's complement, least significant byte first.
i32(N) -->
    { (   N >= -0x80000000, N =< 0x7FFFFFFF -> true
      ;   throw(error(domain_error(i32, N), i32//1))
      ),
      U is N /\ 0xFFFFFFFF,
      B0 is U /\ 0xFF,
      B1 is (U >> 8) /\ 0xFF,
      B2 is (U >> 16) /\ 0xFF,
      B3 is U >> 24 },
    [B0, B1, B2, B3].
