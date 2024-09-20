import {
  Backstop,
  BackstopPool,
  BackstopPoolUser,
  BackstopPoolUserEst,
  Pool,
  Network,
  PositionsEstimate
} from '@blend-capital/blend-sdk';

const network: Network = {
  rpc: "https://soroban-rpc.creit.tech/",
  passphrase: "Public Global Stellar Network ; September 2015",
};

const poolContracts = [
  'CDVQVKOY2YSXS2IC7KN6MNASSHPAO7UN2UR2ON4OI2SKMFJNVAMDX6DP',
  'CBP7NO6F7FRDHSOFQBT2L2UWYIZ2PU76JKVRYAQTG3KZSQLYAOKIF2WB'
];
const backstopContract = 'CAO3AGAMZVRMHITL36EJ2VZQWKYRPWMQAPDQD5YEOF3GIF7T44U4JAL3';

const replacer = (key: any, value: any) => {
  if (value instanceof Map) {
    return {
      dataType: 'Map',
      value: Array.from(value.entries()),
    };
  } else if (typeof value == 'bigint') {
    return {
      dataType: 'BigInt',
      value: value.toString(),
    };
  } else {
    return value;
  }
};

function pb(x: BigInt): number {
    return parseInt(x.toString()) / 10**7;
}

async function display(userPub: string, poolId: string) {
  const pool = await Pool.load(
    network,
    poolId);
  const pool_oracle = await pool.loadOracle();
  const pool_user = await pool.loadUser(userPub);
  const user_est = PositionsEstimate.build(
    pool, pool_oracle, pool_user.positions
  );

  //console.log(JSON.stringify(user, replacer, 2));
  console.log(`Balances for ${pool_user.userId} ->`);

  console.log('  Liabilities ->');
  for (let reserve of pool.reserves.values()) {
    let sym = reserve.tokenMetadata.symbol;
    let val = pool_user.getLiabilitiesFloat(reserve);
    if (val > 0) {
      console.log(`\t${sym}:\t-${val}`);
    }
  }

  console.log('  Collateral ->');
  for (let reserve of pool.reserves.values()) {
    let sym = reserve.tokenMetadata.symbol;
    let val = pool_user.getCollateralFloat(reserve);
    if (val > 0) {
      console.log(`\t${sym}:\t${val}`);
    }
  }

}

let backstop: Backstop;

async function main(pubkeys: Array<string>) {
  const backstop = await Backstop.load(network, backstopContract);

  for (let pubkey of pubkeys) {
    console.log(`\n== USER ${pubkey} ==`);

    for (let poolId of poolContracts) {
      const backstop_pool = await BackstopPool.load(
        network, backstopContract, poolId
      );
      const userBackstop = await BackstopPoolUser.load(
        network,
        backstopContract,
        poolId,
        pubkey);
      const backstop_pool_user_est = BackstopPoolUserEst.build(
        backstop, backstop_pool, userBackstop
      );

      console.log(`POOL ${poolId}`);
      await display(pubkey, poolId);
      console.log('backstop:');
      console.log(backstop_pool_user_est.tokens);
    }
  }

}

if (process.argv.length < 3) {
  console.error("Usage: node index.js G.... [G....]");
}
let pubkeys = process.argv.slice(2);

main(pubkeys);
