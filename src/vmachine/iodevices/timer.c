/*
 * timer.c
 *
 *  Created on: 26/12/2016
 *      Author: Miguel
 */
#include "../../vmachine/iodevices/timer.h"

#include "../../vmachine/defines.h"
#include "../../vmachine/io_controller.h"

mtx_t mutex;

char timer_device_running = 1;
uint32_t timer_device_id = (uint32_t)-1;

void timer_poll(void) {
	SDL_Delay(500); /* Wait a little bit to allow the CPU to start executing */
	timer_device_running = 1;
	while(timer_device_running) {
		io_irq(timer_device_id, INT_IRQ);
		SDL_Delay(50);
	}
}

int timer_init(void * arg) {
	timer_device_id = (uint32_t)arg;
	mtx_init(&mutex, mtx_plain);

	timer_poll();

	mtx_destroy(&mutex);
	thrd_exit(0);
	return 1;
}

void timer_deinit(void) {
	mtx_lock(&mutex);
	timer_device_running = 0;
	mtx_unlock(&mutex);
}

char timer_write(uint32_t local_ioaddr, uint64_t data, uint8_t access_width) {

	return 1;
}

uint64_t timer_read(uint32_t local_ioaddr, uint8_t access_width) {

	return 0;
}
