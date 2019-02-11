lisp-nasm: lisp-nasm.o
	ld -nostdlib -static -o lisp-nasm lisp-nasm.o

doe: lisp-nasm
	cat swail.lisp - | ./lisp-nasm

kever: lisp-nasm
	gdb -x gdb-lisp ./lisp-nasm

proef: lisp-nasm
	cat swail.lisp proeven.lisp | ./lisp-nasm

lisp-nasm.o: lisp.nasm
	nasm -f elf64 -g -o lisp-nasm.o lisp.nasm

lisp: lisp.S
	gcc -m64 -nostdlib -static -gstabs+ -o lisp lisp.S

.PHONY: doe kever proef
