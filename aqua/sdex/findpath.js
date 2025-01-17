// https://docs.aqua.network/developers/code-examples/executing-swaps
const StellarSdk = require('@stellar/stellar-sdk');
const {
    xdr,
    Address,
    Asset,
    StrKey,
    XdrLargeInt,
    Networks,
    TransactionBuilder,
    rpc,
    BASE_FEE,
    TimeoutInfinite,
    Keypair,
    Horizon,
} = StellarSdk;

// Step 1: Specify your secret key, input token, output token and input token amount

const userSecretKey = process.env.SECRET_KEY;

const tokenIn = process.argv[2];
const tokenOut = process.argv[3];
const amount = parseInt(process.argv[4]);
const minOut = parseInt(process.argv[5]);

// Common constants
const horizonServerUrl = "https://horizon.stellar.org";
const sorobanServerUrl = 'https://mainnet.sorobanrpc.com';
const baseApi = 'https://amm-api.aqua.network/api/external/v1';
const routerContractId = "CBQDHNBFBZYE4MKPWBSJOPIYLW4SFSXAXUTSXJN76GNKYVYPCKWC6QUK"

function u128ToInt(value) {
    /**
     * Converts UInt128Parts from Stellar's XDR to a JavaScript number.
     *
     * @param {Object} value - UInt128Parts object from Stellar SDK, with `hi` and `lo` properties.
     * @returns {number|null} Corresponding JavaScript number, or null if the number is too large.
     */
    const result = (BigInt(value.hi()._value) << 64n) + BigInt(value.lo()._value);

    // Check if the result is within the safe integer range for JavaScript numbers
    if (result <= BigInt(Number.MAX_SAFE_INTEGER)) {
        return Number(result);
    } else {
        console.warn("Value exceeds JavaScript's safe integer range");
        return null;
    }
}

// Step 2: Call Find Path API to calculate swap chain and XDR

async function findSwapPath() {
    const headers = { 'Content-Type': 'application/json' };
    const body = JSON.stringify({
        token_in_address: tokenIn,
        token_out_address: tokenOut,
        amount: amount.toString(),
    });

    const estimateResponse = await fetch(`${baseApi}/find-path/`, { method: 'POST', body, headers });
    //console.log(await estimateResponse.text());
    //console.log(`${baseApi}/find-path`);
    const estimateResult = await estimateResponse.json();

    //console.log(estimateResult);
    // {
    //   success: true,
    //   swap_chain_xdr: 'AAAAEAAAAAE...SEu1QKQU3Ycwk9FM5LjU5ggGwgl5w==',
    //   pools: [ 'CDE57N6XTUPBKYYDGQMXX7E7SLNOLFY3JEQB4MULSMR2AKTSAENGX2HC' ],
    //   tokens: [
    //     'native',
    //     'AQUA:GBNZILSTVQZ4R7IKQDGHYGY2QXL5QOFJYQMXPKWRRM5PAV7Y4M67AQUA'
    //   ],
    //   amount: 1724745895
    // }

    if (!estimateResult.success) {
        throw new Error('Estimate failed');
    }

    return estimateResult;
}

// Step 3: generate smart contact call

async function executeSwap(estimateResult) {
    if (estimateResult.amount < minOut) {
      throw new Error(`below minimum ${estimateResult.amount} < ${minOut}`);
    }

    const keypair = Keypair.fromSecret(userSecretKey);

    const server = new rpc.Server(sorobanServerUrl);
    const horizonServer = new Horizon.Server(horizonServerUrl);

    // No need to generate swapsChain manually, use value received from find-path api
    const swapsChain = xdr.ScVal.fromXDR(estimateResult.swap_chain_xdr, 'base64');
    const tokenInScVal = Address.contract(StrKey.decodeContract(tokenIn)).toScVal()
    const amountU128 = new XdrLargeInt('u128', amount.toFixed()).toU128();
    const amountWithSlippage = estimateResult.amount * 0.99; // slippage 1%
    const amountWithSlippageU128 = new XdrLargeInt('u128', amountWithSlippage.toFixed()).toU128();

    const account = await server.getAccount(keypair.publicKey());
    const tx = new TransactionBuilder(account, {
        fee: BASE_FEE,
        networkPassphrase: Networks.PUBLIC,
    })
        .addOperation(
            new StellarSdk.Contract(routerContractId).call(
                "swap_chained",
                xdr.ScVal.scvAddress(Address.fromString(keypair.publicKey()).toScAddress()),
                swapsChain,
                tokenInScVal,
                amountU128,
                amountWithSlippageU128
            )
        )
        .setTimeout(TimeoutInfinite)
        .build();

    const preparedTx = await server.prepareTransaction(tx);

    preparedTx.sign(keypair);

    const result = await horizonServer.submitTransaction(preparedTx);

    let retry=4;
    let returnValue;
    while(retry-->0) {
      // wait a for the tx to make it to soroban (grrrrrrr)
      await new Promise(resolve => setTimeout(resolve, 1000));

      const resultTx = await server.getTransaction(result.id);
      const meta = resultTx.resultMetaXdr;
      if (typeof(meta) !== 'undefined') {
        returnValue = meta.v3().sorobanMeta().returnValue();
        retry = -99;
      }
    }

    if (retry==0) {
      throw new Error('swap failed');
    }

    const swapResult = u128ToInt(returnValue.value());

    //console.log('Swap successful!');
    //console.log(`Swapped: ${amount / 1e7} => ${swapResult / 1e7}`);
    console.log(swapResult);
}

// Entry point
findSwapPath().then(estimated => executeSwap(estimated))

