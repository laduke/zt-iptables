# Some helpers for adding zerotier related rules to iptables
Adds some zt-* chains and adds some rules to them

Built on a debian based VPS with a public IP. 
I'm not a bash expert. I do not manage iptables for a living. 

## Summary
- `curl -O https://raw.githubusercontent.com/laduke/zt-iptables/main/src/script.sh`
- `bash script.sh vl1 insert`
- `bash script.sh snat gather $NETWORK_ID > my-config`
- `bash script.sh snat insert my-config` 
- `iptables-save` // take a look

There, now your VPS can be an exit to the internet.

Don't forget to enable ip forwarding.

``` shell
sysctl -w net.ipv4.conf.all.forwarding=1 
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ip_forward.conf
```


## VL1

Allows zerotier to peer with other nodes.

- Allows the zerotier-one process to send any UDP. 
- Allows incoming port 9993/udp

### Usage

- `bash script.sh vl1 insert`
- `bash script.sh vl1 flush`

### What it adds
Basically:

```shell
-A zt-in -p udp -m udp --dport 9993 -m comment --comment zt-vl1 -j ACCEPT
-A zt-out -m owner --uid-owner 998 -m comment --comment zt-vl1 -j ACCEPT
```


## VL2

Allows all traffic on all zerotier interfaces.

### Usage

- `bash script.sh vl2 insert`
- `bash script.sh vl2 flush`

### What it adds
Basically:

``` shell
-A zt-in -i zt+ -m comment --comment zt-vl2 -j ACCEPT
-A zt-out -o zt+ -m comment --comment zt-vl2 -j ACCEPT
-A zt-fwd -o zt+ -m comment --comment zt-vl2 -j ACCEPT
-A zt-fwd -i zt+ -m comment --comment zt-vl2 -j ACCEPT
```

## SNAT
Use your VPS as an internet gateway

### Usage
- `bash script.sh snat gather $NETWORK_ID > my-config` // try to guess SNAT configuration. requires `jq` and `curl` 

- `bash script.sh snat insert my-config` // add the guessed configuration
- `bash script.sh snat flush $NETWORK_ID` 

### What it adds

``` shell
-A zt-fwd -o zt3jn2z57r -m comment --comment zt-snat-9bee8941b0000001 -j ACCEPT
-A zt-fwd -i zt3jn2z57r -m comment --comment zt-snat-9bee8941b0000001 -j ACCEPT
-A zt-post -s 10.2.0.0/24 -o enp1s0 -m comment --comment zt-snat-9bee8941b000001 -j SNAT --to-source xx.211.111.224
```


## Extra

- `bash script.sh chains insert` // the other commands do this automatically
- `bash script.sh chains flush` // deletes everything added by these scripts

## Dev

### 
work locally and automatically sync to remote machine

something like:

```
nodemon -e sh -w ./src -x 'rsync -avPh --delete src root@$IP_ADDRESS:/root/zt-iptables'
```


## TODO
- [ ] ip6tables
- [ ] masquerade
- [ ] vl2 with specific zerotier networks
