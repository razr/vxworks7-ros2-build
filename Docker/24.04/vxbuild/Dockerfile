# Pinned base image (multi-arch index digest of ubuntu:24.04, created 2026-11-10).
# The tag is re-pointed on every Docker Hub refresh; pinning keeps the image and
# the CI layer cache stable. To update: docker buildx imagetools inspect ubuntu:24.04
ARG UBUNTU_IMAGE=ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8
FROM ${UBUNTU_IMAGE}

RUN dpkg --add-architecture i386 && \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  g++-multilib libstdc++6:i386 libgtk2.0-0:i386 libxtst6:i386 \
  gtk2-engines-murrine:i386 libcanberra-gtk-module:i386 libatk-adaptor:i386 \
  unzip bc git wget zstd \
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

# make /bin/sh symlink to bash instead of dash:
RUN echo "dash dash/sh boolean false" | debconf-set-selections \
&& DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash \
&& ln -sf /bin/bash /bin/sh

WORKDIR /work

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/bin/bash"]
