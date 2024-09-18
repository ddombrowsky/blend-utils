import { Backstop, BackstopPoolUser, Pool, Network } from '@blend-capital/blend-sdk';

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
  //const oracle = await pool.loadOracle();

  const user = await pool.loadUser(userPub);

  //console.log(JSON.stringify(user, replacer, 2));
  console.log(`Balances for ${user.userId} ->`);

  console.log('Liabilities ->');
  // TODO doesn't work, needs to use estimates
  for (let x of user.positions.liabilities) {
    console.log(`${x[0]} : ${pb(x[1])}`);
  }
  console.log('Collateral ->');
  for (let x of user.positions.collateral) {
    console.log(`${x[0]} : ${pb(x[1])}`);
  }

}

let backstop: Backstop;

async function main(pubkeys: Array<string>) {
  /*backstop = await Backstop.load(
    network,
    backstopContract,
    poolContracts,
    true,
    Math.floor(Date.now() / 1000));*/

  for (let pubkey of pubkeys) {
    console.log(`\n== USER ${pubkey} ==`);

    for (let poolId of poolContracts) {
      const userBackstop = await BackstopPoolUser.load(
        network,
        backstopContract,
        poolId,
        pubkey);

      console.log(`POOL ${poolId}`);
      await display(pubkey, poolId);
      console.log('backstop:');
      //console.log(userBackstop.estimates.get(poolId).tokens);
      console.log(userBackstop);
    }
  }

}

if (process.argv.length < 3) {
  console.error("Usage: node index.js G.... [G....]");
}
let pubkeys = process.argv.slice(2);

main(pubkeys);
