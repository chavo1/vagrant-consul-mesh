#!/usr/bin/env bash

SERVER_COUNT=${SERVER_COUNT}
CLIENT_COUNT=${CLIENT_COUNT}
CONSUL_VERSION=${CONSUL_VERSION}
DOMAIN=${DOMAIN}
TLS_ENABLE=${TLS_ENABLE}
IPs=$(hostname -I | cut -f2 -d' ')
HOST=$(hostname)

#############
# Functions #
#############
unseal_vault () { 
        for x in {0..2}; do
            echo $x
            for u in {0..2}; do
                ukey=key${x}
                `curl --insecure --cacert /etc/consul.d/ssl/vault.crt --header --request PUT --data '{"key": "'${!ukey}'"}' $1`
            done
        done
}

acquiring_certs_from_vault () {

      pushd /etc/consul.d/ssl/
          GENCERT=`curl --insecure --cacert /etc/consul.d/ssl/vault.crt --header "X-Vault-Token: $1" --request POST --data '{"common_name": "'$2.$3.$4'", "ttl": "24h", "alt_names": "localhost", "ip_sans": "127.0.0.1"}' $httpUrl`
        if [ $? -ne 0 ]; then
            echo "Vault is not available. Exit ..."
            exit 1 # if vault is not available script will be terminated
        else
            echo $GENCERT | jq -r .data.issuing_ca > consul-agent-ca.pem
            echo $GENCERT | jq -r .data.certificate > consul-agent.pem
            echo $GENCERT | jq -r .data.private_key > consul-agent.key
        fi
      popd
}

enabling_gossip_encryption () {
    if [ $1 == consul-dc1-server01 ]; then
        crypto=`consul keygen` # Generate an encryption key only for first node
sudo cat <<EOF > /etc/consul.d/encrypt.json
{"encrypt": "${crypto}"}
EOF
    else # Copying the key from first node to the other agents
        sshpass -p 'vagrant' scp -o StrictHostKeyChecking=no vagrant@192.168.56.51:"/etc/consul.d/encrypt.json" /etc/consul.d/

    fi
}

# Install packages
which unzip socat jq dig route vim curl sshpass &>/dev/null || {
    apt-get update -y
    apt-get install unzip socat net-tools jq dnsutils vim curl sshpass -y 
}

#####################
# Installing consul #
#####################
sudo mkdir -p /vagrant/pkg

which consul || {
    # check if consul file exist.
    CHECKFILE="/vagrant/pkg/consul_${CONSUL_VERSION}_linux_amd64.zip"
    if [ ! -f "$CHECKFILE" ]; then
        pushd /vagrant/pkg
        wget https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip
        popd
    fi
    
    pushd /usr/local/bin/
    unzip /vagrant/pkg/consul_${CONSUL_VERSION}_linux_amd64.zip 
    sudo chmod +x consul
    popd
}

killall consul
sudo mkdir -p /etc/consul.d/ssl /vagrant/consul_logs

# ###########################
# # Starting consul servers #
# ###########################
if [[ $IPs =~ 192.168.56 ]]; then # if 192.168.56 it is dc1
    DC_RANGE="192.168.56"
    DC=dc1
    WAN=""
elif [[ $IPs =~ 192.168.57 ]]; then  # if 192.168.57 it is dc2
    DC_RANGE_OP="192.168.56"
    DC_RANGE="192.168.57"
    DC=dc2
    WAN=", \"retry_join_wan\": [ \"$DC_RANGE_OP.51\", \"$DC_RANGE_OP.52\", \"$DC_RANGE_OP.53\" ]"
else 
    DC_RANGE_OP="192.168.57"
    DC_RANGE="192.168.58"
    DC=dc3
    WAN=", \"retry_join_wan\": [ \"$DC_RANGE_OP.51\", \"$DC_RANGE_OP.52\", \"$DC_RANGE_OP.53\" ]"
fi   
NODE_TYPE=client
  if [[ $HOST =~ server ]]; then
    # if the name contain server we are there
    NODE_TYPE=server
  fi
  LAN=", \"retry_join\": [ \"$DC_RANGE.51\", \"$DC_RANGE.52\", \"$DC_RANGE.53\" ]"
  

######################## 
# Creating consul user # 
########################
sudo groupadd --system consul
sudo useradd -s /sbin/nologin --system -g consul consul
sudo mkdir -p /var/lib/consul
sudo chown -R consul:consul /var/lib/consul
sudo chmod -R 775 /var/lib/consul
sudo chown -R consul:consul /etc/consul.d/ssl 

