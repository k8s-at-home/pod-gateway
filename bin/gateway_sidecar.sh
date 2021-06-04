#!/bin/sh -ex

# Load main settings
cat /config/default_settings.sh
. /config/default_settings.sh
cat /config/settings.sh
. /config/settings.sh

#Get K8S DNS
K8S_DNS=$(grep nameserver /etc/resolv.conf|cut -d' ' -f2)

#create config
echo "

# DHCP server settings
interface=vxlan0
bind-interfaces

# Dynamic IPs assigned to PODs - we keep a range for static IPs
dhcp-range=${VXLAN_IP_NETWORK}.${VXLAN_GATEWAY_FIRST_DYNAMIC_IP},${VXLAN_IP_NETWORK}.255,12h

# For debugging purposes, log each DNS query as it passes through
# dnsmasq.
log-queries                                                 
                                                                
# Log lots of extra information about DHCP transactions.          
log-dhcp

# Log to stdout
log-facility=-
">>/etc/dnsmasq.conf

for local_cidr in ${DNS_LOCAL_CIDRS}; do
echo "
# Send ${local_cidr} DNS queries to the K8S DNS server
server=/${local_cidr}/${K8S_DNS}
">>/etc/dnsmasq.conf
done

# Need to wait until new DNS server in /etc/resolv.conf is setup
# by the VPN.
#
# dnsmasq should be able to detect changes in /etc/resolv.conf
# and reload the settings but this does not work
#
# TBD: find a better way...
sleep 10

exec dnsmasq -k
