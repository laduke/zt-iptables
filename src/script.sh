#!/usr/bin/env bash

# set -o errexit
set -o nounset
# set -o pipefail

CHAIN_INPUT="zt-in"
CHAIN_OUTPUT="zt-out"
CHAIN_FORWARD="zt-fwd"
CHAIN_POSTROUTING="zt-post"

VL1_TAG="zt-vl1"
vl1__flush () {
    echo "Clearing existing \"${VL1_TAG}\" rules"

    clear_by_tag ${VL1_TAG} filter
}

vl1__insert () {
    chains__insert

    vl1__flush

    echo "Inserting \"${VL1_TAG}\" rules"

    iptables -I ${CHAIN_OUTPUT} --match owner --uid-owner zerotier-one --jump ACCEPT -m comment --comment "${VL1_TAG}"
    iptables -I ${CHAIN_INPUT} --protocol udp --match udp --dport 9993 --jump ACCEPT -m comment --comment "${VL1_TAG}"
}

VL2_TAG="zt-vl2"
vl2__flush () {
    echo "Clearing existing \"${VL2_TAG}\" rules"

    clear_by_tag ${VL2_TAG} filter
}

vl2__insert () {
    chains__insert

    vl2__flush

    echo "Inserting \"${VL2_TAG}\" rules"

    iptables -I ${CHAIN_OUTPUT} --out-interface zt+ --jump ACCEPT -m comment --comment "${VL2_TAG}"
    iptables -I ${CHAIN_INPUT}   --in-interface zt+ --jump ACCEPT -m comment --comment "${VL2_TAG}"
    iptables -I ${CHAIN_FORWARD} --in-interface zt+ --jump ACCEPT -m comment --comment "${VL2_TAG}"
    iptables -I ${CHAIN_FORWARD} --out-interface zt+ --jump ACCEPT -m comment --comment "${VL2_TAG}"
}



SNAT_TAG="zt-snat"

snat__insert () {
    source $1

    echo "Setting up SNAT for: "
    echo "ZT_ID=${ZT_ID}"
    echo "ZT_NET=${ZT_NET}"
    echo "ZT_IF=${ZT_IF}"
    echo "GATEWAY_IP=${GATEWAY_IP}"
    echo "GATEWAY_IF=${GATEWAY_IF}"

    SNAT_TAG="zt-snat-${ZT_ID}"

    chains__insert
    snat__flush $ZT_ID

    iptables -I ${CHAIN_FORWARD} --in-interface ${ZT_IF} --jump ACCEPT -m comment --comment "${SNAT_TAG}"
    iptables -I ${CHAIN_FORWARD} --out-interface ${ZT_IF} --jump ACCEPT -m comment --comment "${SNAT_TAG}"

    iptables -t nat -I ${CHAIN_POSTROUTING} -s ${ZT_NET} -o ${GATEWAY_IF} -j SNAT --to-source ${GATEWAY_IP} -m comment --comment "${SNAT_TAG}"
}

snat__flush () {
    NWID=$1
    iptables -t nat -S | grep "$NWID" | grep "\-A" | cut -d " " -f 2- | xargs -rL1 iptables -t nat -D
    iptables -S | grep "$NWID" | cut -d " " -f 2- | xargs -rL1 iptables -D
}

snat__gather () {
    ZT_ID=$1

    # v4 route with no via
    ZT_NET=$(zerotier-cli listnetworks -j | jq -r ".[] | select(.nwid == \"${ZT_ID}\") | .routes[] | select(.via == null) | select(.target|test(\"^[^:]*$\")) | .target")
    ZT_IF=$(zerotier-cli listnetworks -j | jq -r ".[] | select(.nwid == \"${ZT_ID}\") | .portDeviceName")
    GATEWAY_IP=$(curl -s -4 ifconfig.co)
    GATEWAY_IF=$(ip -br -4 a sh | grep ${GATEWAY_IP} | cut -f1 -d" ")

    echo "ZT_ID=${ZT_ID}"
    echo "ZT_NET=${ZT_NET}"
    echo "ZT_IF=${ZT_IF}"
    echo "GATEWAY_IP=${GATEWAY_IP}"
    echo "GATEWAY_IF=${GATEWAY_IF}"
}

chains__flush () {
    iptables -F ${CHAIN_INPUT} &> /dev/null
    iptables -F ${CHAIN_OUTPUT} &> /dev/null
    iptables -F ${CHAIN_FORWARD} &> /dev/null
    iptables -t nat -F ${CHAIN_POSTROUTING} &> /dev/null

    # clear references to the chains
    iptables -t filter -S | grep "zt-" | grep "\-A" | cut -d " " -f 2- | xargs -rL1 iptables -t filter -D
    iptables -t nat -S | grep "zt-" | grep "\-A" | cut -d " " -f 2- | xargs -rL1 iptables -t nat -D

    # delete chains
    iptables -X ${CHAIN_INPUT} &> /dev/null
    iptables -X ${CHAIN_OUTPUT} &> /dev/null
    iptables -X ${CHAIN_FORWARD} &> /dev/null
    iptables -t nat -X ${CHAIN_POSTROUTING} &> /dev/null
}

chains__insert () {
    if ! iptables -t filter -C INPUT -j ${CHAIN_INPUT} &> /dev/null ; then
        iptables -N ${CHAIN_INPUT}
        iptables -I INPUT  -j ${CHAIN_INPUT}
        iptables -A ${CHAIN_INPUT} -j RETURN
    fi

    if ! iptables -t filter -C OUTPUT -j ${CHAIN_OUTPUT} &> /dev/null; then
        iptables -N ${CHAIN_OUTPUT}
        iptables -I OUTPUT -j ${CHAIN_OUTPUT}
        iptables -A ${CHAIN_OUTPUT} -j RETURN
    fi

    if ! iptables -t filter -C FORWARD -j ${CHAIN_FORWARD} &> /dev/null; then
        iptables -N ${CHAIN_FORWARD}
        iptables -I FORWARD -j ${CHAIN_FORWARD}
        iptables -A ${CHAIN_FORWARD} -j RETURN
    fi

    if ! iptables -t nat -C POSTROUTING -j ${CHAIN_POSTROUTING} &> /dev/null; then
        iptables -t nat -N ${CHAIN_POSTROUTING}
        iptables -t nat -I POSTROUTING -j ${CHAIN_POSTROUTING}
        iptables -t nat -A ${CHAIN_POSTROUTING} -j RETURN
    fi
}



clear_by_tag () {
    TAG="$1"
    TABLE="$2"
    TABLE=${TABLE:-filter}

    iptables -t $TABLE -S | grep ${TAG} | cut -d " " -f 2- | xargs -rL1 iptables -t $TABLE -D
}


if declare -f "${1}__$2" >/dev/null; then
  func="${1}__$2"
  shift; shift    # pop $1 and $2 off the argument list
  "$func" "$@"    # invoke our named function w/ all remaining arguments
elif declare -f "$1" >/dev/null 2>&1; then
  "$@"
else
  echo "Neither function $1 nor subcommand ${1}__$2 recognized" >&2
  exit 1
fi
