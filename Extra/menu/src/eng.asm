bits 16
org 0x800
%macro GETB 0
  a32 mov al,[es:esi]
  inc esi
%endmacro
%ifdef DBG
H equ 0x1000
%define ENGSZ 0x800
%else
H equ 0xF00
%define ENGSZ 0x700
%endif
BUFV equ 0x6000
BUFM equ 0x6200
PALT equ 0x6400
DECB equ 0x20000
; --- config block, patched by the installer (all LBAs absolute; 0 = absent) ---
  jmp short stage2
  nop
  nop
cfg_magic db 'NC63'
mac_lba dd 0
xp_lba dd 0
bank_lba dd 0
stage2:
  cld
  xor ax,ax
  mov ds,ax
  mov es,ax
  mov al,[0x5fe]
  mov [drive],al
  call a20
  cmp dword [xp_lba],0
  jne .two
  mov byte [sel],0          ; no Windows partition: boot macOS directly
  jmp boot
.two:
  call vbe_init
  cmp dword [bank_lba],0
  jne .hb
  mov byte [gfx],0          ; no room for the image bank: text menu
.hb:
  cmp byte [gfx],0
  je .nog
  call load_bank
.nog:
  cmp byte [gfx],0
  jne .g
  mov ax,3
  int 0x10
  jmp .m
.g:
  mov si,[H]
  call runl
.m:
menu:
  call items
  call countline
  mov ah,0
  int 0x1a
  mov [last],dx
.wait:
  mov ah,1
  int 0x16
  jnz .key
  cmp byte [auto],0
  je .wait
  mov ah,0
  int 0x1a
  mov ax,dx
  sub ax,[last]
  cmp ax,18
  jb .wait
  add word [last],18
  dec byte [secs]
  jz boot
  call countline
  jmp .wait
.key:
  mov ah,0
  int 0x16
  mov byte [auto],0
  cmp al,13
  je boot
  cmp al,'1'
  jne .n1
  mov byte [sel],0
  jmp boot
.n1:
  cmp al,'2'
  jne .n2
  mov byte [sel],1
  jmp boot
.n2:
  cmp ah,0x48
  je .up
  cmp ah,0x4b
  je .up
  cmp ah,0x50
  je .dn
  cmp ah,0x4d
  je .dn
  jmp menu
.up:
  mov byte [sel],0
  jmp menu
.dn:
  mov byte [sel],1
  jmp menu

items:
  cmp byte [gfx],0
  je titems
  mov si,[H+2]
  cmp byte [sel],0
  jne .a
  mov si,[H+4]
.a:
  call runl
  mov si,[H+6]
  cmp byte [sel],1
  jne .b
  mov si,[H+8]
.b:
  call runl
  ret

countline:
  cmp byte [gfx],0
  je tcount
  mov si,[H+10]
  call runl
  cmp byte [auto],0
  je .z
  mov ax,[H+16]
  xor bx,bx
  mov bl,[secs]
  mul bx
  shr ax,3
  mov [tmp+5],ax
  mov ax,[H+12]
  mov [tmp+1],ax
  mov ax,[H+14]
  mov [tmp+3],ax
  mov ax,[H+18]
  mov [tmp+7],ax
  mov eax,[H+20]
  mov [tmp+9],eax
  mov si,tmp
  call runl
.z:
  ret

; ---------- text fallback ----------
titems:
  mov si,t0n
  cmp byte [sel],0
  jne .a
  mov si,t0s
.a:
  mov dx,0x0a14
  call tputs
  mov si,t1n
  cmp byte [sel],1
  jne .b
  mov si,t1s
.b:
  mov dx,0x0c14
  call tputs
  ret
tcount:
  mov si,t_auto
  cmp byte [auto],0
  jne .a
  mov si,t_press
.a:
  mov di,buf
  mov al,[secs]
  xor ah,ah
  mov bl,10
  div bl
  add ax,0x3030
  mov bx,ax
