/*
 * io_controller.c
 *
 *  Created on: 19/12/2016
 *      Author: Miguel
 */
#include <mti.h>
#include <stdio.h>
#include "io_controller.h"
#include "address_space.h"
#include "defines.h"
#include "signal_conv.h"
#include "tinycthread/tinycthread.h"
#include "utils.h"

typedef struct {
	mtiSignalIdT clk;
	mtiDriverIdT int_en;
	mtiDriverIdT int_id;
	mtiDriverIdT int_type;
	mtiSignalIdT int_ack;
	mtiSignalIdT int_ack_id;
	mtiSignalIdT ex_enabled;
	mtiSignalIdT int_enabled;
} ioctrl_t;

ioctrl_t * ioctrl_ip;

uint8_t int_en_holdtime = 0;

#define ALIGN_IOADDR(phys_addr) (phys_addr - IOSPACE)

char io_rd_dispatch_ret[MAX_INTEGER_SIZE+1];

volatile char io_controller_closing = 0;
volatile char is_ack = 0;

typedef struct iodev {
	int (*init)(void*);
	void (*deinit)(void);
	char (*write)(uint32_t local_ioaddr, uint64_t data, uint8_t access_width);
	uint64_t (*read)(uint32_t local_ioaddr, uint8_t access_width);
	void (*int_ack)(void);
	const int space_addr;
	const int space_len;
} iodev_t;

iodev_t devices[] = {
	{timer_init, timer_deinit, timer_write, timer_read, 0, 0, TIMER_IOSPACE}, /* Create Timer Device */
	{vga_init, vga_deinit, vga_write, vga_read, 0, TIMER_IOSPACE, LINEAR_FRAMEBUFFER_SIZE}, /* Create VGA Device */
};

thrd_t io_threads[IODEVICE_COUNT];

char io_controller_init(void) {
	for(int i = 0; i < IODEVICE_COUNT; i++)
		if(thrd_create(&io_threads[i], devices[i].init, (void*)i) != thrd_success)
			return 0;
	return 1;
}

void io_controller_on_clk(void * param) {
	_Bool clk = sig_to_int(ioctrl_ip->clk);
	if(clk) {
		if(!int_en_holdtime)
			mti_ScheduleDriver(ioctrl_ip->int_en, 2, 1, MTI_INERTIAL);
		else
			int_en_holdtime--;
		is_ack = sig_to_int(ioctrl_ip->int_ack);
		if(is_ack) {
			uint32_t int_ack_id = sigv_to_int(ioctrl_ip->int_ack_id);
			if(int_ack_id < IODEVICE_COUNT && devices[int_ack_id].int_ack)
				devices[int_ack_id].int_ack();
		}
	}
}

void io_controller_init_vhd(
	mtiRegionIdT region,
	char * param,
	mtiInterfaceListT * generics,
	mtiInterfaceListT * ports
) {
	ioctrl_ip              = (ioctrl_t *)mti_Malloc(sizeof(ioctrl_t));
	ioctrl_ip->clk         = mti_FindPort(ports, "clk");
	ioctrl_ip->int_en      = mti_CreateDriver(mti_FindPort(ports, "int_en"));
	ioctrl_ip->int_id      = mti_CreateDriver(mti_FindPort(ports, "int_id"));
	ioctrl_ip->int_type    = mti_CreateDriver(mti_FindPort(ports, "int_type"));
	ioctrl_ip->int_ack     = mti_FindPort(ports, "int_ack");
	ioctrl_ip->int_ack_id  = mti_FindPort(ports, "int_ack_id");
	ioctrl_ip->ex_enabled  = mti_FindPort(ports, "ex_enabled");
	ioctrl_ip->int_enabled = mti_FindPort(ports, "int_enabled");

	mtiProcessIdT io_proc_onclk = mti_CreateProcess("ioctrl_p_onclk", io_controller_on_clk, ioctrl_ip);
	mti_Sensitize(io_proc_onclk, ioctrl_ip->clk, MTI_EVENT);
}

char io_controller_deinit(void) {
	for(int i = 0; i < IODEVICE_COUNT; i++)
		devices[i].deinit();
	io_controller_closing = 1;
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

char io_irq(uint8_t devid, enum INTERRUPT_TYPE type) {
	/* TODO: Since this function can be called from multioctrl_iple threads, we must implement queueing for IRQ servicing */
	/* Do not trigger an interrupt while the CPU is on IRQ mode, therefore, we must wait for a CPU ack */

#if ENABLE_INTERRUPT_NOTICES == 1
	printf("\n**** NOTICE: INTERRUPT (%s, devid: %d) ****\n", (type == INT_ERR) ? "EXC" : "IRQ", devid);
	fflush(stdout);
#endif

	_Bool int_enabled = sig_to_int(ioctrl_ip->int_enabled);
	_Bool ex_enabled  = sig_to_int(ioctrl_ip->ex_enabled);

	if(type == INT_ERR && !ex_enabled) {
#if ENABLE_INTERRUPT_NOTICES == 1
		printf("**** ERROR: Exceptions are disabled! Dropping the EX request... ****\n");
		fflush(stdout);
#endif
		return 0;
	}

	if(type == INT_IRQ && !int_enabled) {
#if ENABLE_INTERRUPT_NOTICES == 1
		printf("**** ERROR: Interrupts are disabled! Dropping the IRQ request... ****\n");
		fflush(stdout);
#endif
		return 0;
	}

	int_en_holdtime = 1; /* The IRQ enable wire will be held high for this many clock cycles */

	mti_ScheduleDriver(ioctrl_ip->int_en,   3, 1, MTI_INERTIAL);
	mti_ScheduleDriver(ioctrl_ip->int_id,   (long)int_to_sigv(devid, 8), 1, MTI_INERTIAL);
	mti_ScheduleDriver(ioctrl_ip->int_type, (long)int_to_sigv(type,  2), 1, MTI_INERTIAL);

	if(devices[devid].int_ack)
		while(!is_ack)
			SDL_Delay(10);

	return 1;
}
