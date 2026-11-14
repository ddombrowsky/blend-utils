import {
  Backstop,
  BackstopPoolV1,
  BackstopPoolV2,
  BackstopPoolUser,
  BackstopPoolUserEst,
  BackstopPoolUserV3,
  BackstopPoolV3,
  PoolV1,
  PoolV2,
  PoolV3,
  Network,
} from '@blend-capital/blend-sdk';

const network: Network = {
  rpc: "https://soroban-rpc.creit.tech/",
  passphrase: "Public Global Stellar Network ; September 2015",
};

const assetLookup = {
  'CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA': 'XLM',
  'CDTKPWPLOURQA2SGTKTUQOWRCBZEORB4BWBOMJ3D3ZTQQSGE5F6JBQLV': 'EURC',
  'CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75': 'USDC',
  'CB226ZOEYXTBPD3QEGABTJYSKZVBP2PASEISLG3SBMTN5CE4QZUVZ3CE': 'USDGLO',
  'CBLV4ATSIWU67CFSQU2NVRKINQIKUZ2ODSZBUJTJ43VJVRSBTZYOPNUR': 'USTRY',
  'CAL6ER2TI6CTRAY6BFXWNWA7WTYXUXTQCHUBCIBU5O6KM3HJFG6Z6VXV': 'CETES',
  'CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK': 'AQUA',
  'CCCRWH6Q3FNP3I2I57BDLM5AFAT7O6OF6GKQOC6SSJNDAVRZ57SPHGU2': 'PYUSD',
  'CBCO65UOWXY2GR66GOCMCN6IU3Y45TXCPBY3FLUNL4AOUMOCKVIVV6JC': 'GBPx',
  'CDIKURWHYS4FFTR5KOQK6MBFZA2K3E26WGBQI6PXBYWZ4XIOPJHDFJKP': 'USDx',
  'CBN3NCJSMOQTC6SPEYK3A44NU4VS3IPKTARJLI3Y77OH27EWBY36TP7U': 'EURx',
  'CBZPEXQLJCGUYTAQRQ4FGCXUV5O4TZER5WSOMCGNDNIIO4EJ4FU5GQNZ': 'oUSD',
  'CBSJZEIO5C7KC2SF3MKSNXXJSW5G3VTNBX4ATMKUI3B2MR4JKM4R26YF': 'USDT0',
  'CBIJBDNZNF4X35BJ4FFZWCDBSCKOP5NB4PLG4SNENRMLAPYG4P5FM6VN': 'SolvBTC',
};

const poolContracts = [
  {'id':'CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D','ver':3},
  {'id':'CACSQWCMKG45TUHCQ3LXHOB7YEEJH4W376ZHQPXH2IZ3TE4NJHFZMCY7','ver':3},
];
// indexed by pool version
const backstopContract: Record<number, string> = {
  1: 'CAO3AGAMZVRMHITL36EJ2VZQWKYRPWMQAPDQD5YEOF3GIF7T44U4JAL3',
  2: 'CAQQR5SWBXKIGZKPBZDH3KM5GQ5GUTPKB7JAFCINLZBC5WXPJKRG3IM7',
  3: 'CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO',
};

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

// Format a fixed-point bigint exactly, using all `decimals` digits.
function fmt(x: bigint, decimals: number): string {
  const neg = x < 0n;
  const abs = neg ? -x : x;
  const base = 10n ** BigInt(decimals);
  const whole = abs / base;
  const frac = (abs % base).toString().padStart(decimals, '0');
  return `${neg ? '-' : ''}${whole}${decimals > 0 ? '.' + frac : ''}`;
}

async function display(userPub: string, poolId: string, version: number) {
  let pool;
  if (version == 1) {
    pool = await PoolV1.load(network, poolId);
  } else if (version == 2) {
    pool = await PoolV2.load(network, poolId);
  } else {
    pool = await PoolV3.load(network, poolId);
  }
  const pool_user = await pool.loadUser(userPub);

  console.log(`Balances for ${pool_user.userId} ->`);

  console.log('  Liabilities ->');
  for (let reserve of pool.reserves.values()) {
    let sym = getSymbol(reserve.assetId);
    let val = pool_user.getLiabilities(reserve);
    if (val > 0n) {
      console.log(`	${sym}:	-${fmt(val, reserve.config.decimals)}`);
    }
  }

  console.log('  Collateral ->');
  for (let reserve of pool.reserves.values()) {
    let sym = getSymbol(reserve.assetId);
    let val = pool_user.getCollateral(reserve);
    if (val > 0n) {
      console.log(`	${sym}:	${fmt(val, reserve.config.decimals)}`);
    }
  }
}

async function displayBackstop(
  userPub: string, poolId: string, version: number)
{
  if (version == 3) {
    await displayBackstopV3(userPub, poolId);
    return;
  }
  const tokens = await displayBackstopV1V2(userPub, poolId, version);
  console.log(`backstop:\t${tokens}`);
}

async function displayBackstopV3(userPub: string, poolId: string) {
  const backstopId = backstopContract[3];
  const backstop_pool = await BackstopPoolV3.load(network, backstopId, poolId);
  const user = await BackstopPoolUserV3.load(network, backstopId, poolId, userPub);

  for (const tier of backstop_pool.configuredTiers) {
    const tierPool = backstop_pool.tier(tier);
    const shares = user.balance(tier).shares;
    const queued = user.queuedShares(tier);
    if (shares == 0n && queued == 0n) continue;
    const tokens = tierPool.sharesToTokens(shares);
    const queuedTokens = tierPool.sharesToTokens(queued);
    // all backstop tier assets (BLNT LP tokens, USDC, XLM) use 7 decimals
    console.log(`backstop ${tier} (${tierPool.data.asset}):\t${fmt(tokens, 7)}` +
      (queued > 0n ? `\t(queued: ${fmt(queuedTokens, 7)})` : ''));
  }
}

async function displayBackstopV1V2(
  userPub: string, poolId: string, version: number)
{
  const backstopId = backstopContract[version];
  const backstop = await Backstop.load(network, backstopId);
  const backstop_pool = version == 1
    ? await BackstopPoolV1.load(network, backstopId, poolId)
    : await BackstopPoolV2.load(network, backstopId, poolId);
  const userBackstop = await BackstopPoolUser.load(
    network, backstopId, poolId, userPub);
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
