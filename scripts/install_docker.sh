#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

## Install Docker

sudo apt-get update 

sudo apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

## Install Docker

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io -y

## Install docker-compose

sudo curl -L https://github.com/docker/compose/releases/download/1.21.2/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

#### Consu Task Traffic Splitting for Service Deployments
# https://learn.hashicorp.com/tutorials/consul/service-mesh-traffic-splitting

# git clone https://github.com/hashicorp/consul-demo-traffic-splitting.git
# cd consul-demo-traffic-splitting
# docker-compose up