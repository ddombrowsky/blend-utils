#!/bin/sh


curl -s --location 'http://localhost:8000' \
    --header 'Content-Type: application/json' \
    --data '{ "jsonrpc":"2.0", "id":2, "method":"getHealth" }' |
    jq .
