/*
 * io_controller.c
 *
 *  Created on: 19/12/2016
 *      Author: Miguel
 */
#include "defines.h"
#include "io_controller.h"
#include "address_space.h"
#include "iodevices/vga.h"
#include <stdio.h>

#define ALIGN_IOADDR(phys_addr) (phys_addr - IOSPACE)
char io_rd_dispatch_ret[MAX_INTEGER_SIZE+1];

char io_controller_init(void) {
	vga_init();
	return 1;
}

char io_controller_deinit(void) {
	vga_deinit();
	return 1;
}

char io_wr_dispatch(uint32_t phys_addr, uint64_t data, uint8_t access_width) {
	uint32_t ioaddr = ALIGN_IOADDR(phys_addr);

	return 1;
}

char * io_rd_dispatch(uint32_t phys_addr, uint8_t access_width) {
	uint32_t ioaddr = ALIGN_IOADDR(phys_addr);


	for(int i=0;i<MAX_INTEGER_SIZE;i++) io_rd_dispatch_ret[i] = 3;
	io_rd_dispatch_ret[MAX_INTEGER_SIZE] = 0;
	return io_rd_dispatch_ret;
}
