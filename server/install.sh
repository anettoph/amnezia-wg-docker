#!/bin/bash

# ADMIN_IP_ADDRESS=x.x.x.x/32
XRAY_SRV_PORT=443
XRAY_CLIENT_PORT=62933
AWG_PORT=62932
TUN_NET=10.8.0.0/24
TUN_MTU=1370
MIKROTIK_CONTAINER_NET=172.17.0.0/24

make_swap() {
	if [ ! -f /swapfile ]; then
		fallocate -l 1G /swapfile
		chmod 0600 /swapfile
		mkswap /swapfile
		swapon /swapfile
	fi
}

clean_swap() {
	swapoff -a
	rm -f /swapfile
}

# Update system packages
make_swap
PM=$(yum --version 1>/dev/null 2>&1 && echo yum) || PM=$(dnf --version 1>/dev/null 2>&1 && echo dnf) || PM=$(apt --version 1>/dev/null 2>&1 && echo apt)
if [ $? -ne 0 ]; then >&2 echo "$PM not supported yet"; exit 1; fi

old_kernel=$(uname -r)
case $PM in
	yum|dnf) $PM -y update ;;
	apt|apt-get) $PM update && $PM -y upgrade ;; #todo /etc/cloud/cloud.cfg do not update
esac

# Check for reboot necessary
new_kernel=$(uname -r)
updated_kernels=()
need_reboot=false
reboot_message='Reboot required to apply system updates'
case $PM in
	yum|dnf) if $PM list --installed kernel* | grep -q '^Installed[^)]'; then need_reboot=true; fi ;;
	apt|apt-get) [ "$old_kernel" != "$new_kernel" ] && need_reboot=true ;;
esac
if [[ $need_reboot == true ]] ; then
	case $PM in
		yum|dnf) for i in $($PM list --installed kernel* | grep -q '^Installed[^)]' | tail -n +2 | awk '{print $2}'); do updated_kernels+=("$i"); done ;;
		apt|apt-get) updated_kernels+=("$old_kernel -> $new_kernel") ;;
	esac
	reboot_message="$reboot_message\nUpdated kernels:\n${updated_kernels[*]}"
fi
if [ $need_reboot == true ]; then echo -e "$reboot_message" && echo "Run script after reboot." && sleep 60 && clean_swap && reboot; fi

# Install necessary packages
case $PM in
	yum|dnf) $PM clean all && $PM makecache && $PM -y install iproute iptables-services mc net-tools tcpdump tar git wget "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)" dkms openssl ;;
	apt|apt-get) sed -i '/deb-src/s/^# //' /etc/apt/sources.list && $PM update && $PM -y install iproute2 iptables iptables-persistent mc net-tools tcpdump tar git wget "software-properties-common" python3-launchpadlib gnupg2 "linux-headers-$(uname -r)" linux-source dkms openssl ;;
	# apt|apt-get) $PM -y install iproute2 iptables iptables-persistent mc net-tools tcpdump tar git wget gnupg2 openssl ;;
esac

IF_NAME=$(ip route | grep '^default' |  sed -n 's/.*dev \([^\ ]*\).*/\1/p')
VM_IP4_ADDRESS_WITH_MASK=$(ip -4 addr show "$IF_NAME" | grep inet | awk '{ print $2; }' | grep -Eo '^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$')
VM_IP6_ADDRESS_WITH_MASK=$(ip -6 addr show "$IF_NAME" | grep global | awk '{ print $2; }')

############################################################ ip filter section ############################################################

iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT && iptables -t nat -F && iptables -t mangle -F && iptables -F && iptables -X
case $PM in
	yum|dnf) systemctl stop firewalld.service && systemctl disable firewalld.service && systemctl mask firewalld.service && systemctl enable iptables && systemctl start iptables ;;
	apt|apt-get) systemctl stop ufw.service && systemctl disable ufw.service && systemctl mask ufw.service && systemctl enable netfilter-persistent && systemctl start netfilter-persistent ;;
esac

iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -d "$VM_IP4_ADDRESS_WITH_MASK" -p tcp -m tcp --dport $XRAY_SRV_PORT -j ACCEPT
iptables -A INPUT -d "$VM_IP4_ADDRESS_WITH_MASK" -p udp -m udp --dport $AWG_PORT -j ACCEPT
if [ -z $ADMIN_IP_ADDRESS ]; then
	iptables -A INPUT -s 0.0.0.0/0 -d "$VM_IP4_ADDRESS_WITH_MASK" -p tcp -m tcp --dport 22 -j ACCEPT
