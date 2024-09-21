## About The Project
Mikrotik compatible Docker image to run Amnezia WG over Xray(vless+reality) tunnel on Mikrotik routers. As of now, support ARM64 boards(tested on hAP ax^3 7.15.3 (stable) as client and VPS [amneziawg-linux-kernel-module](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module)@AlmaLinux9 as server)

## About The Project
This is a highly experimental attempt to run [Amnezia-WG](https://github.com/amnezia-vpn/amnezia-wg) over [Xray](https://computerscot.github.io/wireguard-over-xray.html) on a Mikrotik router in containers.
[Xray-doc](https://xtls.github.io/ru/config/)

### Prerequisites

Follow the [Mikrotik guidelines](https://help.mikrotik.com/docs/display/ROS/Container) to enable container support.

Install [Docker buildx](https://github.com/docker/buildx) subsystem, make and go.
```
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo apt install qemu-user-static

``` 

### Building Docker Image

You may need(nope) to initialize submodules
```
git submodule add --force https://github.com/amnezia-vpn/amneziawg-go.git amneziawg-go
git submodule update --init --force --remote
```

To build a Docker container for the ARM64 v8 run
```
DOCKER_BUILDKIT=1  docker buildx build --no-cache --platform linux/arm64/v8 --output=type=docker --tag docker-awg:latest .
cd Xray; DOCKER_BUILDKIT=1  docker buildx build --platform linux/arm64/v8 --build-arg TARGETPLATFORM=linux/arm64/v8 --output=type=docker --tag xray-arm64:latest .
```
This command should cross-compile amnezia-wg locally and then build a docker image for ARM64 arch.

To export a generated image, use
```
docker save docker-awg:latest > docker-awg-arm8.tar
cd Xray; docker save  xray-arm64:latest > xray-arm64.tar
```

You will get the `docker-awg-arm8.tar` archive ready to upload to the Mikrotik router.

### Running locally

Just run `docker compose up`

Make sure to create a `wg` folder with the `awg0.conf` file.

Example client `awg0.conf`:

```
[Interface]
Address = 10.8.0.3/24
DNS = 8.8.8.8, 8.8.4.4
PrivateKey = SF..lQ=
ListenPort = 51820
MTU = 1420
Jc = 1 ≤ Jc ≤ 128; recommended range is from 3 to 10 inclusive
Jmin = Jmin < Jmax; recommended value is 50
Jmax = Jmin < Jmax ≤ 1280; recommended value is 1000
S1 = S1 < 1280; S1 + 56 ≠ S2; recommended range is from 15 to 150 inclusive 
S2 = S2 < 1280; recommended range is from 15 to 150 inclusive
H1 = H1/H2/H3/H4 — must be unique among each other; recommended range is from 5 to 2147483647 inclusive
H2 = H1/H2/H3/H4 — must be unique among each other; recommended range is from 5 to 2147483647 inclusive
H3 = H1/H2/H3/H4 — must be unique among each other; recommended range is from 5 to 2147483647 inclusive
H4 = H1/H2/H3/H4 — must be unique among each other; recommended range is from 5 to 2147483647 inclusive

[Peer]
PublicKey = 33..0o=
PresharedKey = qa..sY=
AllowedIPs = don't use 0.0.0.0/0, include 10.8.0.0/24, exclude local networks, exclude Endpoint address -> https://www.procustodibus.com/blog/2021/03/wireguard-allowedips-calculator/
Endpoint = 127.0.0.1:51821
PersistentKeepalive = 15

```

Example server `awg0.conf`:

```
[Interface]
Address = 10.8.0.1/24
PrivateKey = KF..Uw=
ListenPort = 51820
MTU = 1420
Jc = 1 ≤ Jc ≤ 128; recommended range is from 3 to 10 inclusive
Jmin = Jmin < Jmax; recommended value is 50
Jmax = Jmin < Jmax ≤ 1280; recommended value is 1000
S1 = S1 < 1280; S1 + 56 ≠ S2; recommended range is from 15 to 150 inclusive 
S2 = S2 < 1280; recommended range is from 15 to 150 inclusive
H1 = H1/H2/H3/H4 — must be unique among each other; recommended range is from 5 to 2147483647 inclusive
H2 = H1/H2/H3/H4 — must be unique among each other; recommended range is from 5 to 2147483647 inclusive
H3 = H1/H2/H3/H4 — must be unique among each other; recommended range is from 5 to 2147483647 inclusive
H4 = H1/H2/H3/H4 — must be unique among each other; recommended range is from 5 to 2147483647 inclusive

[Peer]
PublicKey = Fz..Dk=
PresharedKey = qa..sY=
AllowedIPs = 10.8.0.3/32, 172.17.0.1/32

```


### Mikrotik Configuration

Set up interface and IP address for the containers

```
/interface bridge
add name=containers

/interface veth
add address=172.17.0.2/24 gateway=172.17.0.1 gateway6="" name=veth1

/interface bridge port
add bridge=containers interface=veth1
add bridge=containers interface=veth2

/ip address
add address=172.17.0.1/24 interface=containers network=172.17.0.0
```

Add address list
```
/ip firewall address-list
add address=2ip.ru list=rkn_wg
```

Set up masquerading for the outgoing traffic and dstnat

```
/ip firewall nat
add chain=srcnat action=masquerade comment="NAT for containers network" dst-address=!172.17.0.0/24 out-interface=containers
/ip firewall nat
add action=dst-nat chain=dstnat comment=amnezia-wg dst-port=51820 protocol=udp to-addresses=172.17.0.2 to-ports=51820
```

Mask our internal IP's from containers
```
/ip firewall nat
add action=masquerade chain=srcnat out-interface=containers log=no log-prefix="" 
```

Add route mark
```
/ip firewall mangle
add action=mark-routing chain=prerouting dst-address-list=rkn_wg \
    new-routing-mark=wg_mark passthrough=yes
```

Add routing table
```
/routing table
add disabled=no fib name=wg_mark
```

Add route for marked table
```
/ip route
add disabled=no distance=2 dst-address=0.0.0.0/0 gateway=172.17.0.2 \
    routing-table=wg_mark scope=30 suppress-hw-offload=no target-scope=10
```

Set up mount with the Wireguard configuration

```
/container mounts
add name="awg_conf" src="/usb1/docker/data/awg_conf" dst="/etc/amnezia/amneziawg/" 
add name="xray_conf" src="/usb1/docker/data/xray_conf" dst="/etc/xray/" 

/container/add cmd=/sbin/init hostname=amnezia interface=veth1 logging=yes mounts=awg_config file=docker-awg-arm8.tar
/container/add cmd=/sbin/init hostname=xray interface=veth1 logging=yes mounts=xray_conf file=xray-arm64:latest
```

To start the container run

```
/container/start number=0
/container/start number=1
```

To get the container shell

```
/container/shell number=0
/container/shell number=1
```