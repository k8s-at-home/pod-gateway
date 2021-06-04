#!/bin/sh -ex

# Load main settings
cat /config/default_settings.sh
. /config/default_settings.sh
cat /config/settings.sh
. /config/settings.sh

# Create VXLAN NIC
ip link add vxlan0 type vxlan id $VXLAN_ID  dev eth0 dstport 0 || true
ip addr add ${VXLAN_GATEWAY_IP}/24 dev vxlan0 || true
ip link set up dev vxlan0

# Enable outbound NAT
iptables -t nat -A POSTROUTING -j MASQUERADE

if [ -n "${VPN_INTERFACE}" ]; then
  # Open inbound NAT ports in nat.conf
  while read aLine; do
    case "$aLine" in
      \#*) continue;;
      *) echo Processing: $aLine ;;
    esac
    # Skip lines with comments
    [[ '$aLine' == \#* ]] && continue
    NAME=$(echo $aLine|cut -d' ' -f1)
    IP=$(echo $aLine|cut -d' ' -f2)
    PORTS=$(echo $aLine|cut -d' ' -f3)
    # Add NAT entries
    for portStr in $(echo $PORTS|sed 's/,/ /g'); do
      PORT_TYPE=$(echo $portStr|cut -d':' -f1)
      PORT_NUMBER=$(echo $portStr|cut -d':' -f2)
      echo "IP: $IP , NAME: $NAME , PORT: $PORT_NUMBER , TYPE: $PORT_TYPE"
      iptables -t nat -A PREROUTING -p ${PORT_TYPE} -i ${VPN_INTERFACE} --dport ${PORT_NUMBER} -j DNAT --to-destination ${VXLAN_IP_NETWORK}.${IP}:${PORT_NUMBER}
      iptables -A FORWARD -p ${PORT_TYPE} -d ${VXLAN_IP_NETWORK}.${IP} --dport ${PORT_NUMBER} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    done
  done </config/nat.conf

  echo "Setting iptables for VPN with NIC ${VPN_INTERFACE}"
  # Firewall incomming traffic from VPN
  echo Accept traffic alredy ESTABLISHED
  iptables -A FORWARD -i ${VPN_INTERFACE} -m state --state ESTABLISHED,RELATED -j ACCEPT
  # Reject other traffic"
  iptables -A FORWARD -i ${VPN_INTERFACE} -j REJECT

  if [ "$VPN_BLOCK_OTHER_TRAFFIC" = true ] ; then
    # Do not forward any traffic that does not leave through ${VPN_INTERFACE}
    # The openvpn will also add drop rules but this is to ensure we block even if VPN is not connecting
    iptables --policy FORWARD DROP
    iptables -I FORWARD -o ${VPN_INTERFACE} -j ACCEPT

    # Do not allow outbound traffic on eth0 beyond VPN and local traffic
    iptables --policy OUTPUT DROP
    iptables -A OUTPUT -p udp --dport ${VPN_TRAFFIC_PORT} -j ACCEPT #VPN traffic over UDP
    iptables -A OUTPUT -p tcp --dport ${VPN_TRAFFIC_PORT} -j ACCEPT #VPN traffic over TCP

    # Allow local traffic
    for local_cidr in ${VPN_LOCAL_CIDRS}; do
      iptables -A OUTPUT -d ${local_cidr} -j ACCEPT
    done

    # Allow output for VPN and VXLAN
    iptables -A OUTPUT -o ${VPN_INTERFACE} -j ACCEPT
    iptables -A OUTPUT -o vxlan0 -j ACCEPT
  fi

  #Routes for local networks
  K8S_GW_IP=$(/sbin/ip route | awk '/default/ { print $3 }')
  for local_cidr in ${VPN_LOCAL_CIDRS}; do
    # command might fail if rule already set
    ip route add ${local_cidr} via ${K8S_GW_IP} || /bin/true
  done

fi
