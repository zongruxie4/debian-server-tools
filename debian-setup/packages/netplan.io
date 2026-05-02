#!/bin/bash

set -e -x

NETPLAN_CONFIG="/etc/netplan/50-cloud-init.yaml"

Netplan()
{
    python3 /usr/local/bin/shyaml "$@" < "$NETPLAN_CONFIG"
}

if ! grep -q "configured to use Netplan" /etc/network/interfaces; then
    exit 0
fi

test -f "$NETPLAN_CONFIG"
cp -a "$NETPLAN_CONFIG" /root/dist-mod/
cp -a /etc/network/interfaces /root/dist-mod/interfaces.netplan-stub

{
    echo "# Generated from ${NETPLAN_CONFIG}"
    echo
    echo "auto lo"
    echo "iface lo inet loopback"
    echo

    for IFACE in $(Netplan keys "network.ethernets"); do
        if [ "$(Netplan get-value "network.ethernets.${IFACE}.dhcp4" "false")" == "True" ]; then
            echo "auto ${IFACE}"
            echo "iface ${IFACE} inet dhcp"
            echo
        fi

        if [ "$(Netplan get-value "network.ethernets.${IFACE}.dhcp6" "false")" == "True" ]; then
            echo "auto ${IFACE}"
            echo "iface ${IFACE} inet6 auto"
            echo
        fi
    done
} >/etc/network/interfaces

ifquery --list
for IFACE in $(Netplan keys "network.ethernets"); do
    ifquery "$IFACE"
done

apt-get purge -qq netplan.io netplan-generator python3-netplan libnetplan1