else	
	iptables -A INPUT -s "$ADMIN_IP_ADDRESS" -d "$VM_IP4_ADDRESS_WITH_MASK" -p tcp -m tcp --dport 22 -j ACCEPT
fi
iptables -A INPUT -p icmp -m addrtype --dst-type LOCAL -j ACCEPT
iptables -A FORWARD -i "$IF_NAME" -o awg+ -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i awg+ -o "$IF_NAME" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i awg+ -j ACCEPT
# AWG
iptables -t nat -A POSTROUTING -s $TUN_NET ! -d $TUN_NET -j MASQUERADE
# mikrotik container network 172.17.0.0/24
iptables -t nat -A POSTROUTING -s $MIKROTIK_CONTAINER_NET ! -d $MIKROTIK_CONTAINER_NET -j MASQUERADE
iptables -P INPUT DROP && iptables -P FORWARD DROP && iptables -P OUTPUT ACCEPT
case $PM in
	yum|dnf) iptables-save > /etc/sysconfig/iptables ;;
	apt|apt-get) iptables-save > /etc/iptables/rules.v4 ;;
esac

if [ -n "$VM_IP6_ADDRESS_WITH_MASK" ]; then
	systemctl enable ip6tables && systemctl start ip6tables
	ip6tables -P INPUT ACCEPT && ip6tables -P FORWARD ACCEPT && ip6tables -P OUTPUT ACCEPT && ip6tables -t nat -F && ip6tables -t mangle -F && ip6tables -F && ip6tables -X
	ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
	ip6tables -A INPUT -i lo -j ACCEPT
	ip6tables -A INPUT -d "$VM_IP6_ADDRESS_WITH_MASK" -p udp -m udp --dport $AWG_PORT -j ACCEPT
	ip6tables -A INPUT -p ipv6-icmp -m addrtype --dst-type LOCAL -j ACCEPT
	ip6tables -A FORWARD -i "$IF_NAME" -o awg+ -m state --state RELATED,ESTABLISHED -j ACCEPT
	ip6tables -A FORWARD -i awg+ -o "$IF_NAME" -m state --state RELATED,ESTABLISHED -j ACCEPT
	ip6tables -A FORWARD -i awg+ -j ACCEPT
fi
ip6tables -P INPUT DROP && ip6tables -P FORWARD DROP && ip6tables -P OUTPUT ACCEPT
case $PM in
	yum|dnf) ip6tables-save > /etc/sysconfig/ip6tables ;;
	apt|apt-get) ip6tables-save > /etc/iptables/rules.v6 ;;
esac

sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

############################################################ Xray install section ############################################################

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --logrotate 04:00:00
mkdir -p /var/log/Xray/
touch /var/log/Xray/access.log
touch /var/log/Xray/error.log
XRAY_CLIENT_ID=$(xray uuid)
XRAY_CLIENT_SID=11aa
xray_gen_keys=$(xray x25519)
XRAY_PRIVATE_KEY=$(echo -n "$xray_gen_keys" | awk '{ print $3; }')
XRAY_PUBLIC_KEY=$(echo -n "$xray_gen_keys" | awk '{ print $6; }')
# server config
function xray_server_config_json() {
cat <<EOF
{
	"log": {
		"access": "/var/log/Xray/access.log",
		"error": "/var/log/Xray/error.log",
		"loglevel": "info",
		"dnsLog": false
	},
	"inbounds": [
		{
			"listen": "$(echo -n $VM_IP4_ADDRESS_WITH_MASK | sed 's/\/[[:digit:]]\{1,2\}$//')",
			"port": $XRAY_SRV_PORT,
			"protocol": "vless",
			"settings": {
				"clients": [
					{
						"id": "$XRAY_CLIENT_ID",
						"email": "mikrotik@local",
						"flow": "",
						"level": 0
					}
				],
				"decryption": "none"
			},
			"streamSettings": {
				"network": "h2",
				"security": "reality",
				"realitySettings": {
					"show": false,
					"dest": "www.pornhub.com:443",
					"xver": 0,
					"serverNames": [
						"www.pornhub.com"
					],
					"privateKey": "$XRAY_PRIVATE_KEY",
					"shortIds": [
						"$XRAY_CLIENT_SID"
					]
				}
			}
		}
	],
	"outbounds": [
		{
			"protocol": "freedom",
			"settings": {
				"domainStrategy": "AsIs",
				"redirect": "127.0.0.1:$AWG_PORT",
				"userLevel": 0,
				"proxyProtocol": 0
			},
			"tag": "direct"
		}
	]
}
EOF
}
xray_server_config_json > /usr/local/etc/xray/config.json

