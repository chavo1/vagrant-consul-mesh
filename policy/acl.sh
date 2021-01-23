#!/usr/bin/env bash

TLS_ENABLE=${TLS_ENABLE}

# Install sshpass -if not installed
which sshpass &>/dev/null || {
    apt-get sshpass -y 
}
set -x
HOST=$(hostname)
# - Create the consul directory
mkdir -p /etc/consul.d/
mkdir -p acl
mkdir -p /vagrant/services_logs/
# - Enable ACLs on all the servers. 

###-------------------------------------------
if [[ $HOST == consul-dc1-server01 ]]; then
sudo cat <<EOF > /etc/consul.d/acl.json
{
  "datacenter": "dc1",
  "primary_datacenter": "dc1",
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "down_policy": "extend-cache",
    "enable_token_persistence": true
  }
}
EOF
systemctl restart consul
sleep 10
# - Create the initial bootstrap token. 

  if [[ "$TLS_ENABLE" = true ]] ; then
   export TLS='-ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem -client-key=/etc/consul.d/ssl/consul-agent.key -http-addr https://127.0.0.1:8501'
  else
   export TLS=''
  fi
consul acl bootstrap $TLS > /vagrant/policy/master-token.txt
export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’` # bootstrap token

## Agent Policy - Token
sudo cat <<EOF > acl/agent-policy.hcl
node_prefix "" {
  policy = "write"
}
service_prefix "" {
   policy = "read"
}
EOF
# - Create agent policy
    consul acl policy create $TLS \
      -name agent-policy \
      -rules @acl/agent-policy.hcl
    # - Create agent token
consul acl token create $TLS -description "Agent Token" -policy-name agent-policy > /vagrant/policy/agent-token.txt
## Replication Policy - Token
sudo cat <<EOF > acl/replication-policy.hcl
acl = "write"

operator = "write"

service_prefix "" {
  policy = "read"
  intentions = "read"
}
EOF
# - Create Replication policy
    consul acl policy create $TLS \
      -name replication-policy \
      -rules @acl/replication-policy.hcl
    # - Create Replication token
consul acl token create $TLS -description "Replication Token" -policy-name replication-policy > /vagrant/policy/replication-token.txt
sleep 2
# dashboard-policy.hcl
sudo cat <<EOF > acl/dashboard-policy.hcl
service "dashboard" {
  policy = "write"
}
EOF
# - Create dashboard-service policy
    consul acl policy create $TLS \
      -name dashboard-policy \
      -rules @acl/dashboard-policy.hcl
# - Create dashboard-service token
consul acl token create $TLS -description "Dashboard Token" -policy-name dashboard-policy > /vagrant/policy/dashboard-token.txt
sleep 2
# counting-policy.hcl
sudo cat <<EOF > acl/counting-policy.hcl
service "counting" {
  policy = "write"
}
EOF
# - Create counting-service policy
    consul acl policy create $TLS \
      -name counting-policy \
      -rules @acl/counting-policy.hcl
# - Create counting-service token
consul acl token create $TLS -description "Counting Token" -policy-name counting-policy > /vagrant/policy/counting-token.txt
# web-policy.hcl
sleep 2
sudo cat <<EOF > acl/web-policy.hcl
service "web" {
  policy = "write"
}
EOF
# - Create web-service policy
    consul acl policy create $TLS \
      -name web-policy \
      -rules @acl/web-policy.hcl
# - Create DNS token
consul acl token create $TLS -description "Web Token" -policy-name web-policy > /vagrant/policy/web-token.txt
# dns-policy.hcl
sleep 2
sudo cat <<EOF > acl/dns-policy.hcl
node_prefix "" {
  policy = "read"
}
service_prefix "" {
  policy = "read"
}
# only needed if using prepared queries
query_prefix "" {
  policy = "read"
}
EOF
# - Create DNS policy
    consul acl policy create $TLS \
      -name dns-policy \
      -rules @acl/dns-policy.hcl
# - Create DNS token
consul acl token create $TLS -description "DNS Token" -policy-name dns-policy > /vagrant/policy/dns-token.txt
# mesh-gateway-policy.hcl
sleep 2
sudo cat <<EOF > acl/mesh-gateway-policy.hcl
service_prefix "gateway" {
   policy = "write"
}
service_prefix "" {
   policy = "read"
}
node_prefix "" {
   policy = "read"
}
agent_prefix "" {
   policy = "read"
}
EOF
# - Create mesh-gateway policy
    consul acl policy create $TLS \
      -name mesh-gateway-policy \
      -rules @acl/mesh-gateway-policy.hcl
# - Create mesh-gateway tokens
consul acl token create $TLS -description "mesh-gateway primary datacenter token" -policy-name mesh-gateway-policy > /vagrant/policy/primery-mesh-gateway-token.txt
consul acl token create $TLS -description "mesh-gateway secondary datacenter token" -policy-name mesh-gateway-policy > /vagrant/policy/secondary-mesh-gateway-token.txt

fi

###--------------------------------------------

if [[ $HOST == consul-dc1-client01 ]]; then

  if [[ "$TLS_ENABLE" = true ]] ; then
    export TLS='-ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem -client-key=/etc/consul.d/ssl/consul-agent.key -http-addr https://127.0.0.1:8501'
  else
    export TLS=''
  fi
# - Apply the new token to the servers. // change the token in file
export AGENT_TOKEN=`cat /vagrant/policy/agent-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`

sudo cat <<EOF > /etc/consul.d/agent-acl.hcl
"acl" = {
  "default_policy" = "deny"

  "enable_token_persistence" = true

  "enabled" = true

  "tokens" = {
    "default" = "${AGENT_TOKEN}"
  }
}
EOF
systemctl restart consul
sleep 5
curl -L https://getenvoy.io/cli | sudo bash -s -- -b /usr/local/bin
getenvoy run standard:1.13.4 -- --version
sudo cp /root/.getenvoy/builds/standard/1.13.4/linux_glibc/bin/envoy /usr/local/bin/

export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`

