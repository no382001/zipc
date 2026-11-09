(t + v)
tags are 8 bit
val is 32 -> single prec ftp

int
float
box
atom
term
cons
link
undef
funct
block
empty
termin
clause
table
tabref
proc

special case for comp. term/n is repr. by term ptr to a cell of n+1 words where the first cell is a functor tagged to the functor cell, everything else follows

special case for list constr. ./2 for comp.terms

cons cell points to head and tail, an alternative is to represent lists as CT of /2 using a term tagged ptr to a cell, functor, head, tail


poss. to repr. proc. clas.tables and functors as CT or tables, would be more simple and simple data struct but would cost more memory fetches -> i think we can make this tradeoff, it would be great to have something i can eventually hand-roll into arm assembly, but is it worth the tradeoff? it scales linearly probably, if its really much simpler to implement then i guess it is fine for the POC

- use compound terms for the fixed-shape records and for clause chains keep explicit first/last pointers instead of a cons list.

func or /0 is an atom here, so no unnec. func cells

lots of diagnostic things in the data layout, that we can probably cut out or conditionally not include at the end

atom -> 3 word cell
1. hash_chain followed by atom_ptr or a termin word
2. funct chain, fwd by a functor word or termin word, all functors having the same name but diff arity are linked into this chain
3. BOX tagged word -> atom string name

functor -> 4 word cell
1. atom of its name
2. int of arity
3. funct word pointing to the next same name diff arity functor
4. proc word -> proc cell if any

proc -> 6 word cell
1. int word with various? what? flags
2. atom word naming the module where defined
3. word where the module is visible
4. funct associated
5. proc, next proc with the same functor but with different module characteristics
6. clauses: prim proc -> int for identif. prim; otherwise a TABREF pointing to a two component table. first comp is a clause, poiting to the first clause second points to the last clause

clause -> cell which is a single prolog clause, they are chained, so they can be removed const time, clause is min 7 words, 8th and subsequent words are some sort of external references table for the clause, used as references to structures used by the zip instructions of the clause?  i dont really get this.
xc register offset is accessing these references apparently,
1. int with flags
2. word used as a search key for the database. "the key is related to the first argument of the clause" so FAI?; key is same for first arg of constants? undef word for variables with no first argument, principal functor for CT? const tagged word having a dont care val field for ./2. idk what half of this means
3. proc word to the proc owning this clause
4. box poiting to the bytecode block containing the zip instructions for this clause. bytecode only contains instr and args. args are lit val or offsets from a register so no tagged word appers as an argument.
> "The reason for this is so that instructions can be easily decoded on byte-boundaries, and so that is it never necessary to scan the code block to find references (as required for garbage collection). Instead, tagged words appear in the external references table, and instructions access hese using their argument as an offset into the table. An additional advantage is that external references are represented uniquely, thus improving compaction.
i should maybe make a graph of these references, this is getting very hard to understand, i dont understand how gc can work in this way.
5. int for total size of the cell in words
6. clause word -> to the prev clause or a tabref word
7. clause word -> next clause or a termin word

term or /n term -> cell of n + 1, 1st is a functor pointer to the functor cell. next words are components to the compound term.

box: byte string of length n is repr. as a box word poiting to a block cell of len floor((n-1)/4)+2 1st word has a t. and v.
> "Subsequent words contain bytes packed four to the word, null-padded to the nearest word. The padding is required because boxes are compared with each other word-at-a-time." i dont really understand this requirement.

tabref: vector of len n is repr by this, tabref points to a table cell of n+1 len, where the first cell is a TABLE tag and val n + 1, next n words have the n components. ok? iguess.

registers:
pm processor mode
xc curr. clause ptr
d curr. data ptr
pc
l curr. target local frame
cl curr. source local frame
cp forward continuation program counter
cl0 f.c. local frame
g glob. stack alloc'd top
g0 glob. stack commited top
h heap freelist
bl backtrack cont. local frame
bg bt. glob. stack top
bp bt. cont. clause
tr trail alloc'd top
tr0 trail commited top

> "Some of the above registers are redundant in that they are caches for slots in the current local frame. Other registers not mentioned here are scratchpad registers whose contents are valid only during the execution of a single ZIP machine instruction."

skipped 5: 
storage alloc

and went to 6: zip instr

ARG, COPY, MATCH

i should word code instead of byte code, clocksin talks about this aswell.
> "Furthermore, a word-sized instruction could be represented as the starting address of the emulator definition of the instruction, further reducing the instruction dispatching overhead by means of the so-called "threaded code" technique.