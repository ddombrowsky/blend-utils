#!/bin/sh

# https://github.com/BLNT-Protocol/blnt-contracts-v3/blob/main/pool/src/errors.rs
# error 1200 = bad request (wrong user / percent != 100)
# error 1227 = invalid interest auction (v3 lots have max of 4 assets)
# error 1228 = no interest auction capacity (not enough interest accrued yet)

LOG=auction.log

# BLNT v3 fixed
echo BLNT v3 fixed
stellar contract invoke \
    --id CACSQWCMKG45TUHCQ3LXHOB7YEEJH4W376ZHQPXH2IZ3TE4NJHFZMCY7 \
    --source-account xbull \
    --network mainnet --fee 10000000 -- \
    new_auction \
      --percent 100 \
      --lot '["CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA","CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75","CDTKPWPLOURQA2SGTKTUQOWRCBZEORB4BWBOMJ3D3ZTQQSGE5F6JBQLV"]' \
      --user 'CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO' \
      --auction_type 2 \
      --bid '[]' > \
    $LOG 2>&1
    grep Error $LOG || exit
