/*
 * vga.c
 *
 *  Created on: 20/12/2016
 *      Author: Miguel
 */
#include "../../vmachine/iodevices/vga.h"

#include <stdio.h>
#include <string.h>

#include "../../vmachine/defines.h"

SDL_Window   * window = 0;
SDL_Renderer * renderer;
SDL_Texture  * texture;

char renderbuffer[LINEAR_FRAMEBUFFER_SIZE];

char vga_device_running = 1;
char vga_device_open    = 0;
uint32_t vga_device_id  = (uint32_t)-1;

mtx_t mutex;

volatile uint32_t internal_local_ioaddr = 0;
volatile uint64_t internal_data = 0;
volatile uint8_t  internal_access_width = 0;
volatile uint8_t  internal_wr = 0;
volatile uint8_t  internal_rd = 0;

volatile uint64_t external_rd = 0;

char vga_write(uint32_t local_ioaddr, uint64_t data, uint8_t access_width) {
	static char first = 2; /* TODO: This variable temporarily fixes a threading bug */
	internal_local_ioaddr = local_ioaddr;
	internal_data = data;
	internal_access_width = access_width;
	while(internal_wr) SDL_Delay(1);
	internal_wr = 1;
	if(first) {
		first--;
		while(internal_wr) SDL_Delay(1);
		return vga_write(local_ioaddr, data, access_width);
	} else {
		first = 2;
	}
	return 1;
}

char vga_local_write(uint32_t local_ioaddr, uint64_t data, uint8_t access_width) {
	if(local_ioaddr < LINEAR_FRAMEBUFFER_SIZE) {
		vga_device_open = 1;
		int pitch = WINDOW_WIDTH*4;

		uint32_t format;
		int w, h;
		SDL_QueryTexture(texture, &format, NULL, &w, &h);
		SDL_PixelFormat * fmt = SDL_AllocFormat(SDL_GetWindowPixelFormat(window));

		SDL_LockTexture(texture, NULL, (void**)&renderbuffer[0], &pitch);

		switch(access_width) {
			case SZ_8: {
				uint32_t * ptr = (uint32_t*)&renderbuffer[local_ioaddr];
				*ptr = SDL_MapRGB(fmt, 0, 0, (uint8_t) data & 0xFF);
				break;
			}
			case SZ_16: {
				uint32_t * ptr = (uint32_t*)&renderbuffer[local_ioaddr];
				*ptr = SDL_MapRGB(fmt, 0, (uint8_t)((data & 0xFF00) >> 8), (uint8_t) data & 0xFF);
				break;
			}
			case SZ_32: {
				uint32_t * ptr = (uint32_t*)&renderbuffer[local_ioaddr];
				*ptr = SDL_MapRGB(fmt, (uint8_t)((data & 0xFF0000) >> 16), (uint8_t)((data & 0xFF00) >> 8), (uint8_t) data & 0xFF);
				break;
			}
			case SZ_64: {
				uint32_t * ptr = (uint32_t*)&renderbuffer[local_ioaddr];
				ptr[0] = SDL_MapRGB(fmt, (uint8_t)((data & 0xFF000000000000) >> 48), (uint8_t)((data & 0xFF0000000000) >> 40), (uint8_t)((data & 0xFF00000000) >> 32));
				ptr[1] = SDL_MapRGB(fmt, (uint8_t)((data & 0xFF0000) >> 16), (uint8_t)((data & 0xFF00) >> 8), (uint8_t) data & 0xFF);
				break;
			}
			default: return 0;
		}

		SDL_FreeFormat(fmt);
		SDL_UnlockTexture(texture);
	}
	return 1;
}

uint64_t vga_read(uint32_t local_ioaddr, uint8_t access_width) {
	internal_local_ioaddr = local_ioaddr;
	internal_access_width = access_width;
	internal_rd = 1;
	while(internal_rd) SDL_Delay(1);
	return external_rd;
}

