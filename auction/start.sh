#!/bin/sh

# v2
#docker run --restart=always --name auction5 -d -v ./data-v2:/app/data script3/auctioneer-bot:latest

# BLNT v3
docker run --restart=always --name auction6 -d -v ./data-v3:/app/data ghcr.io/ddombrowsky/auctioneer-bot:blnt-v3
