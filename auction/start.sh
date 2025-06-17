#!/bin/sh

#docker run -v ./data:/app/data script3/auctioneer-bot:latest

# fixed
docker run --restart always --name auction1 -d -v ./data:/app/data script3/auctioneer-bot:v1.0.0-beta

# ybx
docker run --restart always --name auction2 -d -v ./data-ybx:/app/data script3/auctioneer-bot:v1.0.0-beta

# fxdao
docker run --restart always --name auction3 -d -v ./data-fxdao:/app/data script3/auctioneer-bot:v1.0.0-beta

# reflector
docker run --restart always --name auction4 -d -v ./data-refl:/app/data script3/auctioneer-bot:v1.0.0-beta

# v2
docker run --restart always --name auction5 -d -v ./data-v2:/app/data script3/auctioneer-bot:latest
