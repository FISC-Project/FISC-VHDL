/*
 * vga.h
 *
 *  Created on: 20/12/2016
 *      Author: Miguel
 */

#ifndef SRC_MACHINE_IODEVICES_VGA_H_
#define SRC_MACHINE_IODEVICES_VGA_H_

#define WINDOW_TITLE  "FISC VGA Screen"
#define WINDOW_ICON   "res/fisc_logo.bmp"
#define WINDOW_WIDTH  800
#define WINDOW_HEIGHT 600

char vga_init(void);
char vga_deinit(void);

#endif /* SRC_MACHINE_IODEVICES_VGA_H_ */
