#!/usr/bin/env bash

release=`lsb_release -c | cut -f 2-`

if [ $release == "bionic" ]
then

######################################
# Consul DNS, systemd-resolved setup #
######################################

  echo -e "DNS=127.0.0.1 \nDomains=~consul" >> /etc/systemd/resolved.conf
  iptables -t nat -A OUTPUT -d localhost -p udp -m udp --dport 53 -j REDIRECT --to-ports 8600
  iptables -t nat -A OUTPUT -d localhost -p tcp -m tcp --dport 53 -j REDIRECT --to-ports 8600
  service systemd-resolved restart

    # Do this
elif [ $release == "xenial" ]
then

apt-get install dnsmasq -y

#######################################################################
# Consul DNS, to be resolved in the consul domain as well as external #
#######################################################################
sudo echo "server=/consul/127.0.0.1#8600" > /etc/dnsmasq.d/10-consul

sudo sed -i 's/#resolv-file=/resolv\-file=\/etc\/dnsmasq.d\/external.conf/g' /etc/dnsmasq.conf

cat <<EOF > /etc/dnsmasq.d/external.conf
server=8.8.8.8
EOF

sudo systemctl restart dnsmasq

else
    echo "Unsupported OS Release. Exit...";
fi





