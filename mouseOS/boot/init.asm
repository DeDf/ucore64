
; *********************************************************
; * init.asm for mouseOS operating system project         *
; *                                                       * 
; * Copyright (c) 2009-2010                               *
; * All rights reserved.                                  *
; * mik(deng zhi)                                         *
; * visit web site : www.mouseos.com                      *
; * bug send email : mik@mouseos.com                      *
; *                                                       *
; * version 0.01 by mik                                   *  
; *********************************************************

%include "include\mouseos.inc"
%include "include\routine_export.inc"
%include "include\mickey_export.inc"
%include "include\driver_export.inc"
%include "include\driver\driver.inc"
%include "include\macro.inc"

; boot ---> setup ---> init

; the init module at MICKEY_INIT_ENTRY (0xffff8000_00000000)

	org MICKEY_INIT_ENTRY - 8

	bits 64

init_length		dq	init_end - init_entry

;-------------- OS initialization --------------
init_entry:
  
	mov rdi, system_memory
	mov rdi, [rdi]
	
	call init_physical_page_table        ; phsycal memory manager system
	
	call init_mickey_page_struct         ; final long mode kernel-page struct
	
	call set_legacy_page_struct          ; for legacy page
	
	mov rdi, system_memory
	mov rdi, [rdi]                 ; for set_mickey_data()
	
	mov rax, pml4t_base
	mov rax, [rax]
	mov cr3, rax                   ; set final CR3
	
	mov rsp, MICKEY_RSP
	
	call set_mickey_data
	
	call get_user_page_map_base
	mov [qword user_page_base], rax        ; get user_page_base
	
	call init_long_gdt             ; set GDT
	call init_long_idt             ; set IDT
	
	call init_keyboard
	
	call init_8259A
	call init_8253
	call init_floppy_controller
	
	; disalbe timer & keyboard
	mov rdi, IRQ0 | IRQ1
	call set_master_IRQ_disable
	
	mov rax, gdt_limit
	mov rbx, idt_limit
	
	lgdt [rax]                     ; load GDT
	lidt [rbx]                     ; load IDT                          
	
; enable IRQ & NMI 
	sti
	NMI_ENABLE                      ; NMI enable
	
; set stack pointer & data segment
	mov ax, KERNEL_SS
	mov ss, ax
	mov ds, ax
	mov es, ax
	
; set code segment descriptor
	mov rax, init_next
	push KERNEL_CS
	push rax
	
   retf_qword


; Now: the 64bit long mode code segment descriptor is CS = KERNEL_CS  

init_next:
; in this step:
; init module load:
;                 * routine module to MICKEY_ROUTINE area
;                 * driver module to MICKEY_DRIVER area
;                 * mickey module to MICKEY_CODE area

	
	
	
; copy routine ---->	mickey routine area
; from ROUTINE_SEG(0xb000) to routine area(0xffffb000_00400000)

	mov rax, ROUTINE_SEG - 8
	mov rcx, [rax]
	mov rsi, ROUTINE_SEG
	mov rdi, MICKEY_ROUTINE_ENTRY
	rep movsb

; copy driver ---->	mickey driver area
; from DRIVER_SEG(0xc000) to routine area(0xffffb000_c0000000)

	mov rax, DRIVER_SEG - 8
	mov rcx, [rax]
	mov rsi, DRIVER_SEG
	mov rdi, MICKEY_DRIVER_ENTRY
	rep movsb

; copy mickey ----> mickey area
; from MICKEY_SEG(0xd000) to mickey area(0xffff8000_00400000)

	mov rax, MICKEY_SEG - 8
	mov rcx, [rax]
	mov rsi, MICKEY_SEG
	mov rdi, MICKEY_CODE_ENTRY
	rep movsb

	call init_long_tss
	mov ax, TSS64
	ltr ax
	
	call init_syscall
	
	call clear_video

; final step:
; enter the mickey modue(kernel)
	mov rax, MICKEY_ENTRY
	push rax
   ret


;*********************************************************************
; OS initialization routine
;*********************************************************************	

;---------------------------------------------------------------------
; set_mickey_data(long system_memory) - set mouseOS system structure
; input:  rdi --- system_memory
;---------------------------------------------------------------------
set_mickey_data:
	mov rax, system_memory
	mov [rax], rdi
	mov rax, video_current
	mov qword [rax], 0xb8000
	call set_mickey_page_struct_base
	ret
	

;---------------------------------------------------------------
; init_long_gdt(void) - set long mode Global Descriptor Table
;---------------------------------------------------------------
init_long_gdt:
	mov rcx, GDT_END - GDT
	mov rsi, GDT
	mov rdi, gdt_base
	rep movsb
	
	mov rax, gdt_limit
	mov rdx, gdt_base
	mov word [rax], GDT_END - GDT
	mov qword [rax + 2], rdx
	ret

	
;---------------------------------------------------------------
; init_long_idt(void) - set long mode Interrupt Descriptor Table
;---------------------------------------------------------------
init_long_idt:
	mov rcx, IDT_END - IDT
	mov rsi, IDT
	mov rdi, idt_base
	rep movsb
	
	mov rax, idt_limit
	mov rdx, idt_base
	mov word [rax], 0xff * 16              ; IDT limit
	mov qword [rax + 2], rdx
	
	
; set IDT entry for int 0x80 (syscall services entry) 
	mov rdi, 0x80
	mov rsi, int80_services_order * 5 + MICKEY_CODE_ENTRY
	call set_interrupt_handler
	
	call set_timer_handler                ; set timer handler
	call set_keyboarder_handler           ; set keyboard handlder
	call set_breakpointer_handler         ; set breakpointer handler
	call set_floppy_interrupt_handler      ; set floppy interrupt handler 
	ret
	
	

	