# client1 dc1
sudo cat <<EOF > /etc/consul.d/dashboard.hcl
service {
  name = "dashboard"
  port = 9002

  connect {
    sidecar_service {
      proxy {
        upstreams = [
          {
            destination_name = "counting",
            datacenter = "dc2",
            local_bind_port  = 5000
          }
        ]
      }
    }
  }

  check {
    id       = "dashboard-check"
    http     = "http://localhost:9002/health"
    method   = "GET"
    interval = "1s"
    timeout  = "1s"
  }
}
EOF

consul services register $TLS /etc/consul.d/dashboard.hcl
sleep 2
#### Start the services and sidecar proxies #DC1 Client 1
sleep 2
consul intention create $TLS dashboard counting
sleep 2
consul catalog services $TLS
sleep 2
PORT=9002 COUNTING_SERVICE_URL="http://localhost:5000" /vagrant/services/dashboard-service_linux_amd64 &> /vagrant/services_logs/dashboard.log &
sleep 2
consul connect envoy $TLS -sidecar-for dashboard &> /vagrant/services_logs/sidecar_dashboard.log &

fi

###----------------------------------------------

if [[ $HOST == consul-dc1-client02 ]]; then

  if [[ "$TLS_ENABLE" = true ]] ; then
   export TLS='-ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem -client-key=/etc/consul.d/ssl/consul-agent.key -http-addr https://127.0.0.1:8501'
  else
   export TLS=''
  fi

# - Apply the new token to the servers. // change the token in file
export AGENT_TOKEN=`cat /vagrant/policy/agent-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’` # Agent token

sudo cat <<EOF > /etc/consul.d/agent-acl.hcl
"acl" = {
  "default_policy" = "deny"

  "enable_token_persistence" = true

  "enabled" = true

  "tokens" = {
    "default" = "${AGENT_TOKEN}"
  }
}
EOF
systemctl restart consul
sleep 5
curl -L https://getenvoy.io/cli | sudo bash -s -- -b /usr/local/bin
getenvoy run standard:1.13.4 -- --version
sudo cp /root/.getenvoy/builds/standard/1.13.4/linux_glibc/bin/envoy /usr/local/bin/

export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`
export PRIMARY_TOKEN=`cat /vagrant/policy/primery-mesh-gateway-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`

#DC1 Client 2
consul connect envoy $TLS -gateway=mesh -register \
                  -service "gateway-primary" \
                  -address "192.168.56.62:8443" \
                  -token=$PRIMARY_TOKEN &> /vagrant/services_logs/prymary_gateway.log &

# Configure sidecar proxies to use the mesh gateways
sudo cat <<EOF > proxy-defaults.hcl
Kind = "proxy-defaults",
Name = "global",
MeshGateway {
  mode = "local"
}
EOF
sleep 2
consul config write $TLS proxy-defaults.hcl

fi

###---------------------------------------

if [[ $HOST == consul-dc2-server01 ]]; then

  if [[ "$TLS_ENABLE" = true ]] ; then
   export TLS='-ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem -client-key=/etc/consul.d/ssl/consul-agent.key -http-addr https://127.0.0.1:8501'
  else
   export TLS=''
  fi
export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`
export REPLICATION_TOKEN=`cat /vagrant/policy/replication-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`

sudo cat <<EOF > /etc/consul.d/acl.json
{
  "datacenter": "dc2",
  "primary_datacenter": "dc1",
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "down_policy": "extend-cache",
    "enable_token_persistence": true,
    "enable_token_replication": true
  }
}
EOF
systemctl restart consul
sleep 5
consul acl set-agent-token $TLS replication $REPLICATION_TOKEN
sleep 5
fi

###-------------------------------------------

