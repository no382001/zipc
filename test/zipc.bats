#!/usr/bin/env bats
# Run with `make test`, which builds build/zip and build/gen/gen.pl first.
# `make sanitize` runs them with ZIP=build/zip-san.

bats_require_minimum_version 1.5.0

setup() {
    ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    ZIPC="$ROOT/zipc"
    export ZIP=${ZIP:-$ROOT/build/zip}
    T=$BATS_TEST_TMPDIR
}

run_program() {
    local expected
    expected=$(cat)
    run --separate-stderr "$ZIPC" -r "$ROOT/test/$1.pl"
    [ "$status" -eq 0 ]
    diff -u <(echo "$expected") <(echo "$output")
}

@test "concat runs" {
    run_program concat <<'EOF'
?- concatenate([1,2],[3],Z).
   Z = [1,2,3].
?- concatenate(X,Y,[1,2,3]).
   X = [], Y = [1,2,3]
;  X = [1], Y = [2,3]
;  X = [1,2], Y = [3]
;  X = [1,2,3], Y = []
;  false.
?- concatenate([1],[2],[1,3]).
   false.
EOF
}

@test "concat compiles to the same image as the hand-written code" {
    "$ZIPC" "$ROOT/test/concat.pl" "$T/c.bin"
    "$ZIPC" -a "$ROOT/test/concat.asm.pl" "$T/a.bin"
    cmp "$T/c.bin" "$T/a.bin"
}

@test "atoms run" {
    run_program atoms <<'EOF'
?- colour(red).
   true.
?- colour(C).
   C = red
;  C = green
;  C = blue.
?- colour(purple).
   false.
?- colour(1).
   false.
?- complement(blue,X).
   X = orange.
?- pair(X,Y).
   X = red, Y = green
;  X = green, Y = red
;  X = blue, Y = orange.
?- first([a,b,c],X).
   X = a.
?- first(L,a).
   L = [a|_G1].
?- first(['hello world'],X).
   X = 'hello world'.
?- first([[]],X).
   X = [].
?- first([[]],[]).
   true.
EOF
}

@test "atoms are quoted as writeq quotes them" {
    cat > "$T/q.pl" <<'EOF'
q(['A', 'don''t', +, '+a', ;, '', 'a\\b', 'tab\there', !, {}, ',', '|', '.', '..', aB_9, '_x', '1a', 'a\nb']).
?- q(X).
EOF
    run --separate-stderr "$ZIPC" -r "$T/q.pl"
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "   X = ['A','don\\'t',+,'+a',;,'','a\\\\b','tab\\there',!,{},',','|','.',..,aB_9,'_x','1a','a\\nb']." ]
}

@test "nrev runs" {
    run_program nrev <<'EOF'
?- nrev([],R).
   R = [].
?- nrev([1,2,3],R).
   R = [3,2,1].
?- nrev([1,2],[1,2]).
   false.
EOF
}

@test "a query with several goals backtracks into each" {
    cat > "$T/q.pl" <<EOF
:- consult('$ROOT/test/concat').
?- concatenate(X,Y,[1,2]), concatenate(Y,X,Z).
EOF
    run --separate-stderr "$ZIPC" -r "$T/q.pl"
    [ "$status" -eq 0 ]
    diff -u - <(echo "$output") <<'EOF'
?- concatenate(X,Y,[1,2]),concatenate(Y,X,Z).
   X = [], Y = [1,2], Z = [1,2]
;  X = [1], Y = [2], Z = [2,1]
;  X = [1,2], Y = [], Z = [1,2]
;  false.
EOF
}

@test "anonymous variables in heads and bodies" {
    cat > "$T/v.pl" <<'EOF'
first([X|_], X).
g(_, 1).
h(R) :- g(_, R).
?- first([1,2], X).
?- first(L, 1).
?- h(R).
EOF
    run --separate-stderr "$ZIPC" -r "$T/v.pl"
    [ "$status" -eq 0 ]
    diff -u - <(echo "$output") <<'EOF'
?- first([1,2],X).
   X = 1.
?- first(L,1).
   L = [1|_G1].
?- h(R).
   R = 1.
EOF
}

