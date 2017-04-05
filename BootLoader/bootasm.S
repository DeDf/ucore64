#include "asm.h"

# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into memory,
# at %cs=0 %ip=7c00, in real mode.

.set PROT_MODE_CSEG,        0x8                     # kernel code segment selector
.set PROT_MODE_DSEG,        0x10                    # kernel data segment selector
.set CR0_PE_ON,             0x1                     # protected mode enable flag
.set SMAP,                  0x534d4150              # “SMAP”的ASCII码

.globl start
start:
.code16                                             # Assemble for 16-bit mode
    cli                                             # Disable interrupts
    cld                                             # String operations increment

    # Set up the important data segment registers (DS, ES, SS).
    xorw %ax, %ax                                   # Segment number zero
    movw %ax, %ds                                   # -> Data  Segment
    movw %ax, %es                                   # -> Extra Segment
    movw %ax, %ss                                   # -> Stack Segment

    # Enable A20 (Google A20地址线):
    #  键盘控制器 (0x64 == 命令端口  0x60 == 数据端口)
    #  For backwards compatibility with the earliest PCs, physical
    #  address line 20 is tied low, so that addresses higher than
    #  1MB wrap around to zero by default. This code undoes this.
seta20.1:
    inb $0x64, %al                                  # Get status
    testb $0x2, %al                                 # Busy?
    jnz seta20.1

    movb $0xd1, %al                                 # 0xd1 -> port 0x64
    outb %al, $0x64                                 # Command: Write

seta20.2:
    inb $0x64, %al                                  # Get status
    testb $0x2, %al                                 # Busy?
    jnz seta20.2

    movb $0xdf, %al                                 # 0xdf -> port 0x60
    outb %al, $0x60                                 # A20 Enable

# 系统的内存布局 ARDS 结构
# 偏移量    属性名称        描述
#  0      BaseAddrLow  基地址的低32位   4字节
#  4      BaseAddrHigh 基地址的高32位   4字节
#  8      LengthLow    内存长度的低32位 4字节
#  12     LengthHigh   内存长度的高32位 4字节
#  16     Type         本段内存的类型   4字节

probe_memory:
    movl $0, 0x8000                                 # 0x8000处存放获取到的 ARDS 结构的数量
    xorl %ebx, %ebx
    movw $0x8004, %di                               # 用来存放ARDS的缓冲区地址(Address Range Descriptor Structure)
start_probe:
    movl $0xE820, %eax                              # 获取内存分布情况
    movl $20, %ecx
    movl $SMAP, %edx
    int $0x15                                       # int 0x15 ax=0xe820, 获取内存分布情况
    jnc cont                                        # 当执行int 0x15之后，CF位置位表明调用出错
    movw $12345, 0x8000
    jmp finish_probe
cont:
    addw $20, %di                                   # 一个ARDS结构体大小是20字节
    incl 0x8000
    cmpl $0, %ebx                                   # 如果ebx中值为0则说明已经到了最后一个地址范围描述符
    jnz start_probe
finish_probe:
    # Switch from real to protected mode
    lgdt gdtdesc
    movl %cr0, %eax
    orl $CR0_PE_ON, %eax
    movl %eax, %cr0

    # 在32位保护模式下对cs:eip的修改只能靠转移、调用、返回指令;
    # 首先会将选择子赋给cs，并根据GDT将相应的描述符载入cs的缓存器中，然后将EIP指向偏移地址;
    # 前面预取的指令是16位指令，所以要清空指令流水线;
    #
    ljmp $PROT_MODE_CSEG, $protcseg

.code32                                             # Assemble for 32-bit mode
protcseg:
    # Set up the protected-mode data segment registers
    movw $PROT_MODE_DSEG, %ax                       # Our data segment selector
    movw %ax, %ds                                   # -> DS: Data  Segment
    movw %ax, %es                                   # -> ES: Extra Segment
    movw %ax, %fs                                   # -> FS
    movw %ax, %gs                                   # -> GS
    movw %ax, %ss                                   # -> SS: Stack Segment

    # Set up the stack pointer and call into C. The stack region is from 0--start(0x7c00)
    movl $0x0, %ebp
    movl $start, %esp
    call _bootmain

    # If bootmain returns (it shouldn't), loop.
spin:
    jmp spin

.data
# Bootstrap GDT
.p2align 2                                          # force 4 byte alignment
gdt:
    SEG_NULLASM                                     # null seg
    SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)           # code seg for bootloader and kernel
    SEG_ASM(STA_W,       0x0, 0xffffffff)           # data seg for bootloader and kernel

gdtdesc:
    .word 0x17                                      # sizeof(gdt) - 1
    .long gdt                                       # address gdt
