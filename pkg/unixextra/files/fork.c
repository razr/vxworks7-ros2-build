#include <unistd.h>
#include <errno.h>

pid_t fork(void)
{
    errno = ENOSYS;
    return -1;
}