# If TLS is enabled
if [ "$TLS_ENABLE" = true ] ; then
    # Setting variables 
    VAULT_TOKEN=`cat /vagrant/token/keys.txt | grep "Initial Root Token:" | cut -c21-` # Vault token, it is needed to access vault
    httpUrl="https://192.168.56.71:8200/v1/pki_int/issue/example-dot-com" # Vault address, from where the certificates will be acquired
    VaultunSeal="https://192.168.56.71:8200/v1/sys/unseal" # Curl url to unseal Vault
    VaultSeal="https://192.168.56.71:8200/v1/sys/seal" # Curl url to seal Vault
    key0=`cat /vagrant/token/keys.txt | grep "Unseal Key 1:" | cut -c15-` #
    key1=`cat /vagrant/token/keys.txt | grep "Unseal Key 2:" | cut -c15-` # Needed keys to unseal Vault
    key2=`cat /vagrant/token/keys.txt | grep "Unseal Key 3:" | cut -c15-` #  
    # Copy the certificate from Vault in order to autorize consul agents to comunicate with Vault
    sshpass -p 'vagrant' scp -o StrictHostKeyChecking=no vagrant@192.168.56.71:"/etc/vault.d/vault.crt" /etc/consul.d/ssl/
    unseal_vault $VaultunSeal
    acquiring_certs_from_vault ${VAULT_TOKEN} ${NODE_TYPE} ${DC} ${DOMAIN}
    # Sealing Vault /// We doing this for security reason
    curl --cacert /etc/consul.d/ssl/vault.crt --header "X-Vault-Token: ${VAULT_TOKEN}" --request PUT $VaultSeal
    enabling_gossip_encryption $HOST

########################
# Adding consul config #
########################
sudo cat <<EOF > /etc/consul.d/tls.json
{
  "verify_outgoing": true,
  "verify_server_hostname": true,
  "verify_incoming_https": false,
  "verify_incoming_rpc": true,
  "ca_file": "/etc/consul.d/ssl/consul-agent-ca.pem",  
  "cert_file": "/etc/consul.d/ssl/consul-agent.pem",
  "key_file": "/etc/consul.d/ssl/consul-agent.key",
    "ports": {
    "http": -1,
    "https": 8501
    }
}
EOF

fi

sudo cat <<EOF > /etc/consul.d/config.json
{ 
  "datacenter": "${DC}",
  "ui": true,
  "client_addr": "0.0.0.0",
  "bind_addr": "0.0.0.0",
  "advertise_addr": "${IPs}",
  "enable_script_checks": true,
  "connect": [
    {
      "enabled": true
    }
  ],
  "ports": [
    {
      "grpc": 8502
    }
  ],
  "data_dir": "/var/lib/consul"${LAN}
}
EOF

if [[ $HOST =~ server ]]; then
sudo cat <<EOF > /etc/consul.d/server.json
{ 
  "server": true,
  "bootstrap_expect": ${SERVER_COUNT}${WAN}
}
EOF
fi

####################################
# Consul Server systemd Unit file  #
####################################
sudo cat <<EOF > /etc/systemd/system/consul.service
### BEGIN INIT INFO
# Provides:          consul
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Consul agent
# Description:       Consul service discovery framework
### END INIT INFO

[Unit]
Description=Consul server agent
Requires=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
PIDFile=/var/run/consul/consul.pid
PermissionsStartOnly=true
ExecStartPre=-/bin/mkdir -p /var/run/consul
ExecStartPre=/bin/chown -R consul:consul /var/run/consul
ExecStart=/usr/local/bin/consul agent \
    -config-dir=/etc/consul.d/ \
    -pid-file=/var/run/consul/consul.pid
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target

EOF

###################
# Starting Consul #
###################

chown -R consul:consul /etc/consul.d
sudo systemctl daemon-reload
sudo systemctl start consul

###########################
# Redirecting conslul log #
###########################
    if [ -d /vagrant ]; then
        mkdir -p /vagrant/consul_logs
        journalctl -f -u consul.service > /vagrant/consul_logs/${HOST}.log &
    else
        journalctl -f -u consul.service > /tmp/consul.log
    fi
echo consul started
set +x
sleep 5
        if [ "$TLS_ENABLE" = true ] ; then
        consul members -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -http-addr="https://127.0.0.1:8501"
        else
        consul members
        fi
