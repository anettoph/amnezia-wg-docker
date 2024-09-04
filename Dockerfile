ARG GOLANG_VERSION=1.22
ARG ALPINE_VERSION=3.20
FROM golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} AS builder

RUN apk update && apk add --no-cache git make bash build-base linux-headers
RUN git clone https://github.com/amnezia-vpn/amneziawg-go.git
RUN git clone https://github.com/amnezia-vpn/amneziawg-tools.git
RUN cd /go/amneziawg-go && \
    GOOS=linux GOARCH=arm64 make
RUN cd /go/amneziawg-tools/src && \
    GOOS=linux GOARCH=arm64 make


FROM alpine:${ALPINE_VERSION}
RUN apk update && apk add --no-cache bash openrc iptables-legacy iproute2 openresolv \
    && mkdir -p /etc/amnezia/amneziawg/

COPY --from=builder /go/amneziawg-go/amneziawg-go /usr/bin/amneziawg-go
COPY --from=builder /go/amneziawg-tools/src/wg /usr/bin/awg
COPY --from=builder /go/amneziawg-tools/src/wg-quick/linux.bash /usr/bin/awg-quick
COPY wireguard-fs /

RUN \
    sed -i 's/^\(tty\d\:\:\)/#\1/' /etc/inittab && \
    sed -i \
        -e 's/^#\?rc_env_allow=.*/rc_env_allow="\*"/' \
        -e 's/^#\?rc_sys=.*/rc_sys="docker"/' \
        /etc/rc.conf && \
    sed -i \
        -e 's/VSERVER/DOCKER/' \
        -e 's/checkpath -d "$RC_SVCDIR"/mkdir "$RC_SVCDIR"/' \
        /lib/rc/sh/init.sh && \
    rm \
        /etc/init.d/hwdrivers \
        /etc/init.d/machine-id
RUN    sed -i 's/cmd sysctl -q \(.*\?\)=\(.*\)/[[ "$(sysctl -n \1)" != "\2" ]] \&\& \0/' /usr/bin/awg-quick
RUN \
    ln -s /sbin/iptables-legacy /bin/iptables && \
    ln -s /sbin/iptables-legacy-save /bin/iptables-save && \
    ln -s /sbin/iptables-legacy-restore /bin/iptables-restore
# register /etc/init.d/wg-quick
RUN rc-update add wg-quick default

RUN echo -e " \n\
    # Note, that syncookies is fallback facility. It MUST NOT be used to help highly loaded servers to stand against legal connection rate.\n\
    net.ipv4.tcp_syncookies = 0 \n\
    net.ipv4.tcp_keepalive_time = 600 \n\
    net.ipv4.tcp_keepalive_intvl = 60 \n\
    net.ipv4.tcp_keepalive_probes = 20 \n\
    net.ipv4.ip_local_port_range = 10000 60999 \n\
    net.ipv4.tcp_fastopen = 3 \n\
    # Contains three values that represent the minimum, default and maximum size of the TCP socket receive buffer.\n\
    net.ipv4.tcp_rmem = 4096 131072 67108864 \n\
    # Similar to the net.ipv4.tcp_rmem TCP send socket buffer size\n\
    net.ipv4.tcp_wmem = 4096 87380 67108864 \n\
    # Controls TCP Packetization-Layer Path MTU Discovery. Takes three values: 0 - Disabled 1 - Disabled by default, enabled when an ICMP black hole detected 2 - Always enabled, use initial MSS of tcp_base_mss.\n\
    net.ipv4.tcp_mtu_probing = 1 \n\
    # net.ipv4.tcp_congestion_control = bbr # not yet supported by mikrotik https://forum.mikrotik.com/viewtopic.php?t=165325 \n\
    " | sed -e 's/^\s\+//g' | tee -a /etc/sysctl.conf \
    && sysctl -p

VOLUME ["/sys/fs/cgroup"]
HEALTHCHECK --interval=5m --timeout=30s CMD /bin/bash /data/healthcheck.sh
CMD ["/sbin/init"]
