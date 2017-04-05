#include <stdint.h>
#include <stddef.h>
#include "x86.h"
#include "elf_x64.h"

/* ********************************************************************
 * This a dirt simple boot loader, whose sole job is to boot
 * an ELF kernel image from the first IDE hard disk.
 *
 * DISK LAYOUT
 *  * This program(bootasm.S and bootmain.c) is the bootloader.
 *    It should be stored in the first sector of the disk.
 *
 *  * The 2nd sector onward holds the kernel image.
 *
 *  * The kernel image must be in ELF format.
 **********************************************************************/

#define SECTSIZE        512
#define ELFHDR          ((struct elfhdr *)0x10000)	// scratch space

// Command Block Register的用途
// 
// 1F0 (Read and Write): Data Register
// 1F1 (Read): Error Register
// 1F1 (Write): Features Register
// 1F2 (Read and Write): Sector Count Register
// 1F3 (Read and Write): LBA Low Register
// 1F4 (Read and Write): LBA Mid Register
// 1F5 (Read and Write): LBA High Register
// 1F6 (Read and Write): Drive/Head Register
// 1F7 (Read): Status Register
// 1F7 (Write): Command Register
// 
// status register 為8bit, 由左至右分別為:
// 
// BSY (busy)
// DRDY(device ready)
// DF  (Device Fault)
// DSC (seek complete)
// DRQ (Data Transfer Requested)
// CORR(data corrected)
// IDX (index mark)
// ERR (error)

/* waitdisk - wait for disk ready */
static void waitdisk(void)
{
    while ((inb(0x1F7) & 0xC0) != 0x40)
        /* do nothing */ ;
}

/* readsect - read a single sector at @secno into @dst */
static void readsect(void *dst, uint32_t secno)
{
	waitdisk();
	outb(0x1F2, 1);		// count = 1
	outb(0x1F3, secno & 0xFF);
	outb(0x1F4, (secno >> 8) & 0xFF);
	outb(0x1F5, (secno >> 16) & 0xFF);
	outb(0x1F6, ((secno >> 24) & 0xF) | 0xE0);
	outb(0x1F7, 0x20);	// cmd 0x20 - read sectors
	waitdisk();

	// read a sector
	insl(0x1F0, dst, SECTSIZE / 4);  // 一次读4个字节，所以这里除以4
}

/*
 * readseg - read @count bytes at @offset into virtual address @pa,
 * might copy more than asked.
 */
static void readseg(uintptr_t pa, uint32_t count, uint32_t offset)
{
	uintptr_t end_pa = pa + count;

	// round down to sector boundary
	pa -= offset % SECTSIZE;

	// translate from bytes to sectors; kernel starts at sector 1
	uint32_t secno = (offset / SECTSIZE) + 1;

	// If this is too slow, we could read lots of sectors at a time.
	// We'd write more to memory than asked, but it doesn't matter --
	// we load in increasing order.
	for (; pa < end_pa; pa += SECTSIZE, secno++)
    {
		readsect((void *)pa, secno);
	}
}

/* bootmain - the entry of bootloader */
void bootmain(void)
{
	// read the 1st page off disk
	readseg((uintptr_t) ELFHDR, SECTSIZE * 8, 0);

	// is this a valid ELF?
	if (ELFHDR->e_magic != ELF_MAGIC)
    {
		return;
	}

	struct proghdr *ph, *eph;

	// load each program segment (ignores ph flags)
	ph = (struct proghdr *)((uintptr_t) ELFHDR + (size_t) ELFHDR->e_phoff);
	eph = ph + (size_t) ELFHDR->e_phnum;
	for (; ph < eph; ph++)
    {
		readseg(ph->p_pa, ph->p_memsz, ph->p_offset);
	}

	// call the entry point from the ELF header
	// note: does not return
	((void (*)(void))((uintptr_t) ELFHDR->e_entry)) ();

    // trigger a Bochs breakpoint if running under Bochs
bad:
	outw(0x8A00, 0x8A00);
	outw(0x8A00, 0x8E00);

	//do nothing
	while (1) ;
}
