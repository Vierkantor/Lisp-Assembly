# Lisp-Assembly
A minimalist Lisp implementation in x86_64 assembly.
Note that most of the code is in Dutch, since it was a personal project.

This is a minimalist Lisp implementation, entirely written within x86_64 assembly language and in the Lisp itself.
The project was inspired by (and some parts of the implementation are based on) Jones Forth, a Forth implementation also written entirely in (32 bits) x86 assembly language,
and a nice example of literate programming.

The basic language is implemented in `lisp.nasm`. This language is extended using its own primitives in the "standard library" file `swail.lisp` to a more complete Lisp dialect. The `Makefile` includes the following commands:

 - `make` # To make the executable, `lisp-nasm`
 - `make doe` # To run this executable, together with the standard library, giving a prompt.
 - `make kever` # To run the executable in GDB, together with useful command's for debugging (see `lisp_gdb.py`)
 - `make proef` # To run a few test cases.

Requirements
------------

 - A computer with x86_64 processor running Linux.
 - A recent version of NASM, the Netwide Assembler, for example version 2.13.
 - A linker, for example the `ld` that is included with GCC.
 - (GNU) Make
 - Optionally: GDB, the GNU debugger, with Python3 support, for debugging.

Features
--------

 - Minimalism
 - Built on x86_64 assembly
 - Dynamical scoping
 - Garbage collection
 - Configurable primitives
