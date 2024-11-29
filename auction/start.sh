#!/bin/sh

#docker run -v ./data:/app/data script3/auctioneer-bot:latest

# fixed
docker run --restart always --name auction1 -d -v ./data:/app/data script3/auctioneer-bot:latest

# ybx
docker run --restart always --name auction2 -d -v ./data-ybx:/app/data script3/auctioneer-bot:latest
