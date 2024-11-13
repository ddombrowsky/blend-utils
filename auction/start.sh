#!/bin/sh

docker run --restart always -d -v ./data:/app/data script3/auctioneer-bot:latest
