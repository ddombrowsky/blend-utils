
const util = require('node:util');
const Stellar = require('@stellar/stellar-sdk');

const privKey = process.env.SECRET_KEY;

if (typeof privKey === 'undefined') {
  console.error('no secret key');
  process.exit(1);
}

if (process.argv.length < 6) {
  console.error('usage: sell_issue sell_code buy_issue buy_code sell_amt price');
  console.error('       (sell_amt in sell, price in buy)');
  process.exit(1);
}

const sell_issue = process.argv[2];
const sell_code = process.argv[3];
const buy_issue = process.argv[4];
const buy_code = process.argv[5];
const sell_amt = parseFloat(process.argv[6]);
const price = parseFloat(process.argv[7]);

async function go() {
  const server = new Stellar.Horizon.Server('https://horizon.stellar.org');
  let seckey = Stellar.Keypair.fromSecret(privKey);

  let sell_asset = new Stellar.Asset(sell_code, sell_issue);
  let buy_asset = new Stellar.Asset(buy_code, buy_issue);
  let account = await server.loadAccount(seckey.publicKey());
  let amount_s = sell_amt.toString();
  let price_s = price.toString();

  let builder = new Stellar.TransactionBuilder(account, {
    fee: '100000',
    networkPassphrase: Stellar.Networks.PUBLIC
  }).addOperation(Stellar.Operation.manageSellOffer({
    selling: sell_asset,
    buying: buy_asset,
    amount: amount_s,
    price: price_s,
  }));

  let tx = builder
    .setTimeout(180)
    .build();

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
    console.log('order placed successfully');
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
