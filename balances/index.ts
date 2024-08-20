import { Backstop, BackstopUser, Pool, Network } from '@blend-capital/blend-sdk';

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

async function display(userPub: string, poolId: string) {
  const pool = await Pool.load(
    network,
    poolId,
    Math.floor(Date.now() / 1000));

  const user = await pool.loadUser(
    network,
    userPub);

  //console.log(JSON.stringify(user, replacer, 2));
  console.log(`Balances for ${user.user} ->`);

  console.log('Liabilities ->');
  for (let x of user.positionEstimates.liabilities) {
    console.log(x);
  }
  console.log('Collateral ->');
  for (let x of user.positionEstimates.collateral) {
    console.log(x);
  }

}

let backstop: Backstop;

async function main(pubkeys: Array<string>) {
  backstop = await Backstop.load(
    network,
    backstopContract,
    poolContracts,
    true,
    Math.floor(Date.now() / 1000));

  for (let pubkey of pubkeys) {
    console.log(`\n== USER ${pubkey} ==`);
    const userBackstop = await BackstopUser.load(
      network,
      pubkey,
      backstop);

    for (let poolId of poolContracts) {
      console.log(`POOL ${poolId}`);
      await display(pubkey, poolId);
      console.log('backstop:');
      console.log(userBackstop.estimates.get(poolId).tokens);
    }
  }

}

if (process.argv.length < 3) {
  console.error("Usage: node index.js G.... [G....]");
}
let pubkeys = process.argv.slice(2);

main(pubkeys);