@test "steps go to stderr, not stdout" {
    run --separate-stderr "$ZIPC" "$ROOT/test/concat.pl" "$T/c.bin"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"read      $ROOT/test/concat.pl"* ]]
    [[ "$stderr" == *"compile   2 clauses, 3 queries"* ]]
    [[ "$stderr" == *"write     $T/c.bin"* ]]
}

@test "-d prints the code of each procedure and query" {
    run --separate-stderr "$ZIPC" -d "$ROOT/test/concat.pl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"concatenate/3"* ]]
    [[ "$output" == *"?- concatenate([1,2],[3],Z)."* ]]
    [[ "$stderr" == *"compile   2 clauses, 3 queries"* ]]
}

@test "-r compiles, then runs on the VM" {
    run --separate-stderr "$ZIPC" -r "$ROOT/test/concat.pl"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"write     "* ]]
    [[ "$stderr" == *"run       $ROOT/test/concat.pl"* ]]
    [[ "$output" == "?- concatenate([1,2],[3],Z)."* ]]
}

@test "-r with IMAGE keeps the image" {
    run --separate-stderr "$ZIPC" -r "$ROOT/test/concat.pl" "$T/c.bin"
    [ "$status" -eq 0 ]
    [ -s "$T/c.bin" ]
}

@test "-r does not run when compiling fails" {
    printf 'f :- g.\n?- f.\n' > "$T/u.pl"
    run --separate-stderr "$ZIPC" -r "$T/u.pl"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"undefined procedure g/0"* ]]
    [[ "$stderr" != *"run       "* ]]
    [ -z "$output" ]
}

@test "-r uses the VM in ZIP" {
    ZIP=/nonexistent run "$ZIPC" -r "$ROOT/test/concat.pl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no VM at /nonexistent"* ]]
}

@test "-ar runs hand-written code" {
    run --separate-stderr "$ZIPC" -ar "$ROOT/test/concat.asm.pl"
    [ "$status" -eq 0 ]
    [[ "$output" == "?- concatenate([1,2],[3],Z)."* ]]
}

@test "-dr lists, then runs, reading the file once" {
    run --separate-stderr "$ZIPC" -dr "$ROOT/test/concat.pl"
    [ "$status" -eq 0 ]
    [[ "$output" == "concatenate/3"* ]]
    [[ "$output" == *"   Z = [1,2,3]."* ]]
    [ "$(grep -c 'read  ' <<< "$stderr")" -eq 1 ]
}

@test "chained and separate flags are the same" {
    run --separate-stderr "$ZIPC" -dr "$ROOT/test/concat.pl"
    local chained=$output
    run --separate-stderr "$ZIPC" -d -r "$ROOT/test/concat.pl"
    [ "$output" = "$chained" ]
}

@test "-d with IMAGE lists and writes" {
    run --separate-stderr "$ZIPC" -d "$ROOT/test/concat.pl" "$T/c.bin"
    [ "$status" -eq 0 ]
    [[ "$output" == "concatenate/3"* ]]
    [ -s "$T/c.bin" ]
}

@test "usage errors" {
    for args in "" "$ROOT/test/concat.pl" "-x $ROOT/test/concat.pl" "-ad $ROOT/test/concat.asm.pl" "-r"; do
        run $ZIPC $args
        [ "$status" -eq 2 ]
        [[ "$output" == usage:* ]]
    done
}

@test "an error writing the image is not a usage error" {
    # 256 constants in one clause: more than a byte can index
    echo "p([$(seq -s, 1000 1255)])." > "$T/many.pl"
    run --separate-stderr "$ZIPC" "$T/many.pl" "$T/many.bin"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"domain_error(byte,256)"* ]]
    [[ "$stderr" != *usage:* ]]
}

@test "a query longer than 255 bytes runs" {
    local list
    list=$(seq -s, 1 100)
    printf 'p([%s]).\n?- p([%s]).\n' "$list" "$list" > "$T/long.pl"
    run --separate-stderr "$ZIPC" -r "$T/long.pl"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf -- '?- p([%s]).\n   true.' "$list")" ]
}

@test "-h prints the usage made from the specs" {
    run --separate-stderr "$ZIPC" -h
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "usage: zipc [-adrh] [--color] FILE [IMAGE]" ]]
    [[ "$output" == *"-r, --run"* ]]
    [[ "$output" == *"    --color"* ]]
}