;---------------------------------------------------------------
; init_long_tss(void) - set long mode Task Status Segment
;---------------------------------------------------------------	
init_long_tss:
	mov rcx, TSS_END - TSS
	mov rsi, TSS
	mov rdi, tss_base
	rep movsb
	

	mov rax, 0x0000890000000000
	mov rdx, (tss_base & 0x00000000ff000000) << 32
	mov rbx, (tss_base & 0x0000000000ffffff) << 16
	or rdx, rax
	or rdx, rbx
	mov dx, TSS_END - TSS
	
	mov rsi, tss_base >> 32


	mov rdi, TSS64
	call set_tss64_descriptor	

	mov rax, tss_base
	mov rbx, MICKEY_RSP
	mov qword [rax + 4], rbx               ; rsp 0
	mov rbx, IST_RSP1
	mov qword [rax + 36], rbx              ; IST 1	
	ret
	



;---------------------------------------------------------------
; init_syscall(void) - set long mode syscall services
;---------------------------------------------------------------
	
init_syscall:
;-------------------------------------------------------
; Note: the sysret instruction: not change SS.RPL to 3
;       So: MSR_STAR.SYSRET_CS.RPL must be to set 3 !!!!
;-------------------------------------------------------

	mov edx, SYSCALL_CS | ((SYSRET_CS | 0x3) << 16)
	xor eax, eax
	mov ecx, MSR_STAR                      ; MSR_STAR's address
	wrmsr                                  ; write edx:eax into MSR_STAR register
	
	mov rax, sys_services_order * 5 + MICKEY_CODE_ENTRY
	mov rdx, rax
	shr rdx, 32
	mov ecx, MSR_LSTAR             ; set MSR_LSTAR = sys_services
	wrmsr
	
	xor edx, edx
	xor eax, eax
	mov ecx, MSR_SFMASK             ; set MSR_SFMASK = 0                     
	wrmsr
         
	ret



	
;-----------------------------
; int3  --- breakpoint handler
;-----------------------------
set_breakpointer_handler:
	mov rdi, 0x03
	mov rsi, breakpointer_order * 5 + MICKEY_CODE_ENTRY
	call set_interrupt_handler
	ret

	
;------------------------------------------
; int 0x20 - timer handler
;------------------------------------------	
set_timer_handler:
; set IDT entry for int 0x20 	
	mov rdi, 0x20
	mov rsi, timer_order * 5 + MICKEY_CODE_ENTRY
	call set_interrupt_handler
	ret

	
;-------------------------------------------
; int 0x21 - keyboard handler
;-------------------------------------------	
set_keyboarder_handler:
	mov rdi, 0x21
	mov rsi, keyboard_handler_order * 5 + MICKEY_DRIVER_ENTRY
	call set_interrupt_handler
	ret


;--------------------------------------------
; int 0x26 - floppy interrupt handler
;--------------------------------------------
set_floppy_interrupt_handler:
	mov rdi, 0x26
	mov rsi, floppy_interrupt_order * 5 + MICKEY_CODE_ENTRY
	call set_interrupt_handler 
	ret


;-----------------------------------------
; clear_video
;-----------------------------------------	
clear_video:
	mov rdi, 0xb8000
	mov rcx, (80*40*2)/8
	xor rax, rax
	rep stosq
	
	ret
	
	
	
	
;--------------------------------------------------------------------------
; ****** import table from kernel routine area **************
;--------------------------------------------------------------------------	
	

; import mickey module, routine module & driver module for Initialization
; ...


	
init_import_table:


; mickey module API's Interface
; the MICKEY_SEG is 0xd000, it's loaded by load module
 	
init_physical_page_table:
	mov rbp, init_physical_page_table_order * 5 + MICKEY_SEG
	jmp rbp

set_mickey_page_struct_base:
	mov rbp, set_mickey_page_struct_base_order * 5 + MICKEY_SEG
	jmp rbp
	
init_mickey_page_struct:
	mov rbp, init_mickey_page_struct_order * 5 + MICKEY_SEG
	jmp rbp
	
get_user_page_map_base:
	mov rax, get_user_page_map_base_order * 5 + MICKEY_SEG
	jmp rax 	
	
set_legacy_page_struct:
	mov rbp, set_legacy_page_struct_order * 5 + MICKEY_SEG
	jmp rbp
	
set_temp_data_page_struct:
	mov rbp, set_temp_data_page_struct_order * 5 + MICKEY_SEG
	jmp rbp



; routine module API's Interface
; the ROUTINE_SEG is 0xb000, it's loaded by load module
	
set_interrupt_handler:
	mov rbp, set_interrupt_handler_order * 5 + ROUTINE_SEG
	jmp rbp
	
set_tss64_descriptor:
	mov rbp, set_tss64_descriptor_order * 5 + ROUTINE_SEG
	jmp rbp

;sys_services_enter:
;	mov rbp, sys_services_enter_order * 5 + ROUTINE_SEG
;	jmp rbp



; driver module API's Interface
; the DRIVER_SEG is 0xc000, It's loaded by load module
init_keyboard:
	mov rbp, init_keyboard_order * 5 + DRIVER_SEG
	jmp rbp
  
	
init_8259A:
	mov rax, init_8259A_order * 5 + DRIVER_SEG
	jmp rax

init_floppy_controller:
	mov rax, init_floppy_controller_order * 5 + DRIVER_SEG

set_master_IRQ_disable:
	mov rax, set_master_IRQ_disable_order * 5 + DRIVER_SEG
	jmp rax
	
init_8253:
	mov rax, init_8253_order * 5 + DRIVER_SEG
	jmp rax  

%include "include\sys_struct.inc"

init_end:
;--------------------------
; the end of init
;-------------------------		
	