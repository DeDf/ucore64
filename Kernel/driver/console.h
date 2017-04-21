#ifndef __KERN_DRIVER_CONSOLE_H__
#define __KERN_DRIVER_CONSOLE_H__

void cons_init(void);
//
int cons_getc(void);
void cons_putc(int c);

void serial_intr(void);

void kbd_intr(void);

#endif /* !__KERN_DRIVER_CONSOLE_H__ */