@test "long flags work the same as short ones" {
    run --separate-stderr "$ZIPC" -dr "$ROOT/test/concat.pl"
    local short=$output
    run --separate-stderr "$ZIPC" --dump --run "$ROOT/test/concat.pl"
    [ "$status" -eq 0 ]
    [ "$output" = "$short" ]
}

@test "unknown options are named" {
    run "$ZIPC" --nope "$ROOT/test/concat.pl"
    [ "$status" -eq 2 ]
    [[ "$output" == *"zipc: unknown option --nope"* ]]
}

@test "consult takes the clauses but not the queries" {
    cat > "$T/lib.pl" <<'EOF'
p(1).
?- p(X).
EOF
    cat > "$T/main.pl" <<'EOF'
:- consult(lib).
?- p(1).
EOF
    run --separate-stderr "$ZIPC" -d "$T/main.pl"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"consult   $T/lib.pl"* ]]
    [[ "$stderr" == *"compile   1 clauses, 1 queries"* ]]
}

@test "consult resolves relative to the consulting file, .pl optional" {
    run "$ZIPC" -d "$ROOT/test/nrev.pl"
    [[ "$output" == *"consult   $ROOT/test/concat.pl"* ]]
}

@test "consult takes an absolute path" {
    echo ":- consult('$ROOT/test/concat.pl')." > "$T/abs.pl"
    echo "?- concatenate([1],[2],X)." >> "$T/abs.pl"
    run --separate-stderr "$ZIPC" -r "$T/abs.pl"
    [ "$output" = "$(printf '?- concatenate([1],[2],X).\n   X = [1,2].')" ]
}

@test "consult reads each file once, even in a cycle" {
    echo ":- consult(b). p." > "$T/a.pl"
    echo ":- consult(a). q." > "$T/b.pl"
    run --separate-stderr "$ZIPC" -d "$T/a.pl"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"consult   $T/a.pl (already read)"* ]]
    [[ "$stderr" == *"compile   2 clauses, 0 queries"* ]]
}

@test "consult of a missing file fails" {
    echo ":- consult(nope)." > "$T/m.pl"
    run "$ZIPC" "$T/m.pl" "$T/m.bin"
    [ "$status" -eq 1 ]
    [[ "$output" == *existence_error* ]]
}

@test "other directives are rejected" {
    echo ":- dynamic(p/1)." > "$T/d.pl"
    run "$ZIPC" "$T/d.pl" "$T/d.bin"
    [ "$status" -eq 1 ]
    [[ "$output" == *"domain_error(directive"* ]]
}

@test "undefined procedures are all listed with their callers" {
    printf 'f(X) :- g(X).\n?- h(1).\n?- f(1).\n' > "$T/u.pl"
    run --separate-stderr "$ZIPC" "$T/u.pl" "$T/u.bin"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"undefined procedure g/1, called by f/1"* ]]
    [[ "$stderr" == *"undefined procedure h/1, called by ?- h(1)."* ]]
    [[ "$stderr" != *"f/1, called by"* ]]
    [ ! -e "$T/u.bin" ]
}

@test "undefined procedures in hand-written code are caught too" {
    cat > "$T/u.asm.pl" <<'EOF'
zip_query("g.", [], [argmode(8), call(g/0), halt]).
EOF
    run "$ZIPC" -a "$T/u.asm.pl" "$T/u.bin"
    [ "$status" -eq 1 ]
    [[ "$output" == *"undefined procedure g/0, called by ?- g."* ]]
}

@test "control constructs are rejected by name" {
    printf 'p(1).\nq(X) :- ( p(X) ; X = 2 ).\n' > "$T/c.pl"
    run --separate-stderr "$ZIPC" "$T/c.pl" "$T/c.bin"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"(;)/2 is not supported yet: in q(A):-p(A);A=2"* ]]
    [ ! -e "$T/c.bin" ]
}