.c:
  lodsb
  cmp al,'#'
  jne .s
  mov al,bl
  mov bl,bh
.s:
  mov [di],al
  inc di
  test al,al
  jnz .c
  mov si,buf
  mov dx,0x0f14
  call tputs
  ret
tputs:
  mov ah,2
  xor bh,bh
  int 0x10
.l:
  lodsb
  test al,al
  jz .d
  mov ah,0x0e
  mov bx,7
  int 0x10
  jmp .l
.d:
  ret

; ---------- VBE ----------
vbe_init:
  mov byte [gfx],0

%ifdef DBG
  call dbg_enum
%endif
  mov dword [BUFV],0x32454256
  mov di,BUFV
  mov ax,0x4f00
  int 0x10
  cmp ax,0x004f
  jne .no
  mov si,[BUFV+14]
  mov ax,[BUFV+16]
  mov fs,ax
.lp:
  mov cx,[fs:si]
  add si,2
  cmp cx,0xffff
  je .no
  mov [mode],cx
  mov ax,0x4f01
  mov di,BUFM
  int 0x10
  cmp ax,0x004f
  jne .lp
  mov ax,[BUFM]
  and ax,0x0081
  cmp ax,0x0081
  jne .lp
  cmp word [BUFM+0x12],1024
  jne .lp
  cmp word [BUFM+0x14],768
  jne .lp
  cmp byte [BUFM+0x19],32
  jne .lp
  mov bx,[mode]
  or bx,0x4000
  mov ax,0x4f02
  int 0x10
  cmp ax,0x004f
  jne .no
  mov eax,[BUFM+0x28]
  mov [lfb],eax
  mov ax,[BUFM+0x10]
  mov [pitch],ax
  mov ax,0x4f06
  mov bl,1
  int 0x10
  cmp ax,0x004f
  jne .s7
  test bx,bx
  jz .s7
  mov [pitch],bx
.s7:
  mov ax,0x4f07
  xor bx,bx
  xor cx,cx
  xor dx,dx
  int 0x10
  mov byte [gfx],1
.no:
  ret

a20:
  call .chk
  jnc .done
  mov ax,0x2401
  int 0x15
  call .chk
  jnc .done
  in al,0x92
  test al,2
  jnz .k
  or al,2
  and al,0xfe
  out 0x92,al
.k:
  call .chk
  jnc .done
  call .kw
  mov al,0xd1
  out 0x64,al
  call .kw
  mov al,0xdf
  out 0x60,al
  call .kw
.done:
  ret
.kw:
  mov cx,0xffff
.kl:
  in al,0x64
  test al,2
  loopnz .kl
  ret
.chk:
  push ds
  push es
  push si
  push di
  xor ax,ax
  mov ds,ax
  dec ax
  mov es,ax
  mov si,0x500
  mov di,0x510
  mov al,[si]
  mov ah,al
  not al
  mov [si],al
  cmp al,[es:di]
  mov [si],ah
  pop di
  pop si
  pop es
  pop ds
  jne .on
  stc
  ret
.on:
  clc
  ret

unreal:
  cli
  lgdt [gdtr]
  mov eax,cr0
  or al,1
  mov cr0,eax
  jmp short .a
.a:
  mov bx,8
  mov es,bx
  mov fs,bx
  and al,0xfe
  mov cr0,eax
  jmp short .b
.b:
  ret

runl:
  call unreal
  call run
  sti
  ret
run:
  lodsb
  test al,al
  jz .ret
  cmp al,1
  je .rect
  lodsw
  mov bx,ax
  lodsw
  call calcdi
  lodsw
  mov [rw],ax
  lodsw
  mov [rh],ax
  lodsd
  push si
  mov esi,eax
  call loadimg
  mov esi,DECB
.br:
  push edi
  mov cx,[rw]
.bp:
  a32 mov al,[es:esi]
  inc esi
  test al,al
  jz .sk
  movzx ebx,al
  a32 mov ebx,[PALT+ebx*4]
  a32 mov [es:edi],ebx
