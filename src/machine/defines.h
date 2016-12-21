/*
 * defines.h
 *
 *  Created on: 19/12/2016
 *      Author: Miguel
 */

#ifndef SRC_MACHINE_DEFINES_H_
#define SRC_MACHINE_DEFINES_H_

#define MODELSIM_EXECUTION_TIME 100 /* How long will the Simulator run (in nanoseconds scale) */

#define MAX_INTEGER_SIZE 64

enum DATATYPE {
	SZ_8, SZ_16, SZ_32, SZ_64
};

#define ALIGN16(addr) ((addr)*2)
#define ALIGN32(addr) ((addr)*4)
#define ALIGN64(addr) ((addr)*8)

#define IS_WINDOWS defined(_WIN32) || defined(_WIN64)

#if IS_WINDOWS
#include <i686-w64-mingw32/include/SDL2/SDL.h>
#include <windows.h>
#include <winbase.h>
#else
#include <SDL.h>
#endif

#endif /* SRC_MACHINE_DEFINES_H_ */
