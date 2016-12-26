/*
 * timer.c
 *
 *  Created on: 26/12/2016
 *      Author: Miguel
 */
#include "../defines.h"
#include "timer.h"

int timer_init(void * arg) {

	return 1;
}

void timer_deinit(void) {

}

#include <stdio.h>

char timer_write(uint32_t local_ioaddr, uint64_t data, uint8_t access_width) {
	printf("\n> TIMER WRITE"); fflush(stdout);
	return 1;
}

uint64_t timer_read(uint32_t local_ioaddr, uint8_t access_width) {

	return 0;
}
