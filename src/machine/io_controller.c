/*
 * io_controller.c
 *
 *  Created on: 19/12/2016
 *      Author: Miguel
 */
#include "io_controller.h"
#include <stdio.h>

char io_wr_dispatch(uint32_t phys_addr, uint64_t data, uint8_t access_width) {

	return 1;
}


char io_rd_dispatch_ret[65];

char * io_rd_dispatch(uint32_t phys_addr, uint8_t access_width) {
	for(int i=0;i<64;i++) io_rd_dispatch_ret[i] = 3;
	io_rd_dispatch_ret[64] = 0;


	return io_rd_dispatch_ret;
}
