#!/bin/sh

#docker run -v ./data:/app/data script3/auctioneer-bot:latest
docker run --restart always --name auction1 -d -v ./data:/app/data script3/auctioneer-bot:latest