@test "structures run" {
    run_program struct <<'EOF'
?- point(P).
   P = p(1,2)
;  P = p(3,4).
?- point(p(3,Y)).
   Y = 4.
?- point(p(5,A)).
   false.
?- x(p(7,8),X).
   X = 7.
?- shape(circle(C,R)).
   C = p(0,0), R = 5.
?- shape(S),area(S,A).
   S = circle(p(0,0),5), A = 15
;  S = square(p(1,1),2), A = 4.
?- same(f(X,b),f(a,Y)).
   X = a, Y = b.
?- same(f(X),g(X)).
   false.
?- same(f(a),[a]).
   false.
?- same([f(X)|T],[f(1),g(2)]).
   X = 1, T = [g(2)].
?- same(X,f(Y)),same(Y,'hello world'(g)).
   X = f('hello world'(g)), Y = 'hello world'(g).
?- solve(app(X,Y,[1,2])).
   X = [], Y = [1,2]
;  X = [1], Y = [2]
;  X = [1,2], Y = []
;  false.
?- solve(nrev([1,2,3],R)).
   R = [3,2,1]
;  false.
EOF
}

@test "cut and fail run" {
    run_program cut <<'EOF2'
?- first(X).
   X = red.
?- t(X).
   X = 1.
?- t(2).
   true.
?- p(X,Y).
   X = red, Y = red
;  X = red, Y = green
;  X = red, Y = blue.
?- q(X).
   X = red
;  X = yellow.
?- nope(red).
   false.
?- nope(1).
   true.
?- c.
   true.
?- f.
   false.
?- colour(X),!.
   X = red.
?- colour(X),fail.
   false.
EOF2
}

@test "arithmetic runs" {
    run_program arith <<'EOF2'
?- fib(10,F).
   F = 55.
?- range(298,302,L).
   L = [298,299,300,301,302].
?- X is 1+2-300.
   X = -297.
?- X is-7-1.
   X = -8.
?- 3 is 1+2.
   true.
?- 4 is 1+2.
   false.
?- a is 1.
   false.
?- five(X),X>=5,X=<5,X>4,X=:=5,X=\=6.
   X = 5.
?- five(X),X>5.
   false.
?- count(1).
   true.
EOF2
}

@test "arithmetic on an unbound or non-integer value is an error at run time" {
    printf 'inc(X, Y) :- Y is X + 1.\n?- inc(X, Y).\n' > "$T/u.pl"
    run --separate-stderr "$ZIPC" -r "$T/u.pl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"error: instantiation error"* ]]
    printf 'inc(X, Y) :- Y is X + 1.\n?- inc(a, Y).\n' > "$T/t.pl"
    run --separate-stderr "$ZIPC" -r "$T/t.pl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"error: type error: evaluable"* ]]
}

@test "unsupported arithmetic is rejected at compile time" {
    printf 'p(X) :- Y is X * 2, q(Y).\nq(_).\n' > "$T/m.pl"
    run --separate-stderr "$ZIPC" "$T/m.pl" "$T/m.bin"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"arithmetic with (*)/2 is not supported yet"* ]]
    printf 'p(X) :- X is Y + 1.\n' > "$T/v.pl"
    run --separate-stderr "$ZIPC" "$T/v.pl" "$T/v.bin"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"a variable in an arithmetic expression has no value yet"* ]]
}

@test "integers outside 0..255 are constants" {
    printf 'n(300).\nn(-1).\n?- n(X).\n?- n(300).\n' > "$T/n.pl"
    run --separate-stderr "$ZIPC" -r "$T/n.pl"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '?- n(X).\n   X = 300\n;  X = -1.\n?- n(300).\n   true.')" ]
}

@test "frame variables outlive neither their frame nor a backtrack" {
    run_program locals <<'EOF'
?- mk(X),clobber(10),same(X,f(Z)),same(Z,1).
   X = f(1), Z = 1.
?- mk(X),clobber(10).
   X = f(_G0).
?- older(X),clobber(10),same(X,5).
   X = 5.
?- older(X),clobber(10).
   X = _L8.
?- inside(X),clobber(10),same(X,g(1)).
   X = g(1).
?- down(X).
   X = 7.
?- pick(X),clobber(3).
   X = a
;  X = b.
?- id(X),id(Y),same(X,Y),clobber(5),same(Y,2).
   X = 2, Y = 2.
EOF
}

@test "a cut tidies the trail, but keeps what an older choice point undoes" {
    run_program trail <<'EOF'
?- fib(21,F).
   F = 10946.
?- c(X),k(X,Y).
   X = 1, Y = 1
;  X = 2, Y = 2.
EOF
}
