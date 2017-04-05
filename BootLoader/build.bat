gcc -c bootasm.S  -o bootasm.o
gcc -O2 -c bootmain.c -o bootmain.o

ld -Ttext 0x7c00 -Tdata 0x7de0 bootasm.o bootmain.o -o bootloader_t

objcopy -O binary -j .text -j .data bootloader_t bootloader

rem copy /b boot_sect.bin+kernel.bin os_image
PAUSE