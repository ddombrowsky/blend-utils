#!/bin/sh

# Step 5: open the YieldBlent pool (status 6 setup -> 0 admin active).
# After this, reserve changes need queue_set_reserve + a one-week wait.

P=CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D

# 1. simulate
stellar contract invoke --source-account xbull --network mainnet --inclusion-fee 10000000 --send no --id $P -- set_status --pool_status 0

# 2. send
stellar contract invoke --source-account xbull --network mainnet --inclusion-fee 10000000 --id $P -- set_status --pool_status 0

# 3. check: expect "status":0
stellar contract invoke --source-account xbull --network mainnet --send no --id $P -- get_config
