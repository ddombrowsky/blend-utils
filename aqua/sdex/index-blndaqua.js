const util = require('node:util');
const Stellar = require('@stellar/stellar-sdk');

const privKey = process.env.SECRET_KEY;

if (typeof privKey === 'undefined') {
  console.error('no secret key');
  process.exit(1);
}

const sourceAmount = process.argv[2];
const destAmount = process.argv[3];
let inverse = false;
if (process.argv.length > 3 && process.argv[4] === 'inverse') {
  inverse = true;
}

//console.log(sourceAmount);
//console.log(destAmount);

async function go() {
  const server = new Stellar.Horizon.Server('https://horizon.stellar.org');
  let seckey = Stellar.Keypair.fromSecret(privKey);
  let aqua = new Stellar.Asset(
    'AQUA',
    'GBNZILSTVQZ4R7IKQDGHYGY2QXL5QOFJYQMXPKWRRM5PAV7Y4M67AQUA'
  );
  let blnd = new Stellar.Asset(
    'BLND',
    'GDJEHTBE6ZHUXSWFI642DCGLUOECLHPF3KSXHPXTSTJ7E3JF6MQ5EZYY'
  );

  let account = await server.loadAccount(seckey.publicKey());
  //console.log(account.accountId());

  let fromAsset = aqua;
  let toAsset = blnd;

  if (inverse) {
    fromAsset = blnd;
    toAsset = aqua;
  }

  let paymentPath = await server.strictSendPaths(
    fromAsset,
    sourceAmount,
    [toAsset]
  ).call();
  //console.log(util.inspect(paymentPath));

  if (paymentPath.records.length < 1) {
    console.log('ERROR: no path');
    process.exit(1);
  }
  let destSendAmt = parseFloat(paymentPath.records[0].destination_amount);
  if (destSendAmt < parseFloat(destAmount)) {
    console.log(`ERROR: out of range: ${destSendAmt} < ${destAmount}`);
    process.exit(1);
  }

  let paymentPathTx = paymentPath.records[0].path.map(x => {
    if (x.asset_type == 'native') {
      return Stellar.Asset.native();
    }

    return new Stellar.Asset(x.asset_code, x.asset_issuer);
  });
  //console.log(util.inspect(paymentPathTx));

  let builder = new Stellar.TransactionBuilder(account, {
    fee: '100000', // stroops
    networkPassphrase: Stellar.Networks.PUBLIC
  }).addOperation(Stellar.Operation.pathPaymentStrictSend({
    sendAsset: fromAsset,
    sendAmount: sourceAmount,
    destination: seckey.publicKey(),
    destAsset: toAsset,
    destMin: destAmount,
    path: paymentPathTx
  }));

  let tx = builder
    .setTimeout(180)
    .build();

  //console.log(tx.toXDR());

  tx.sign(seckey);
  try {
    let response = await server.submitTransaction(tx);
    if (response.successful != true ) {
      console.log(util.inspect(response));
    }
    let txResult = Stellar.xdr.TransactionResult.fromXDR(
      response.result_xdr,
      'base64'
    );
    //console.log(util.inspect(txResult, false, 10));
    //console.log(txResult.result());
    //console.log(Object.getOwnPropertyNames(txResult.result()));
    //console.log(txResult.result()._value[0]);
    let amt = parseInt(txResult.result()._value[0]._value._value._value
      ._attributes.last
      ._attributes.amount.toString());

    console.log(amt/10000000);
  } catch (e) {
    if (typeof e.response !== 'undefined') {
      console.log(e.response.status);
      console.log(util.inspect(e.response.data, true, 10));
    } else {
      console.log(e);
    }
    process.exit(1);
  }

}


go();
