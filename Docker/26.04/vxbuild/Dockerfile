FROM ubuntu:26.04

RUN dpkg --add-architecture i386 && \
  apt-get update && apt-get -y dist-upgrade && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  g++-multilib libstdc++6:i386 libxtst6:i386 \
  gtk2-engines-murrine:i386 libatk-adaptor:i386 \
  unzip bc git wget ccache \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV GID=1000
ENV GROUP=wruser
ENV INSTALL_DIR=/opt/windriver
ENV UID=1000
ENV USER=wruser
ENV HOME=/home/${USER}
ENV WRENV=vxworks
ENV WORKSPACE_DIR=/opt/windriver/workspace

COPY ./docker-entrypoint.sh /

# ccache compiler launcher (used via CMAKE_<LANG>_COMPILER_LAUNCHER=ccache-launcher).
#
# Root cause this guards against:
#   ROS 2 packages install ament environment hooks
#   (share/<pkg>/environment/library_path.{sh,dsv}: "prepend LD_LIBRARY_PATH lib").
#   colcon's --merge-install re-sources the install base ($ROOT_DIR) at the start
#   of every package build, so $ROOT_DIR/lib -- full of VxWorks *target* .so files
#   (libzstd.so.1, libc.so.1, ...) -- ends up on LD_LIBRARY_PATH during the build.
#   This is harmless to wr-cc/wr-c++ (static drivers; they resolve target libs via
#   -L/-rpath-link from cc-conf/default.conf, not LD_LIBRARY_PATH). But `ccache`
#   is a *dynamically-linked host* binary: its loader walks LD_LIBRARY_PATH, picks
#   the VxWorks libzstd/libc.so.1, and fails to start:
#     ccache: error while loading shared libraries: libc.so.1: cannot open shared object file
#   (The colcon library_path extension is blocklisted, but that only stops colcon's
#   OWN hook; the ament hooks are installed by CMake and re-sourced regardless.)
#
# Fix: strip the ROS 2 install lib dir ($ROS2_INSTALL_LIB, = $ROOT_DIR/lib, exported
# by ros2.build) from ccache's LD_LIBRARY_PATH, then exec ccache. Same approach as
# host-cc-clean.sh does for cargo's host linker. If ROS2_INSTALL_LIB is unset the
# wrapper is a transparent pass-through.
RUN printf '%s\n' \
  '#!/bin/bash' \
  'clean=$(echo "${LD_LIBRARY_PATH}" | tr ":" "\n" | grep -v -F "${ROS2_INSTALL_LIB:-__none__}" | paste -sd:)' \
  'export LD_LIBRARY_PATH="$clean"' \
  'exec ccache "$@"' \
  > /usr/local/bin/ccache-launcher \
&& chmod +x /usr/local/bin/ccache-launcher

# make /bin/sh symlink to bash instead of dash:
RUN echo "dash dash/sh boolean false" | debconf-set-selections \
&& DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash \
&& ln -sf /bin/bash /bin/sh

WORKDIR /work

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/bin/bash"]
