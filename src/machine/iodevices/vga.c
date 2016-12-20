/*
 * vga.c
 *
 *  Created on: 20/12/2016
 *      Author: Miguel
 */
#include <stdio.h>
#include "../defines.h"
#include "vga.h"

SDL_Window * window = 0;
SDL_Renderer *renderer;

char vga_init(void) {
	SDL_CreateWindowAndRenderer(WINDOW_WIDTH, WINDOW_HEIGHT, SDL_WINDOW_OPENGL | SDL_WINDOW_BORDERLESS | SDL_WINDOW_RESIZABLE, &window, &renderer);
	if(window == NULL) {
		printf("\n> ERROR (SDL): Window could not be created! SDL Error: %s\n", SDL_GetError());
		return 0;
	}

	SDL_SetWindowTitle(window, WINDOW_TITLE);
	SDL_Surface * icon = SDL_LoadBMP(WINDOW_ICON);
	SDL_SetWindowIcon(window, icon);

	SDL_SetRenderDrawColor(renderer, 0, 0, 255, 0);
	SDL_RenderClear(renderer);
	SDL_SetRenderDrawColor(renderer, 255, 255, 255, 0);
	SDL_RenderDrawPoint(renderer, 400, 300);
	SDL_RenderPresent(renderer);

	char quit = 0;
	SDL_Event e;
	while(!quit)
		while(SDL_PollEvent(&e) != 0)
			if(e.type == SDL_QUIT)
				quit = 1;

	return 1;
}

char vga_deinit(void) {
	SDL_DestroyRenderer(renderer);
	SDL_DestroyWindow(window);
	return 1;
}
