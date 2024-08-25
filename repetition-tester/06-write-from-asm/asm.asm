global movAllBytesAsm
global cmpAllBytesAsm

section .text


movAllBytesAsm:
    xor rax, rax
.loop:
    mov [rcx + rax], al
    inc rax
    cmp rax, rdx
    jb .loop
    ret

cmpAllBytesAsm:
    xor rax, rax
.loop:
    inc rax
    cmp rax, rdx
    jb .loop
    ret
