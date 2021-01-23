#!/usr/bin/env bash

ENVCONSUL_VERSION=${CONSUL_TEMPLATE_VERSION}

sudo mkdir -p /vagrant/pkg

which envconsul || {
    # consul-template file exist.
    CHECKFILE="/vagrant/pkg/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip"
    if [ ! -f "$CHECKFILE" ]; then
        pushd /vagrant/pkg
        wget https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip
        popd
 
    fi
    
    pushd /usr/local/bin/
    unzip /vagrant/pkg/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip
    sudo chmod +x consul-template
    popd
}
