#!/usr/bin/env bash

ENVCONSUL_VERSION=${ENVCONSUL_VERSION}

sudo mkdir -p /vagrant/pkg

which envconsul || {
    # envconsul file exist.
    CHECKFILE="/vagrant/pkg/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip"
    if [ ! -f "$CHECKFILE" ]; then
        pushd /vagrant/pkg
        wget https://releases.hashicorp.com/envconsul/${ENVCONSUL_VERSION}/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip
        popd
 
    fi
    
    pushd /usr/local/bin/
    unzip /vagrant/pkg/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip
    sudo chmod +x envconsul
    popd
}