systemctl restart xray.service

# client config
function xray_client_config_json() {
cat <<EOF
{
	"log": {
		"loglevel": "warning"
	},
	"inbounds": [
		{
			"listen": "127.0.0.1",
			"port": $XRAY_CLIENT_PORT,
			"protocol": "dokodemo-door",
			"settings": {
				"address": "127.0.0.1",
				"port": $AWG_PORT,
				"network": "udp",
				"timeout": 30,
				"followRedirect": false,
				"userLevel": 0
			},
			"tag": "awg"
		}
	],
	"outbounds": [
		{
			"sendThrough": "0.0.0.0",
			"protocol": "vless",
			"settings": {
				"vnext": [
					{
						"address": "$(echo -n $VM_IP4_ADDRESS_WITH_MASK | sed 's/\/[[:digit:]]\{1,2\}$//')",
						"port": $XRAY_SRV_PORT,
						"users": [
							{
								"id": "$XRAY_CLIENT_ID",
								"encryption": "none",
								"flow": "",
								"level": 0
							}
						]
					}
				]
			},
			"streamSettings": {
				"network": "h2",
				"security": "reality",
				"realitySettings": {
					"show": false,
					"fingerprint": "random",
					"serverName": "www.pornhub.com",
					"publicKey": "$XRAY_PUBLIC_KEY",
					"shortId": "$XRAY_CLIENT_SID",
					"spiderX": ""
				}
			},
			"tag": "proxy"
		}
	]
}
EOF
}
xray_client_config_json > xray_client_config.json

############################################################# AWG install section #############################################################

case $PM in
	yum|dnf) $PM -y copr enable amneziavpn/amneziawg && ln -s "/usr/src/kernels/$(uname -r)/kernel/" kernel && $PM -y install amneziawg-dkms amneziawg-tools && dkms autoinstall ;;
	apt|apt-get) add-apt-repository -y ppa:amnezia/ppa && apt install -y amneziawg && $PM -y install amneziawg-dkms amneziawg-tools && tar xjf "/usr/src/linux-source-$(uname -r | sed 's/-.*//').tar.bz2" -C /usr/src/ && rm -f "/usr/src/linux-source-$(uname -r | sed 's/-.*//').tar.bz2" && ln -s "/usr/src/linux-source-$(uname -r | sed 's/-.*//')/" kernel && dkms autoinstall ;;
esac

# umask 077

SRV_PRIVATE_KEY=$(awg genkey)
SRV_PUBLIC_KEY=$(echo -n "$SRV_PRIVATE_KEY" | awg pubkey)
CLIENT_PRIVATE_KEY=$(awg genkey)
CLIENT_PUBLIC_KEY=$(awg pubkey <<< "$CLIENT_PRIVATE_KEY")
CLIENT_PRESHARED_KEY=$(awg genpsk)
AWG_JC=$(( ( RANDOM % 7 )  + 3 ))
AWG_JMIN=$(( ( RANDOM % 9 )  + 50 ))
AWG_JMAX=$(( ( RANDOM % 280 )  + 1000 ))
AWG_S1=$(( ( RANDOM % 145 )  + 15 ))
while true; do
	AWG_S2=$(( ( RANDOM % 145 )  + 15 ))
	if [[ $(( AWG_S1 + 56 )) -ne $AWG_S2 ]]; then break; fi 
