#!/bin/sh

docker run --restart always --name soroban1 -p 8001:8001 -p 8000:8000 \
    --log-driver json-file --log-opt max-size=100m --log-opt max-file=2 \
    -v ./core:/config stellar/stellar-rpc \
    --config-path /config/coreconfig.toml \
    -h soroban1.local


#docker run -p 8001:8001 -p 8000:8000 \
#-v ./core:/config stellar/stellar-rpc \
#--captive-core-config-path="/config/testnet.toml" \
#--captive-core-storage-path="/var/lib/stellar/captive-core" \
#--stellar-core-binary-path="/usr/bin/stellar-core" \
#--db-path="/var/lib/stellar/soroban-rpc-db.sqlite" \
#--stellar-captive-core-http-port=11626 \
#--friendbot-url="https://friendbot-testnet.stellar.org/" \
#--network-passphrase="Test SDF Network ; September 2015" \
#--history-archive-urls="https://history.stellar.org/prd/core-testnet/core_testnet_001" \
#--admin-endpoint="0.0.0.0:8001" \
#--endpoint="0.0.0.0:8000"
