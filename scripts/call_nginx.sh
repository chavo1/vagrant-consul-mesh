#!/usr/bin/env bash

TLS_ENABLE=${TLS_ENABLE}
HOST=$(hostname)

if [ "$TLS_ENABLE" = true ] ; then
    envconsul -consul-ssl-ca-path=/etc/consul.d/ssl/consul-agent-ca.pem -consul-addr=https://127.0.0.1:8501 -prefix $HOST /vagrant/scripts/nginx.sh
else
    envconsul -prefix $HOST /vagrant/scripts/nginx.sh
fi