done
while true; do
	gen_numbers=()
	for _ in {1..5}; do
		gen_numbers+=($(( ( RANDOM % 2147483642 )  + 5 )))
	done
	mapfile -t unique_numbers < <(echo "${gen_numbers[*]}" | tr ' ' '\n' | sort -u)
	if [[ ${#unique_numbers[@]} -gt 3 ]]; then
		AWG_H1=${unique_numbers[0]}
		AWG_H2=${unique_numbers[1]}
		AWG_H3=${unique_numbers[2]}
		AWG_H4=${unique_numbers[3]}
		break
	fi
done

echo "# AWG server config
# Do not alter the commented lines, they are maybe used by wireguard-install or same
# ENDPOINT $(echo -n $VM_IP4_ADDRESS_WITH_MASK | sed 's/\/[[:digit:]]\{1,2\}$//')

[Interface]
Address = $(echo -n $TUN_NET | sed 's/\([[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\.\).\(\/[[:digit:]]\{1,2\}\)$/\11\2/')
PrivateKey = $SRV_PRIVATE_KEY
#PublicKey = $SRV_PUBLIC_KEY
ListenPort = $AWG_PORT
MTU = $TUN_MTU
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4


# BEGIN_PEER mikrotik
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $CLIENT_PRESHARED_KEY
AllowedIPs = $(echo -n $TUN_NET | sed 's/[[:digit:]]\{1,3\}\/[[:digit:]]\{1,2\}$/2\/32/'), $(echo -n $MIKROTIK_CONTAINER_NET | sed 's/[[:digit:]]\{1,3\}\/[[:digit:]]\{1,2\}$/1\/32/')
# END_PEER mikrotik
" | tee -a /etc/amnezia/amneziawg/awg0.conf

echo "# mikrotik configuration
[Interface]
Address = $(echo -n $TUN_NET | sed 's/\([[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\.\).\(\/[[:digit:]]\{1,2\}\)$/\12\2/')
DNS = 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1
PrivateKey = $CLIENT_PRIVATE_KEY
#PublicKey = $CLIENT_PUBLIC_KEY
ListenPort = $AWG_PORT
MTU = $TUN_MTU
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4


[Peer]
PublicKey = $SRV_PUBLIC_KEY
PresharedKey = $CLIENT_PRESHARED_KEY
# https://www.procustodibus.com/blog/2021/03/wireguard-allowedips-calculator/
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $(echo -n $VM_IP4_ADDRESS_WITH_MASK | sed 's/\/[[:digit:]]\{1,2\}$//'):$AWG_PORT
# Endpoint = 127.0.0.1:$XRAY_CLIENT_PORT
" | tee -a awg_client.conf

awg-quick up awg0
systemctl enable awg-quick@awg0.service

############################################################# cleanup section #############################################################

$PM clean all
case $PM in
	yum|dnf) $PM clean all ;;
	apt|apt-get) rm -rf "/usr/src/linux-source-$(uname -r | sed 's/-.*//')/" kernel && apt remove linux-source && apt -y autoremove ;;
esac
clean_swap
echo "AWG and Xray client configs: awg_client.conf & xray_client_config.json"
ls -lah
sleep 15

############################################################# net tune section #############################################################

echo " 
vm.swappiness = 1
net.ipv4.ip_forward = 1
# Defines the maximum receive window size.
net.core.rmem_max = 67108864 
# Defines the default send window size.
net.core.wmem_max = 67108864 
# The kernel parameter 'netdev_max_backlog' is the maximum size of the receive queue. The received frames will be stored in this queue after taking them from the ring buffer on the NIC. Use high value for high speed cards to prevent loosing packets.
net.core.netdev_max_backlog = 100000 
# The net.core.somaxconn kernel parameter is used to set the maximum number of connections that can be queued for a socket. This parameter is used to prevent a flood of connection requests from overwhelming the system.
# In other words, this parameter determines the maximum length of the queue of pending connections that are waiting to be accepted by the system. And it’s used to prevent the system from being overwhelmed with too many connections that it cannot handle.
net.core.somaxconn = 4096 
# Note, that syncookies is fallback facility. It MUST NOT be used to help highly loaded servers to stand against legal connection rate.
net.ipv4.tcp_syncookies = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 20
net.ipv4.ip_local_port_range = 10000 60999
net.ipv4.tcp_fastopen = 3
# net.ipv4.tcp_fastopen_blackhole_timeout_sec = 0 # w?
# Contains three values that represent the minimum, default and maximum size of the TCP socket receive buffer.
net.ipv4.tcp_rmem = 4096 131072 67108864
# Similar to the net.ipv4.tcp_rmem TCP send socket buffer size
net.ipv4.tcp_wmem = 4096 87380 67108864
# Controls TCP Packetization-Layer Path MTU Discovery. Takes three values: 0 - Disabled 1 - Disabled by default, enabled when an ICMP black hole detected 2 - Always enabled, use initial MSS of tcp_base_mss.
net.ipv4.tcp_mtu_probing = 1
# Ubuntu 24.04 tcp_congestion_control props
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control = bbr
" | sed -e 's/^\s\+//g' | tee -a /etc/sysctl.conf
sysctl -p
echo " 
* soft nofile 51200 
* hard nofile 524288 
" | sed -e 's/^\s\+//g' | tee -a /etc/security/limits.conf
reboot