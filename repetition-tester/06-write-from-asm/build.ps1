nasm -f win64 asm.asm
zig build-exe .\reads_repeated.zig .\asm.obj
