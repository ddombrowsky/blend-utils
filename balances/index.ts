import {
  Backstop,
  BackstopPoolV1,
  BackstopPoolV2,
  BackstopPoolUser,
  BackstopPoolUserEst,
  PoolV1,
  PoolV2,
  Network,
  PositionsEstimate
} from '@blend-capital/blend-sdk';

const network: Network = {
  rpc: "https://soroban-rpc.creit.tech/",
  passphrase: "Public Global Stellar Network ; September 2015",
};

const assetLookup = {
  'CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA': 'XLM',
  'CDTKPWPLOURQA2SGTKTUQOWRCBZEORB4BWBOMJ3D3ZTQQSGE5F6JBQLV': 'ERUC',
  'CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75': 'USDC',
  'CB226ZOEYXTBPD3QEGABTJYSKZVBP2PASEISLG3SBMTN5CE4QZUVZ3CE': 'USDGLO',
  'CBLV4ATSIWU67CFSQU2NVRKINQIKUZ2ODSZBUJTJ43VJVRSBTZYOPNUR': 'USTRY',
  'CAL6ER2TI6CTRAY6BFXWNWA7WTYXUXTQCHUBCIBU5O6KM3HJFG6Z6VXV': 'CETES',
  'CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK': 'AQUA',
};

const poolContracts = [
  {'id':'CDVQVKOY2YSXS2IC7KN6MNASSHPAO7UN2UR2ON4OI2SKMFJNVAMDX6DP','ver':0},
  {'id':'CBP7NO6F7FRDHSOFQBT2L2UWYIZ2PU76JKVRYAQTG3KZSQLYAOKIF2WB','ver':0},
  {'id':'CAJJZSGMMM3PD7N33TAPHGBUGTB43OC73HVIK2L2G6BNGGGYOSSYBXBD','ver':1},
  {'id':'CCCCIQSDILITHMM7PBSLVDT5MISSY7R26MNZXCX4H7J5JQ5FPIYOGYFS','ver':1},
];
const backstopContract = [
  'CAO3AGAMZVRMHITL36EJ2VZQWKYRPWMQAPDQD5YEOF3GIF7T44U4JAL3',
  'CAQQR5SWBXKIGZKPBZDH3KM5GQ5GUTPKB7JAFCINLZBC5WXPJKRG3IM7'
];

function getSymbol(assetId: string) : string {
  let sym = assetLookup[assetId];
  return sym ? sym : assetId;
}

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

async function display(userPub: string, poolId: string, version: number) {
  let pool;
  if (version==0) {
    pool = await PoolV1.load(
      network,
      poolId);
  } else {
    pool = await PoolV2.load(
      network,
      poolId);
  }
  const pool_oracle = await pool.loadOracle();
  const pool_user = await pool.loadUser(userPub);
  const user_est = PositionsEstimate.build(
    pool, pool_oracle, pool_user.positions
  );

  //console.log(JSON.stringify(user, replacer, 2));
  console.log(`Balances for ${pool_user.userId} ->`);

  console.log('  Liabilities ->');
  for (let reserve of pool.reserves.values()) {
    let sym = getSymbol(reserve.assetId);
    let val = pool_user.getLiabilitiesFloat(reserve);
    if (val > 0) {
      console.log(`\t${sym}:\t-${val}`);
    }
  }

  console.log('  Collateral ->');
  for (let reserve of pool.reserves.values()) {
    let sym = getSymbol(reserve.assetId);
    let val = pool_user.getCollateralFloat(reserve);
    if (val > 0) {
      console.log(`\t${sym}:\t${val}`);
    }
  }

}

async function displayBackstop(
  userPub: string, poolId: string, version: number)
{
  let tokens = 0;
  if (version==0) {
    tokens = await displayBackstopV1(userPub, poolId);
  } else {
    tokens = await displayBackstopV2(userPub, poolId);
  }
  console.log(`backstop:\t${tokens}`);
}

async function displayBackstopV1(
  userPub: string, poolId: string)
{
  const backstop = await Backstop.load(
    network,
    backstopContract[0]
  );
  const backstop_pool = await BackstopPoolV1.load(
    network, backstopContract[0], poolId
  );
  const userBackstop = await BackstopPoolUser.load(
    network,
    backstopContract[0],
    poolId,
    userPub);
  const backstop_pool_user_est = BackstopPoolUserEst.build(
    backstop, backstop_pool, userBackstop
  );

  return backstop_pool_user_est.tokens;
}

async function displayBackstopV2(
  userPub: string, poolId: string)
{
  const backstop = await Backstop.load(
    network,
    backstopContract[1]
  );
  const backstop_pool = await BackstopPoolV2.load(
    network, backstopContract[1], poolId
  );
  const userBackstop = await BackstopPoolUser.load(
    network,
    backstopContract[1],
    poolId,
    userPub);
  const backstop_pool_user_est = BackstopPoolUserEst.build(
    backstop, backstop_pool, userBackstop
  );

  return backstop_pool_user_est.tokens;
}

async function main(pubkeys: Array<string>) {

  for (let pubkey of pubkeys) {
    console.log(`\n== USER ${pubkey} ==`);

    for (let poolData of poolContracts) {
      let poolId = poolData.id;
      let version = poolData.ver;
      console.log(`POOL ${poolId}`);

      await display(pubkey, poolId, version);
      await displayBackstop(pubkey, poolId, version);
    }
  }

}

if (process.argv.length < 3) {
  console.error("Usage: node index.js G.... [G....]");
}
let pubkeys = process.argv.slice(2);

main(pubkeys);
