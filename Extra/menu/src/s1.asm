bits 16
org 0x7c00
s1:
  cli
  xor ax,ax
  mov ss,ax
  mov sp,0x7c00
  mov ds,ax
  mov es,ax
  sti
  cld
  mov [0x5fe],dl
  mov si,0x7c00
  mov di,0x600
  mov cx,0x100
  rep movsw
  jmp 0x0000:(go-0x7c00+0x600)
go:
  mov si,(dap1-0x7c00+0x600)
  mov dl,[0x5fe]
  mov ah,0x42
  int 0x13
  jc .e
  jmp 0x0000:0x0800
.e:
  mov si,(msg-0x7c00+0x600)
.p:
  lodsb
  or al,al
  jz .h
  mov ah,0x0e
  mov bx,7
  int 0x10
  jmp .p
.h:
  xor ah,ah
  int 0x16
  int 0x19
dap1: db 0x10,0, 24,0, 0x00,0x08, 0,0, 1,0,0,0,0,0,0,0
msg: db 'Boot stage2 error',0
times 440-($-$$) db 0