uint64_t vga_local_read(uint32_t local_ioaddr, uint8_t access_width) {
	switch(access_width) {
		case SZ_8:  if(local_ioaddr   >= LINEAR_FRAMEBUFFER_SIZE) return (uint64_t)-1; break;
		case SZ_16: if(local_ioaddr+1 >= LINEAR_FRAMEBUFFER_SIZE) return (uint64_t)-1; break;
		case SZ_32: if(local_ioaddr+3 >= LINEAR_FRAMEBUFFER_SIZE) return (uint64_t)-1; break;
		case SZ_64: if(local_ioaddr+7 >= LINEAR_FRAMEBUFFER_SIZE) return (uint64_t)-1; break;
		default: return (uint64_t)-1;
	}

	switch(access_width) {
	case SZ_8:
		return (uint64_t)renderbuffer[local_ioaddr];
	case SZ_16:
		return (uint64_t)(((uint8_t)renderbuffer[local_ioaddr] << 8) |
				(uint8_t)renderbuffer[local_ioaddr+1]);
	case SZ_32:
		return  (uint64_t)(((uint8_t)(renderbuffer[local_ioaddr]) << 24) |
				((uint8_t)(renderbuffer[local_ioaddr+1]) << 16) |
				((uint8_t)(renderbuffer[local_ioaddr+2]) << 8)  |
				(uint8_t)(renderbuffer[local_ioaddr+3]));
	case SZ_64:
		return (uint64_t)(((uint64_t)(renderbuffer[local_ioaddr]) << 56) |
				((uint64_t)renderbuffer[local_ioaddr+1] << 48) |
				((uint64_t)renderbuffer[local_ioaddr+2] << 40) |
				((uint64_t)renderbuffer[local_ioaddr+3] << 32) |
				((uint64_t)renderbuffer[local_ioaddr+4] << 24) |
				((uint64_t)renderbuffer[local_ioaddr+5] << 16) |
				((uint64_t)renderbuffer[local_ioaddr+6] << 8)  |
				 (uint64_t)renderbuffer[local_ioaddr+7]);
	default: return (uint64_t)-1;
	}
}

void vga_render(void) {
	SDL_UpdateTexture(texture, NULL, &renderbuffer[0], WINDOW_WIDTH*4);
	SDL_RenderClear(renderer);
	SDL_RenderCopy(renderer, texture, NULL, NULL);
	SDL_RenderPresent(renderer);
}

void vga_poll() {
	SDL_Event evt;
	vga_device_running = 1;
	while(vga_device_running) {
		if(internal_wr) {
			vga_local_write(internal_local_ioaddr, internal_data, internal_access_width);
			internal_wr = 0;
		}
		if(internal_rd) {
			external_rd = vga_local_read(internal_local_ioaddr, internal_access_width);
			internal_rd = 0;
		}
		vga_render();
		while(SDL_PollEvent(&evt) != 0)
			if(evt.type == SDL_QUIT)
				vga_device_running = 0;
	}
}

int vga_init(void * arg) {
	SDL_CreateWindowAndRenderer(WINDOW_WIDTH, WINDOW_HEIGHT, SDL_WINDOW_OPENGL | SDL_WINDOW_BORDERLESS | SDL_WINDOW_RESIZABLE, &window, &renderer);
	if(window == NULL) {
		printf("\n> ERROR (SDL): Window could not be created! SDL Error: %s\n", SDL_GetError());
		return 0;
	}

	vga_device_id = (uint32_t)arg;

	mtx_init(&mutex, mtx_plain);

	SDL_SetWindowTitle(window, WINDOW_TITLE);
	SDL_Surface * icon = SDL_LoadBMP(WINDOW_ICON);
	SDL_SetWindowIcon(window, icon);

	memset(renderbuffer, 0, LINEAR_FRAMEBUFFER_SIZE);

	SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0);
	SDL_RenderClear(renderer);
	SDL_RenderPresent(renderer);
	texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, WINDOW_WIDTH, WINDOW_HEIGHT);
	vga_poll();

	/* Clean up everything: */
	SDL_DestroyTexture(texture);
	SDL_DestroyRenderer(renderer);
	mtx_destroy(&mutex);
	thrd_exit(0);
	return 1;
}

void vga_deinit(void) {
	if(!vga_device_open) return;
	mtx_lock(&mutex);
	vga_device_running = 0;
	mtx_unlock(&mutex);
}