if [[ $HOST == consul-dc2-client01 ]]; then

  if [[ "$TLS_ENABLE" = true ]] ; then
    TLS='-ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem -client-key=/etc/consul.d/ssl/consul-agent.key -http-addr https://127.0.0.1:8501'
  else
    TLS=''
  fi
export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`

sudo cat <<EOF > /etc/consul.d/acl.json
{
  "datacenter": "dc2",
  "primary_datacenter": "dc1",
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "down_policy": "extend-cache",
    "enable_token_persistence": true,
    "enable_token_replication": true
  }
}
EOF
systemctl restart consul
sleep 5
curl -L https://getenvoy.io/cli | sudo bash -s -- -b /usr/local/bin
getenvoy run standard:1.13.4 -- --version
sudo cp /root/.getenvoy/builds/standard/1.13.4/linux_glibc/bin/envoy /usr/local/bin/
#client1 dc2
sudo cat <<EOF > /etc/consul.d/counting.hcl
service {
  name = "counting"
  id = "counting-1"
  port = 9003

  connect {
    sidecar_service {}
  }

  check {
    id       = "counting-check"
    http     = "http://localhost:9003/health"
    method   = "GET"
    interval = "1s"
    timeout  = "1s"
  }
}
EOF

consul services register $TLS /etc/consul.d/counting.hcl
sleep 2
consul catalog services $TLS
#### Start the services and sidecar proxies #DC2 Client 1
PORT=9003 /vagrant/services/counting-service_linux_amd64 &> /vagrant/services_logs/counting.log &
#### Start the built-in sidecar proxy for the counting service
sleep 2
consul connect envoy $TLS -sidecar-for counting-1 -admin-bind localhost:19001 &> /vagrant/services_logs/sidecar_counting.log &

fi

###---------------------------------------------------

if [[ $HOST == consul-dc2-client02 ]]; then

  if [[ "$TLS_ENABLE" = true ]] ; then
   export TLS='-ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem -client-key=/etc/consul.d/ssl/consul-agent.key -http-addr https://127.0.0.1:8501'
  else
   export TLS=''
  fi

sudo cat <<EOF > /etc/consul.d/acl.json
{
  "datacenter": "dc2",
  "primary_datacenter": "dc1",
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "down_policy": "extend-cache",
    "enable_token_persistence": true,
    "enable_token_replication": true
  }
}
EOF
systemctl restart consul
sleep 5
curl -L https://getenvoy.io/cli | sudo bash -s -- -b /usr/local/bin
getenvoy run standard:1.13.4 -- --version
sudo cp /root/.getenvoy/builds/standard/1.13.4/linux_glibc/bin/envoy /usr/local/bin/

export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`
export SECONDARY_TOKEN=`cat /vagrant/policy/secondary-mesh-gateway-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`

consul connect envoy $TLS -gateway=mesh -register \
                  -service "gateway-secondary" \
                  -address "192.168.57.62:8443" \
                  -token=$SECONDARY_TOKEN &> /vagrant/services_logs/secondary_gateway.log &

# Configure sidecar proxies to use the mesh gateways

sudo cat <<EOF > proxy-counting.hcl
Kind = "service-defaults"
Name = "counting-1"
MeshGateway {
   Mode = "local"
}
EOF
sleep 2
consul config write $TLS proxy-counting.hcl
fi




set +x


# TLS='-ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -client-cert=/etc/consul.d/ssl/consul-agent.pem -client-key=/etc/consul.d/ssl/consul-agent.key -http-addr https://127.0.0.1:8501'

# # anonymous-policy.hcl
# sudo cat <<EOF > acl/anonymous-policy.hcl
# acl = "write"
# agent_prefix "" {
# 	policy = "write"
# }
# event_prefix "" {
# 	policy = "write"
# }
# key_prefix "" {
# 	policy = "write"
# }
# keyring = "write"
# node_prefix "" {
# 	policy = "write"
# }
# operator = "write"
# query_prefix "" {
# 	policy = "write"
# }
# service_prefix "" {
# 	policy = "write"
# 	intentions = "write"
# }
# session_prefix "" {
# 	policy = "write"
# }
# EOF
# # - Create mesh-gateway policy
#     consul acl policy create $TLS \
#       -name anonymous-policy \
#       -rules @acl/anonymous-policy.hcl
# # - Create mesh-gateway tokens

# consul acl token update $TLS -id 00000000-0000-0000-0000-000000000002 --merge-policies -description "Anonymous Token - Update" -policy-name anonymous-policy


# curl \
#     --request PUT \
#     --data 'hello consul' \
#     --header "X-Consul-Token: bb520692-763e-bcd1-1d19-c630ec21c398" \
#     http://127.0.0.1:8500/v1/kv/foo

#     curl \
#         --header "X-Consul-Token: bb520692-763e-bcd1-1d19-c630ec21c398" \
#         http://127.0.0.1:8500/v1/kv/foo/?raw