.sk:
  add edi,4
  dec cx
  jnz .bp
  pop edi
  movzx ebx,word [pitch]
  add edi,ebx
  dec word [rh]
  jnz .br
  pop si
  jmp run
.ret:
  ret
.rect:
  lodsw
  mov bx,ax
  lodsw
  call calcdi
  lodsw
  mov [rw],ax
  lodsw
  mov dx,ax
  lodsd
.rl:
  push edi
  movzx ecx,word [rw]
  a32 rep stosd
  pop edi
  movzx ebx,word [pitch]
  add edi,ebx
  dec dx
  jnz .rl
  jmp run

calcdi:
  movzx eax,ax
  movzx edx,word [pitch]
  imul eax,edx
  movzx ebx,bx
  shl ebx,2
  add eax,ebx
  add eax,[lfb]
  mov edi,eax
  ret

loadimg:
  push edi
  GETB
  movzx cx,al
  mov di,PALT+4
.pl:
  GETB
  mov bl,al
  GETB
  mov bh,al
  GETB
  movzx eax,al
  shl eax,16
  mov ax,bx
  stosd
  dec cx
  jnz .pl
  movzx eax,word [rw]
  movzx ebx,word [rh]
  imul eax,ebx
  mov edi,DECB
  lea ebp,[edi+eax]
.fl:
  cmp edi,ebp
  jae .done
  GETB
  mov dl,al
  mov dh,8
.it:
  cmp edi,ebp
  jae .done
  shr dl,1
  jnc .mt
  GETB
  a32 mov [es:edi],al
  inc edi
  jmp .nx
.mt:
  GETB
  mov cl,al
  GETB
  mov ch,al
  mov bx,cx
  shr bh,4
  movzx ebx,bx
  inc ebx
  mov eax,edi
  sub eax,ebx
  and ch,15
  add ch,3
.cp:
  a32 mov bl,[es:eax]
  a32 mov [es:edi],bl
  inc edi
  inc eax
  dec ch
  jnz .cp
.nx:
  dec dh
  jnz .it
  jmp .fl
.done:
  pop edi
  ret

load_bank:
  mov word [dap_cnt],62
  mov word [dap+4],0
  mov word [dap+6],0x4000
  mov ax,[bank_lba]
  mov [dap_lba],ax
  mov ax,[bank_lba+2]
  mov [dap_lba+2],ax
  mov dl,[drive]
  mov si,dap
  mov ah,0x42
  int 0x13
  mov word [dap+4],0x7c00
  mov word [dap+6],0
  jnc .ok
  mov ax,3
  int 0x10
  mov byte [gfx],0
.ok:
  ret

boot:
  mov byte [splash],0
  cmp byte [gfx],0
  je .nosp
  cmp byte [sel],0
  jne .nosp
  mov si,[H+24]
  test si,si
  jz .nosp
  call runl
  mov byte [splash],1
.nosp:
  cmp byte [sel],0
  jne .xp
  mov word [dap_cnt],2
  mov ax,[mac_lba]
  mov [dap_lba],ax
  mov ax,[mac_lba+2]
  mov [dap_lba+2],ax
  mov word [entry],0x7ce
  jmp .go
.xp:
  mov word [dap_cnt],1
  mov ax,[xp_lba]
  mov [dap_lba],ax
  mov ax,[xp_lba+2]
  mov [dap_lba+2],ax
  mov word [entry],0x7be
.go:
  xor ax,ax
  mov es,ax
  mov fs,ax
  mov dl,[drive]
  mov si,dap
  mov ah,0x42
  int 0x13
  jc .fail
  cmp word [0x7dfe],0xaa55
  jne .fail
  cmp byte [splash],0
  jne .nomode
  mov ax,3
  int 0x10
.nomode:
  xor ax,ax
  mov es,ax
  mov si,[entry]
  mov dl,[drive]
  jmp 0x0000:0x7c00
