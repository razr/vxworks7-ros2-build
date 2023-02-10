/* unistd.h standard header extensions for UNIX compatibility */

/*
 * Copyright (c) 2023 Wind River Systems, Inc.
 *
 * The right to copy, distribute, modify, or otherwise make use of this software
 * may be licensed only pursuant to the terms of an applicable Wind River
 * license agreement.
 */

/*
modification history
--------------------
30jan23 akh - created
*/

#ifndef _UNISTD_UNIX
#define _UNISTD_UNIX

#ifdef __VXWORKS__
#include <../public/unistd.h>
#else
#include <sys/types.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

pid_t fork(void);
int execvp(const char *file, char *const argv[]);

#ifdef __cplusplus
}
#endif
#endif /* _UNISTD_UNIX */
