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
#include "utils.h"
#include "tinycthread/tinycthread.h"
#include <stdio.h>

#define ALIGN_IOADDR(phys_addr) (phys_addr - IOSPACE)

char io_rd_dispatch_ret[MAX_INTEGER_SIZE+1];

thrd_t io_threads[IODEVICE_COUNT];

typedef struct iodev {
	int (*init)(void*);
	void (*deinit)(void);
	char (*write)(uint32_t local_ioaddr, uint64_t data, uint8_t access_width);
	uint64_t (*read)(uint32_t local_ioaddr, uint8_t access_width);
	const int space_addr;
	const int space_len;
} iodev_t;

iodev_t devices[IODEVICE_COUNT] = {
	{vga_init, vga_deinit, vga_write, vga_read, 0, LINEAR_FRAMEBUFFER_SIZE} /* Create VGA Device */
};

char io_controller_init(void) {
	for(int i = 0; i < IODEVICE_COUNT; i++)
		if(thrd_create(&io_threads[i], devices[i].init, (void*)0) != thrd_success)
			return 0;
	return 1;
}

char io_controller_deinit(void) {
	for(int i = 0; i < IODEVICE_COUNT; i++)
		devices[i].deinit();
	for(int i = 0; i < IODEVICE_COUNT; i++)
		thrd_join(&io_threads[i], 0);
	return 1;
}

char io_wr_dispatch(uint32_t phys_addr, uint64_t data, uint8_t access_width) {
	uint32_t ioaddr = ALIGN_IOADDR(phys_addr);
	for(int i = 0; i < IODEVICE_COUNT; i++)
		if(ioaddr >= devices[i].space_addr && ioaddr < devices[i].space_addr + devices[i].space_len)
			return devices[i].write(ioaddr - devices[i].space_addr, data, access_width);
	return 1;
}

char * io_rd_dispatch(uint32_t phys_addr, uint8_t access_width) {
	uint32_t ioaddr = ALIGN_IOADDR(phys_addr);
	uint64_t ret = (uint64_t)-1;
	for(int i = 0; i < IODEVICE_COUNT; i++)
		if(ioaddr >= devices[i].space_addr && ioaddr < devices[i].space_addr + devices[i].space_len) {
			ret = devices[i].read(ioaddr - devices[i].space_addr, access_width);
			break;
		}

	int2bin64(ret, io_rd_dispatch_ret, 64);

	for(int i = 0; i < MAX_INTEGER_SIZE; i++)
		io_rd_dispatch_ret[i] = (io_rd_dispatch_ret[i]-'0') + 2;
	io_rd_dispatch_ret[MAX_INTEGER_SIZE] = 0;
	return io_rd_dispatch_ret;
}
