# Dockerfile for xray based alpine
# Copyright (C) 2019 - 2021 Teddysun <i@teddysun.com>
# Reference URL:
# https://github.com/XTLS/Xray-core
# https://github.com/v2fly/v2ray-core
# https://github.com/v2fly/geoip
# https://github.com/v2fly/domain-list-community

FROM --platform=${TARGETPLATFORM} alpine:3.20

ARG TARGETPLATFORM
WORKDIR /root
COPY xray.sh /root/xray.sh
# COPY config.json /etc/xray/config.json
RUN set -ex \
	&& apk add --no-cache tzdata ca-certificates \
	&& mkdir -p /var/log/xray /usr/share/xray /etc/xray \
	&& chmod +x /root/xray.sh \
	&& /root/xray.sh "${TARGETPLATFORM}" \
	&& rm -fv /root/xray.sh
	# && wget -O /usr/share/xray/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat \
	# && wget -O /usr/share/xray/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat

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

ENV TZ=Europe/Moscow
CMD [ "/usr/bin/xray", "-config", "/etc/xray/config.json" ]