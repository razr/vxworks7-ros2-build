#include <unistd.h>
#include <errno.h>

int execvp(const char *file, char *const argv[])
{
    errno = ENOSYS;
    return -1;
}
