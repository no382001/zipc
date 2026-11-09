# zipc (working title)

> The goal of the project is to scaffold the VM to a degree where I can compare it with the current trilog runtime. 

A compiler from Prolog to the ZIP virtual machine, and the VM itself, in C. ZIP is the abstract machine from Clocksin's *Design and Simulation of a Sequential Prolog Machine* (1984); the papers are in [`doc/`](doc/).

zipc is meant to become the backend of [trilog](https://github.com/no382001/trilog) if the MVP succeeds, or just stay as a faster separate Prolog compilable runtime, I am not really sure yet. Either way, trilog interprets clauses as terms with the ABC algorithm, and compiling them to ZIP should make the same programs run in fewer instructions and less memory, which should help with [trilog's main target](https://github.com/no382001/trilog#current-goals).

The compiler is written in Prolog and runs on [Scryer Prolog](https://codeberg.org/mthom/scryer-prolog). It writes a binary image, which the VM in [`src/`](src/) loads and runs.

