/*
 * vga.h
 *
 *  Created on: 20/12/2016
 *      Author: Miguel
 */

#ifndef SRC_VMACHINE_IODEVICES_VGA_H_
#define SRC_VMACHINE_IODEVICES_VGA_H_

#include <stdint.h>

#define WINDOW_TITLE  "FISC VGA Screen"
#define WINDOW_ICON   "res/fisc_logo.bmp"
#define WINDOW_WIDTH  800
#define WINDOW_HEIGHT 600

#define LINEAR_FRAMEBUFFER_SIZE WINDOW_WIDTH * WINDOW_HEIGHT * 4

int vga_init(void * arg);
void vga_deinit(void);
char vga_write(uint32_t local_ioaddr, uint64_t data, uint8_t access_width);
uint64_t vga_read(uint32_t local_ioaddr, uint8_t access_width);

#endif /* SRC_VMACHINE_IODEVICES_VGA_H_ */
