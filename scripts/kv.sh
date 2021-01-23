#!/usr/bin/env bash

TLS_ENABLE=${TLS_ENABLE}
HOST=$(hostname)

if [ "$TLS_ENABLE" = true ] ; then
    HTTP=https://127.0.0.1:8501/v1/kv/$HOST/nginx
    f='-k'
else
    HTTP=http://127.0.0.1:8500/v1/kv/$HOST/nginx
    f=''
fi

# API add value
curl -s "$f" \
    --request PUT \
    --data '<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx from '$HOST'!</h1>
</body>
</html>' \
    "$HTTP"
   