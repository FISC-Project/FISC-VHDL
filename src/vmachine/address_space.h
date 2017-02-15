/*
 * address_space.h
 *
 *  Created on: 19/12/2016
 *      Author: Miguel
 */

#ifndef SRC_VMACHINE_ADDRESS_SPACE_H_
#define SRC_VMACHINE_ADDRESS_SPACE_H_

#include "iodevices/timer.h"
#include "iodevices/vga.h"

#define BOOTLOADER_FILE "bin/bootloader.bin"
#define MEMORY_DEPTH 50000000 /* Size of memory in bytes */
#define MEMORY_LOADLOC 0      /* Where to load the bootloader on startup */

#define IODEVICE_COUNT (sizeof(devices) / sizeof(devices[0]))
#define IOSPACE        0x1000 /* The IO space starts at this address */
#define IOSPACE_LEN    LINEAR_FRAMEBUFFER_SIZE+TIMER_IOSPACE /* And is this long in bytes */

enum ADDR_SPACE_T {
	SPACE_MMEM, /* Main Memory (Read and Write) Address Space */
	SPACE_IO    /* I/O Address space */
};

#endif /* SRC_VMACHINE_ADDRESS_SPACE_H_ */
