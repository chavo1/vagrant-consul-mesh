#!/usr/bin/env bash

set -x
export DEBIAN_FRONTEND=noninteractive
export HOST=$(hostname)
TLS_ENABLE=$2
SERVER_COUNT=$3
IP=$(hostname -I | cut -f2 -d' ')
dc=$1

if [[ $HOST == consul-$dc-server0$SERVER_COUNT ]]; then

echo "Consul is bootstraped. Registering Sidecar Service..."

#####################
# Download services #
#####################
sudo mkdir -p /vagrant/services

# check if counting service file exist.
CHECKFILE1="/vagrant/services/counting-service_linux_amd64"
CHECKFILE2="/vagrant/services/dashboard-service_linux_amd64"
if [ ! -f "$CHECKFILE1" ]; then
    pushd /vagrant/services
    wget https://github.com/hashicorp/demo-consul-101/releases/download/0.0.3/counting-service_linux_amd64.zip
    unzip ./counting-service_linux_amd64.zip
    popd
fi
# check if dashboard service file exist.
if [ ! -f "$CHECKFILE2" ]; then
    pushd /vagrant/services
    wget https://github.com/hashicorp/demo-consul-101/releases/download/0.0.3/dashboard-service_linux_amd64.zip
    unzip ./dashboard-service_linux_amd64.zip
    popd
fi

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

sudo cat <<EOF > /etc/consul.d/dashboard.hcl
service {
  name = "dashboard"
  port = 9002

  connect {
    sidecar_service {
      proxy {
        upstreams = [
          {
            destination_name = "counting"
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

else
  echo "Consul is not bootstraped. Exiting..."
  exit 0
fi


sudo mkdir -p /vagrant/services_logs/

if [[ $TLS_ENABLE == true ]]; 
then

  #### Register services
  consul services register -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -http-addr="https://127.0.0.1:8501" /etc/consul.d/counting.hcl
  consul services register -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -http-addr="https://127.0.0.1:8501" /etc/consul.d/dashboard.hcl
  consul catalog services -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -http-addr="https://127.0.0.1:8501"
  #### Create intention
  consul intention create -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -http-addr="https://127.0.0.1:8501" dashboard counting

  #### Start the services and sidecar proxies
  PORT=9002 COUNTING_SERVICE_URL="http://localhost:5000" /vagrant/services/dashboard-service_linux_amd64 $> /vagrant/services_logs/dashboard_$HOST.log &
  sleep 2
  PORT=9003 /vagrant/services/counting-service_linux_amd64 &> /vagrant/services_logs/counting_$HOST.log &
  sleep 2
  #### Start the built-in sidecar proxy for the counting service
  consul connect proxy -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -http-addr="https://127.0.0.1:8501" -sidecar-for counting-1 > counting-proxy.log &
  sleep 2
  consul connect proxy -ca-file=/etc/consul.d/ssl/consul-agent-ca.pem -http-addr="https://127.0.0.1:8501" -sidecar-for dashboard > dashboard-proxy.log &

elif [[ $TLS_ENABLE == false ]]; then
    #### Register services
    consul services register /etc/consul.d/counting.hcl
    consul services register /etc/consul.d/dashboard.hcl
    consul catalog services
    #### Create intention
    consul intention create dashboard counting

    #### Start the services and sidecar proxies
    PORT=9002 COUNTING_SERVICE_URL="http://localhost:5000" /vagrant/services/dashboard-service_linux_amd64 $> /vagrant/services_logs/dashboard_$HOST.log &
    sleep 2
    PORT=9003 /vagrant/services/counting-service_linux_amd64 &> /vagrant/services_logs/counting_$HOST.log &
    sleep 2
    #### Start the built-in sidecar proxy for the counting service
    consul connect proxy -sidecar-for counting-1 > counting-proxy.log &
    sleep 2
    consul connect proxy -sidecar-for dashboard > dashboard-proxy.log &
fi
set +x
echo "Count Dashboard http://$IP:9002"