/*
 * defines.h
 *
 *  Created on: 19/12/2016
 *      Author: Miguel
 */

#ifndef SRC_MACHINE_DEFINES_H_
#define SRC_MACHINE_DEFINES_H_

#define MAX_INTEGER_SIZE 64

#define IS_WINDOWS defined(_WIN32) || defined(_WIN64)

#if IS_WINDOWS
#include <i686-w64-mingw32/include/SDL2/SDL.h>
#else
#include <SDL.h>
#endif

#endif /* SRC_MACHINE_DEFINES_H_ */