.fail:
  mov ax,3
  int 0x10
  mov si,s_err
  mov dx,0x0a14
  call tputs
  mov ah,0
  int 0x16
  mov byte [auto],0
  mov byte [gfx],0
  jmp stage2.m


%ifdef DBG
dbg_enum:
  mov ax,3
  int 0x10
  mov dword [BUFV],0x32454256
  mov di,BUFV
  mov ax,0x4f00
  int 0x10
  mov si,t_ver
  call pstr
  mov ax,[BUFV+4]
  call phex16
  call pcrlf
  mov si,[BUFV+14]
  mov ax,[BUFV+16]
  mov fs,ax
.lp:
  mov cx,[fs:si]
  add si,2
  cmp cx,0xffff
  je .done
  mov [mode],cx
  push si
  mov ax,0x4f01
  mov di,BUFM
  int 0x10
  pop si
  cmp ax,0x004f
  jne .lp
  cmp word [BUFM+0x12],1024
  jne .lp
  cmp word [BUFM+0x14],768
  jne .lp
  push si
  mov ax,[mode]
  call phex16
  mov al,' '
  call pch
  mov al,'b'
  call pch
  xor ax,ax
  mov al,[BUFM+0x19]
  call phex16
  mov si,t_attr
  call pstr
  mov ax,[BUFM]
  call phex16
  mov si,t_pit
  call pstr
  mov ax,[BUFM+0x10]
  call phex16
  mov si,t_lin
  call pstr
  mov ax,[BUFM+0x32]
  call phex16
  mov si,t_base
  call pstr
  mov ax,[BUFM+0x2a]
  call phex16
  mov ax,[BUFM+0x28]
  call phex16
  mov si,t_pos
  call pstr
  mov al,[BUFM+0x20]
  call phex8
  mov al,[BUFM+0x22]
  call phex8
  mov al,[BUFM+0x24]
  call phex8
  call pcrlf
  pop si
  jmp .lp
.done:
  mov si,t_key
  call pstr
  mov ah,0
  int 0x16
  ret
pch:
  mov ah,0x0e
  mov bx,7
  int 0x10
  ret
pcrlf:
  mov al,13
  call pch
  mov al,10
  jmp pch
pstr:
  lodsb
  test al,al
  jz .d
  call pch
  jmp pstr
.d:
  ret
phex16:
  push ax
  mov al,ah
  call phex8
  pop ax
phex8:
  push ax
  shr al,4
  call phn
  pop ax
  and al,15
phn:
  add al,'0'
  cmp al,'9'
  jbe pch
  add al,7
  jmp pch
t_ver db 'VBE ver ',0
t_attr db ' a=',0
t_pit db ' p=',0
t_lin db ' l=',0
t_base db ' base=',0
t_pos db ' rgbpos=',0
t_key db 13,10,'press a key',0
%endif

align 8
gdt: dq 0
     dq 0x00CF92000000FFFF
gdtr: dw 15
      dd gdt
drive db 0x80
splash db 0
gfx db 0
sel db 0
%ifdef DBG
auto db 0
%else
auto db 1
%endif
secs db 8
last dw 0
entry dw 0
mode dw 0
pitch dw 0
lfb dd 0
rw dw 0
rh dw 0
dap: db 0x10,0
dap_cnt dw 1
dw 0x7c00,0
dap_lba dd 0,0
tmp: db 1
 dw 0,0,0,0
 dd 0
 db 0
s_err db 'Disk read error - press a key',0
t0n db '    1  Mac OS X Snow Leopard   ',0
t0s db '  > 1  Mac OS X Snow Leopard < ',0
t1n db '    2  Windows XP              ',0
t1s db '  > 2  Windows XP            < ',0
t_auto db 'Auto-boot in ## s   ',0
t_press db 'Press Enter to boot ',0
buf times 40 db 0
times ENGSZ-($-$$) db 0
