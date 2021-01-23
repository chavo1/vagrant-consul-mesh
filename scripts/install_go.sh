#!/usr/bin/env bash

# Install Golang
[ "${GOLANG_FILE}" ] || GOLANG_FILE="go1.15.2.linux-amd64.tar.gz"

sudo apt-get update

# install Golang
wget -q -P /tmp https://dl.google.com/go/${GOLANG_FILE} || {
    echo "error downloading Golang package"
    exit 1
}
sudo tar -C /usr/local -xzf /tmp/${GOLANG_FILE} || {
    echo "error extracting Golang package"
    exit 1
}

cat /etc/profile.d/golang_config.sh 2>/dev/null | grep 'export PATH=' || {
    echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile.d/golang_config.sh
    source /etc/profile.d/golang_config.sh
}

# setup GOPATH/bin for vagrant user
cat /home/vagrant/.profile 2>/dev/null | grep "PATH=\$PATH:$(go env GOPATH)/bin" || {
    echo "export PATH=\$PATH:$(go env GOPATH)/bin" | sudo tee -a /home/vagrant/.profile
}

# setup GOPATH for vagrant user
cat /home/vagrant/.profile 2>/dev/null | grep "export GOPATH=" || {
    echo "export GOPATH=/home/vagrant/go" | sudo tee -a /home/vagrant/.profile
}
