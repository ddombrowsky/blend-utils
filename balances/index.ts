import { Backstop, BackstopUser, Pool, Network } from '@blend-capital/blend-sdk';

const network: Network = {
  rpc: "https://soroban-rpc.creit.tech/",
  passphrase: "Public Global Stellar Network ; September 2015",
};

const poolContract = 'CDVQVKOY2YSXS2IC7KN6MNASSHPAO7UN2UR2ON4OI2SKMFJNVAMDX6DP';
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

async function display(userPub: string) {
  const user = await pool.loadUser(
    network,
    userPub);

  //console.log(JSON.stringify(user, replacer, 2));
  console.log(`\nBalances for ${user.user} ->`);

  for (let x of user.positionEstimates.liabilities) {
    console.log(x);
  }
  for (let x of user.positionEstimates.collateral) {
    console.log(x);
  }

  console.log('backstop:');
  const userBackstop = await BackstopUser.load(
    network,
    userPub,
    backstop);

  //console.log(JSON.stringify(userBackstop, replacer, 2));
  console.log(userBackstop.estimates.get(poolContract).tokens);
}

let pool: Pool;
let backstop: Backstop;

async function main(pubkeys: Array<string>) {
  pool = await Pool.load(
    network,
    poolContract,
    Math.floor(Date.now() / 1000));

  backstop = await Backstop.load(
    network,
    backstopContract,
    [poolContract],
    true,
    Math.floor(Date.now() / 1000));

  // console.log(JSON.stringify(pool, replacer, 2));

  for (let pubkey of pubkeys) {
    await display(pubkey);
  }
}

if (process.argv.length < 3) {
  console.error("Usage: node index.js G.... [G....]");
}
let pubkeys = process.argv.slice(2);

main(pubkeys);
