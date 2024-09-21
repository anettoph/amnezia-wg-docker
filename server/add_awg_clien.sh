#!/bin/bash
# AWG add client script
if [ -z $1 ]; then 
	echo "Type client name. Use one word only, no special characters except '-' and '_'."
	read -p 'Client name:' CLIENT_NAME
else
	CLIENT_NAME=$1
fi
IF_NAME=$(ip route | grep '^default' |  sed -n 's/.*dev \([^\ ]*\).*/\1/p')
VM_IP4_ADDRESS_WITH_MASK=$(ip -4 addr show $IF_NAME | grep inet | awk '{ print $2; }' | grep -Eo '^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$' | sed 's/\/[[:digit:]]\{1,2\}$//')
TUN_GW_WITH_MASK=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'Address =' | awk '{ print $3; }')
AWG_PORT=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'ListenPort =' | awk '{ print $3; }')
TUN_MTU=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'MTU =' | awk '{ print $3; }')
AWG_JC=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'Jc =' | awk '{ print $3; }')
AWG_JMIN=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'Jmin =' | awk '{ print $3; }')
AWG_JMAX=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'Jmax =' | awk '{ print $3; }')
AWG_S1=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'S1 =' | awk '{ print $3; }')
AWG_S2=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'S2 =' | awk '{ print $3; }')
AWG_H1=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'H1 =' | awk '{ print $3; }')
AWG_H2=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'H2 =' | awk '{ print $3; }')
AWG_H3=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'H3 =' | awk '{ print $3; }')
AWG_H4=$(cat /etc/amnezia/amneziawg/awg0.conf | grep 'H4 =' | awk '{ print $3; }')

SRV_PUBLIC_KEY=$(cat /etc/amnezia/amneziawg/awg0.conf | grep '#PublicKey =' | awk '{ print $3; }')
CLIENT_PRIVATE_KEY=$(awg genkey)
CLIENT_PUBLIC_KEY=$(awg pubkey <<< "$CLIENT_PRIVATE_KEY")
CLIENT_PRESHARED_KEY=$(awg genpsk)
LAST_CLIENT_IP_DIGIT=$(tac /etc/amnezia/amneziawg/awg0.conf | grep -m1 'AllowedIPs =' | awk '{ print $3; }' | sed -E 's/^.*\.(.*)\/.*/\1/')
[ -z "$LAST_CLIENT_IP_DIGIT" ] && LAST_CLIENT_IP_DIGIT=$(tac /etc/amnezia/amneziawg/awg0.conf | grep -m1 'Address =' | awk '{ print $3; }' | sed -E 's/^.*\.(.*)\/.*/\1/') || exit 1
CLIENT_IP=$(echo -n $TUN_GW_WITH_MASK | sed "s/\([[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\.\).\(\/[[:digit:]]\{1,2\}\)$/\1$((LAST_CLIENT_IP_DIGIT + 1))/")


echo "# BEGIN_PEER $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $CLIENT_PRESHARED_KEY
AllowedIPs = ${CLIENT_IP}/32
# END_PEER $CLIENT_NAME
" | tee -a /etc/amnezia/amneziawg/awg0.conf


echo "# $CLIENT_NAME configuration
[Interface]
Address = ${CLIENT_IP}/24
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
# Endpoint = 127.0.0.1:XRAY_CLIENT_PORT
" | tee -a awg_$(echo -n "$CLIENT_NAME" | sed 's/ /_/g').conf

awg-quick down awg0 && awg-quick up awg0
