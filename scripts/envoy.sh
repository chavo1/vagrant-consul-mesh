#!/usr/bin/env bash

set -x


if [[ $HOST == consul-dc1-client01 ]]; then
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

consul services register /etc/consul.d/dashboard.hcl
sleep 2
#### Start the services and sidecar proxies #DC1 Client 1
PORT=9002 COUNTING_SERVICE_URL="http://localhost:5000" /vagrant/services/dashboard-service_linux_amd64 &> /vagrant/services_logs/dashboard.log &
sleep 2
consul connect envoy -sidecar-for dashboard &> /vagrant/services_logs/sidecar_dashboard.log &

elif [[ $HOST == consul-dc2-client01 ]]; then
export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`
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

consul services register /etc/consul.d/counting.hcl
sleep 2
consul catalog services
sleep 2
consul intention create dashboard counting
sleep 2
#### Start the services and sidecar proxies #DC2 Client 1
PORT=9003 /vagrant/services/counting-service_linux_amd64 &> /vagrant/services_logs/counting.log &
#### Start the built-in sidecar proxy for the counting service
sleep 2
consul connect envoy -sidecar-for counting-1 -admin-bind localhost:19001 &> /vagrant/services_logs/sidecar_counting.log &

elif [[ $HOST == consul-dc1-client02 ]]; then
export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`
export PRIMARY_TOKEN=`cat /vagrant/policy/primery-mesh-gateway-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`

#DC1 Client 2
consul connect envoy -gateway=mesh -register \
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
consul config write proxy-defaults.hcl

#DC2 Client 2

elif [[ $HOST == consul-dc2-client02 ]]; then
export CONSUL_HTTP_TOKEN=`cat /vagrant/policy/master-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`
export SECONDARY_TOKEN=`cat /vagrant/policy/secondary-mesh-gateway-token.txt | grep "SecretID:" | cut -c15- | tr -d ‘[:space:]’`

consul connect envoy -gateway=mesh -register \
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
consul config write proxy-counting.hcl
fi
set +x

## ======
# sudo cat <<EOF > /etc/consul.d/socat.hcl
# Kind = "service-defaults"
# service {
#   name = "socat",
#   port = 8181,
#   token = "c315f9ad-6469-cc7c-d82e-7d90593e9623",
#   connect {
#     sidecar_service {}
#   }
# }
# EOF
# consul config write /etc/consul.d/socat.hcl

# sudo cat <<EOF > /etc/consul.d/web.hcl
# Kind = "service-defaults"
# service {
#   name = "web",
#   port = 8080,
#   token = "c315f9ad-6469-cc7c-d82e-7d90593e9623",
#   connect {
#     sidecar_service {
#       proxy {
#         upstreams = [
#           {
#             destination_name = "socat",
#             datacenter = "dc1",
#             local_bind_port = 8181
#           }
#         ]
#       }
#     }
#   }
# }
# EOF
# consul config write /etc/consul.d/web.hcl

