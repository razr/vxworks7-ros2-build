# `unixextra` library

It is an extension of the VxWorks `unix` library. The library is created to enable ROS2 compilation.
It can be built natively by

```bash
$ make
$ make install DESTDIR=~/tmp
```

It is possible to cherry pick and build individual files. It is done since some files are already merged into the VxWorks sources

```bash
$ make SOURCES=fmatch.c
$ make install SOURCES=fmatch.c DESTDIR=~/tmp
```

```bash
/opt/windriver/wrenv.linux
export WIND_CC_SYSROOT=/workspace/itl_generic_vsb
CC=wr-cc make
make install DESTDIR=$(WIND_CC_SYSROOT) PREFIX=/usr INCLUDE_PATH=h/published/UTILS_UNIX LIBRARY_PATH=lib/common
```
