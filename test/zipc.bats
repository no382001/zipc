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

@test "nrev runs" {
    skip "phase 1: bodies with several goals"
    run_program nrev <<'EOF'
?- nrev([],R).
   R = [].
?- nrev([1,2,3],R).
   R = [3,2,1].
?- nrev([1,2],[1,2]).
   false.
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
