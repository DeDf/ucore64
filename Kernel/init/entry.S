#include <mmu.h>
#include <memlayout.h>

.text
.code32
.global kern_entry
kern_entry:
    
    # Detection CPUID support : when the ID-bit in the FLAGS-register can be flipped.
    pushf
    popl %eax
    movl %eax, %ecx                                 # 保存eflags到ecx中
    xorl $FL_ID, %eax                               # define FL_ID 0x00200000
    pushl %eax
    popf
    pushf
    popl %eax
    xor %eax, %ecx                                  # 比较设置FL_ID前后的eflags
    jz spin

    # Detect x86 or x86_64
    movl $0x80000000, %eax
    cpuid
    cmpl $0x80000001, %eax                          # Compare the A-register with $0x80000001
    jb spin                                         # It is less, there is no long mode.
	 #
    movl $0x80000001, %eax
    cpuid
    test $0x20000000, %edx                          # Test if the LM-bit is set in the D-register
    jz spin                                         # They aren't, there is no long mode.

    # Build page table for long-mode
    cld                                             # 将标志寄存器eFlags的方向标志位DF清零，使SI或DI改变方式为自增

    # step1: set pgd entry, mark pud as (PTE_W | PTE_P)
    movl $pgd, %edi                                 # Page Global Directory (PGD)
    movl $pud, %eax                                 # Page Upper  Directory (PUD)
    orl $0x3, %eax
    movl %eax, (%edi)
    movl %eax, 0x800(%edi)
    movl %eax, 0x900(%edi)

    # clear and set pud, mark pmd as (PTE_W | PTE_P)
    movl $pud, %edi
    movl $pmd, %eax
    orl $0x3, %eax
    movl %eax, (%edi)
    addl $4096, %eax
    movl %eax, 0x08(%edi)
    addl $4096, %eax
    movl %eax, 0x10(%edi)
    addl $4096, %eax
    movl %eax, 0x18(%edi)

    # set pmd, Mark each entry as (PTE_W | PTE_P | PTE_PS)
    movl $pmd, %edi
    movl $0x83, %ebx
    movl $0x800, %ecx                               # 512 entries

    # map 2M * 512 * 4 = 4G memory
    # this should be enough for all IO mapped mem
loop:
    movl %ebx, (%edi)
    addl $0x8, %edi
    addl $0x200000, %ebx
    subl $0x1, %ecx
    cmpl $0x0, %ecx
    jne loop

    # Prepare for long-mode, set (CR4_PGE | CR4_PAE)
    movl $0x20, %eax
    movl %eax, %cr4

    # set cr3
    movl $pgd, %eax
    movl %eax, %cr3

    # enable long-mode
    movl $0xC0000080, %ecx
    rdmsr
    orl $0x00000100, %eax
    wrmsr

    # Active long-mode
    movl %cr0, %eax
    orl $0x80000001, %eax
    movl %eax, %cr0

    movl $gdtdesc, %edi
    lgdt (%edi)
    ljmp $KERNEL_CS, $longmode_entry

spin:
    jmp spin

.global apstart
apstart:
    # Prepare for long-mode, set (CR4_PGE | CR4_PAE)
    movl $0x20, %eax
    movl %eax, %cr4

    # set cr3
    movl $pgd, %eax
    movl %eax, %cr3

    # enable long-mode
    movl $0xC0000080, %ecx
    rdmsr
    orl $0x00000100, %eax
    wrmsr

    # Active long-mode
    movl %cr0, %eax
    orl $0x80000001, %eax
    movl %eax, %cr0

    movl $gdtdesc, %edi
    lgdt (%edi)
    ljmp $KERNEL_CS, $longmode_ap_entry


.code64
longmode_ap_entry:
    # Set up the protected-mode data segment registers
    mov $KERNEL_DS, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss

    # Jump to kern_entry64
    movq $KERNBASE, %rax
    addq $kern_ap_entry64 - KERNBASE, %rax
    jmp *%rax


# %esi = bootparam phy addr
# long-mode code here
.code64
longmode_entry:
    # Set up the protected-mode data segment registers
    mov $KERNEL_DS, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss

    movq $KERNBASE, %rax
    addq %rax, %rsi
    movl 0x00(%rsi), %edi
    movl 0x04(%rsi), %esi

    movq $0x0, %rbp
    movq $KERNBASE, %rsp
    addq $bootstacktop - KERNBASE, %rsp
    call kern_init

# should never get here
    jmp spin

.global kern_ap_entry64
kern_ap_entry64:
    # setup rsp
    mov (%esp), %rsp

    # boot_cr3 cr3
    mov  (%ebp), %rax
    mov  %rax, %cr3

    movq $0x0, %rbp

    call ap_init
    jmp spin
    
.data
.align 4
gdt:
    SEG_NULL()
    SEG_CODE(STA_X | STA_R)
    SEG_DATA(STA_W)

gdtdesc:
    .word 0x2f
    .quad gdt

.global cmdline
cmdline:
	.space 256

.align PGSIZE
pgd:
    .rept 1024   # 把.rept 指令与.endr 指令之间的行重复 X 次
    .long 0x0
    .endr
pud:
    .rept 1024
    .long 0x0
    .endr
pmd:
    .rept (1024*4)
    .long 0x0
    .endr

.align PGSIZE
    .globl bootstack
bootstack:
    .space KSTACKSIZE
    .globl bootstacktop
bootstacktop:

