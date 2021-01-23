#!/usr/bin/env sh

i=0 # set counter to 0
while true  # infinite loop
do
    curl -o /vagrant/consul_logs/loop.log -s web.service.consul || curl -o /vagrant/consul_logs/loop.log -s web.query.consul & # silent curl request to site
    if [ $? -ne 0 ]
    then
        # curl didn't return 0 - failure
        echo $i
        break # terminate loop
    fi
    i=$(($i+1))  # increment counter
    echo -en "$i        \r"   # display # of requests each iteration
    sleep 1  # short pause between requests
done
