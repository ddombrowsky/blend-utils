//! Offline reproduction of a YieldBlent reward claim after a Comet swap.
use kanatoko::soroban_sdk::{xdr, Address, Env, IntoVal, Symbol, TryFromVal, Val};
use kanatoko::{
    AuthMode, CaptureBuilder, CapturedFixture, ExecutionMode, InvokeOutcome, InvokeRequest,
    Receipt, StrictFork,
};

const NETWORK: &str = "Public Global Stellar Network ; September 2015";
const BACKSTOP: &str = "CAHCUKBPTW5DR5RNXOHCTJD5U76A6EEZXYZAQFRQEEQRXQ3CRUZ6Z3MO";
const POOL: &str = "CAUTPSQDAJEUV5XEU3EXFVYRGDJLEJGVTFJCFZCSPTDCREAMZ573VF4D";
const COMET: &str = "CA5HX3D47PQZWC2E7VWXCKH4534P2NOJEOIXAWU47MI4QV2FQUYY3FLC";
const BLNT: &str = "CCBNWP5L7ZSXA3DBWCMFAVKFVRW3ZHWO7B5J557W42O64DDZNPJP7VDS";
const XLM: &str = "CAS3J7GYLGXMF6TDJBBYYSE3HQ6BBSMLNUQ34T6TZMYMW2EVH34XOWMA";
const EMITTER: &str = "CDSO6FQSBJ3U3AJHBNNLHHKSMKTTDDN3GLGF3KZTMXBFV7SVB43ZJERT";
const COMET_USDC: &str = "CDQMIKIHKA5UY3FQJ2UDTLNX3GOPD3GPNZWSPTOBVOHEUMQJQXOPC7Y3";
const OWNER: &str = "GDJSH2NU2WF6J4P5DL4522DUCABWSTZOKFQ7BHBCFYQ3QKC6FRYWP6OL";
const TRADER: &str = "local-trader";
const CAPTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/fixtures/mainnet.json");

fn address(value: &str) -> xdr::ScVal {
    if value == TRADER {
        return xdr::ScVal::Address(xdr::ScAddress::Contract(xdr::ContractId(xdr::Hash(
            [0xb1; 32],
        ))));
    }
    xdr::ScVal::Address(xdr::ScAddress::from(&Address::from_str(
        &Env::default(),
        value,
    )))
}

fn amount(value: i128) -> xdr::ScVal {
    xdr::ScVal::I128(xdr::Int128Parts {
        hi: (value >> 64) as i64,
        lo: value as u64,
    })
}

fn number(value: &xdr::ScVal) -> i128 {
    let xdr::ScVal::I128(value) = value else {
        panic!("expected i128, got {value:?}")
    };
    ((value.hi as i128) << 64) | value.lo as i128
}

fn symbol(value: &str) -> xdr::ScVal {
    xdr::ScVal::Symbol(value.try_into().unwrap())
}

fn list(values: Vec<xdr::ScVal>) -> xdr::ScVal {
    xdr::ScVal::Vec(Some(values.try_into().unwrap()))
}

fn field<'a>(value: &'a xdr::ScVal, name: &str) -> &'a xdr::ScVal {
    let xdr::ScVal::Map(Some(entries)) = value else {
        panic!("expected map")
    };
    &entries
        .iter()
        .find(|entry| entry.key == symbol(name))
        .unwrap()
        .val
}

fn item(value: &xdr::ScVal, index: usize) -> &xdr::ScVal {
    let xdr::ScVal::Vec(Some(entries)) = value else {
        panic!("expected vector")
    };
    &entries[index]
}

fn request(contract: &str, function: &str, args: Vec<xdr::ScVal>) -> InvokeRequest {
    let xdr::ScVal::Address(contract) = address(contract) else {
        unreachable!()
    };
    InvokeRequest {
        contract,
        function: function.try_into().unwrap(),
        args,
    }
}

fn claim(minimum: i128) -> InvokeRequest {
    request(
        BACKSTOP,
        "claim",
        vec![
            list(vec![symbol("FirstLoss")]),
            address(OWNER),
            list(vec![address(POOL)]),
            amount(minimum),
        ],
    )
}

fn balance(token: &str, owner: &str) -> InvokeRequest {
    request(token, "balance", vec![address(owner)])
}

fn reserve() -> InvokeRequest {
    request(COMET, "get_balance", vec![address(BLNT)])
}

fn spot() -> InvokeRequest {
    request(COMET, "get_spot_price", vec![address(BLNT), address(XLM)])
}

fn approve(input: i128, ledger: u32) -> InvokeRequest {
    request(
        BLNT,
        "approve",
        vec![
            address(TRADER),
            address(COMET),
            amount(input),
            xdr::ScVal::U32(ledger + 100),
        ],
    )
}

// Explicit local funding with mocked token-admin authorization. No protocol
// accounting, reward entitlement or Comet reserve is edited by this setup.
fn fund(input: i128) -> InvokeRequest {
    request(BLNT, "mint", vec![address(TRADER), amount(input)])
}

fn swap(input: i128, max_price: i128) -> InvokeRequest {
    request(
        COMET,
        "swap_exact_amount_in",
        vec![
            address(BLNT),
            amount(input),
            address(XLM),
            amount(1),
            amount(max_price),
            address(TRADER),
        ],
    )
}

fn user(tier: &str) -> InvokeRequest {
    request(
        BACKSTOP,
        "user_balance",
        vec![list(vec![symbol(tier)]), address(POOL), address(OWNER)],
    )
}

fn pool_data() -> InvokeRequest {
    request(BACKSTOP, "pool_data", vec![address(POOL)])
}

fn env_call(env: &Env, req: InvokeRequest) -> xdr::ScVal {
    let contract = Address::try_from_val(env, &xdr::ScVal::Address(req.contract)).unwrap();
    let function = Symbol::try_from_val(env, &xdr::ScVal::Symbol(req.function)).unwrap();
    let args = kanatoko::soroban_sdk::Vec::from_iter(
        env,
        req.args
            .iter()
            .map(|arg| Val::try_from_val(env, arg).unwrap()),
    );
    let result =
        env.try_invoke_contract::<Val, kanatoko::soroban_sdk::Error>(&contract, &function, args);
    if !matches!(result, Ok(Ok(_))) {
        eprintln!("discovery result: {result:?}");
    }
    let result = result.unwrap().unwrap();
    result.into_val(env)
}

// Discover the union of keys for reads, a real positive claim, and a swap.
// Only initial RPC entries are captured; none of the local operations is sent.
fn discover(env: &Env) {
    env.mock_all_auths();
    for req in [
        balance(BLNT, BACKSTOP),
        balance(COMET, BACKSTOP),
        balance(BLNT, TRADER),
        balance(XLM, TRADER),
        user("FirstLoss"),
        user("SecondLoss"),
        pool_data(),
    ] {
        env_call(env, req);
    }
    let input = number(&env_call(env, reserve())) / 100;
    assert!(input > 0);
    assert_eq!(number(&env_call(env, balance(BLNT, TRADER))), 0);
    assert_eq!(number(&env_call(env, balance(XLM, TRADER))), 0);
    env_call(env, fund(input));
    let lp = number(&env_call(env, claim(0)));
    assert!(
        lp > 0,
        "existing position must have positive claimable rewards"
    );
    let max_price = number(&env_call(env, spot())) * 2;
    env_call(env, approve(input, env.ledger().sequence()));
    env_call(env, swap(input, max_price));
}

fn invoke(fork: &mut StrictFork, req: InvokeRequest, mode: ExecutionMode) -> Receipt {
    fork.invoke(req, mode, AuthMode::Record)
        .expect("all keys must be in the saved capture")
}

fn success(receipt: Receipt) -> xdr::ScVal {
    match receipt.outcome {
        InvokeOutcome::Success(value) => value,
        failure => panic!(
            "{:?}: {failure:?}; diagnostics={:?}",
            receipt.request.function, receipt.diagnostics
        ),
    }
}

fn read(fork: &mut StrictFork, req: InvokeRequest) -> xdr::ScVal {
    success(invoke(fork, req, ExecutionMode::Preview))
}

fn apply(fork: &mut StrictFork, req: InvokeRequest) -> xdr::ScVal {
    success(invoke(fork, req, ExecutionMode::Apply))
}

#[derive(Debug, PartialEq)]
struct Position {
    reward_custody: i128,
    lp_custody: i128,
    owner: xdr::ScVal,
    other_tier: xdr::ScVal,
    pool: xdr::ScVal,
}

fn position(fork: &mut StrictFork) -> Position {
    Position {
        reward_custody: number(&read(fork, balance(BLNT, BACKSTOP))),
        lp_custody: number(&read(fork, balance(COMET, BACKSTOP))),
        owner: read(fork, user("FirstLoss")),
        other_tier: read(fork, user("SecondLoss")),
        pool: read(fork, pool_data()),
    }
}

fn check_deployed_code(captured: &CapturedFixture) {
    let entries = &captured.frozen_fixture().ledger_snapshot().ledger_entries;
    for (id, expected) in [
        (
            BACKSTOP,
            "0469cfb445bedd87478274f265c8776b32cde1e8840fca4684ffa1dc4d5a750f",
        ),
        (
            EMITTER,
            "4fa7d99dee6fe99cad5d07a46ee39e437dc287e53e3ab1f3ccc0aacf7e6cd6c5",
        ),
        (
            COMET,
            "d735c3395f59510172cf5cf838823a1389b97cfec6bf24e580e9bd77d2b3e687",
        ),
        (
            COMET_USDC,
            "d735c3395f59510172cf5cf838823a1389b97cfec6bf24e580e9bd77d2b3e687",
        ),
    ] {
        let hash = entries
            .iter()
            .find_map(|(_, (entry, _))| {
                let xdr::LedgerEntryData::ContractData(data) = &entry.data else {
                    return None;
                };
                if xdr::ScVal::Address(data.contract.clone()) != address(id)
                    || data.key != xdr::ScVal::LedgerKeyContractInstance
                {
                    return None;
                }
                let xdr::ScVal::ContractInstance(instance) = &data.val else {
                    return None;
                };
                let xdr::ContractExecutable::Wasm(hash) = &instance.executable else {
                    return None;
                };
                Some(hash.clone())
            })
            .expect("deployed contract instance is captured");
        let actual = hash
            .0
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        assert_eq!(actual, expected, "deployment changed: {id}");
        let code = entries
            .iter()
            .find_map(|(_, (entry, _))| {
                let xdr::LedgerEntryData::ContractCode(code) = &entry.data else {
                    return None;
                };
                (code.hash == hash).then_some(code)
            })
            .expect("referenced WASM is captured");
        let env = Env::default();
        let digest = env
            .crypto()
            .sha256(&kanatoko::soroban_sdk::Bytes::from_slice(
                &env,
                code.code.as_slice(),
            ));
        assert_eq!(
            digest.to_array(),
            hash.0,
            "WASM bytes match the deployment hash"
        );
    }
}

fn check(captured: &CapturedFixture) {
    check_deployed_code(captured);
    assert_eq!(captured.provenance().protocol_version(), 29);
    assert_eq!(captured.provenance().executed_protocol_version(), 29);
    assert_eq!(captured.report().final_replay_rpc_reads(), 0);
    let mut baseline = captured.fork();
    let initial = position(&mut baseline);
    let original_reserve = number(&read(&mut baseline, reserve()));
    let input = original_reserve / 100;
    apply(&mut baseline, fund(input));
    assert_eq!(position(&mut baseline), initial);
    let funded_digest = baseline.ledger_digest().unwrap();
    let q0 = number(&apply(&mut baseline, claim(0)));
    let reward = initial.reward_custody - position(&mut baseline).reward_custody;
    assert!(q0 > 0 && reward > 0);
    let old_min = q0 * 995 / 1000; // A finite 0.5% tolerance from the baseline.

    let mut changed = captured.fork();
    apply(&mut changed, fund(input));
    assert_eq!(changed.ledger_digest().unwrap(), funded_digest);
    let max_price = number(&read(&mut changed, spot())) * 2;
    let trader_blnt = number(&read(&mut changed, balance(BLNT, TRADER)));
    let trader_xlm = number(&read(&mut changed, balance(XLM, TRADER)));
    apply(
        &mut changed,
        approve(input, captured.provenance().ledger_sequence()),
    );
    let trade = apply(&mut changed, swap(input, max_price));
    let xlm_out = number(item(&trade, 0));
    assert!(xlm_out > 0);
    assert_eq!(
        number(&read(&mut changed, balance(BLNT, TRADER))),
        trader_blnt - input
    );
    assert_eq!(
        number(&read(&mut changed, balance(XLM, TRADER))),
        trader_xlm + xlm_out
    );
    assert_eq!(
        number(&read(&mut changed, reserve())),
        original_reserve + input
    );

    let post_trade = position(&mut changed);
    let checkpoint = changed.checkpoint();
    let q1 = number(&apply(&mut changed, claim(0)));
    assert_eq!(
        post_trade.reward_custody - position(&mut changed).reward_custody,
        reward
    );
    assert!(
        q1 < old_min && old_min <= q0,
        "q0={q0}, old_min={old_min}, q1={q1}"
    );
    changed.revert(checkpoint).unwrap();
    let before_rejection = changed.ledger_digest().unwrap();
    let rejected = invoke(&mut changed, claim(old_min), ExecutionMode::Apply);
    assert!(
        matches!(
            rejected.outcome,
            InvokeOutcome::Failure {
                error: Some(xdr::ScError::Contract(20)),
                ..
            }
        ),
        "{:?}",
        rejected.outcome
    );
    assert_eq!(rejected.before_digest, rejected.after_digest);
    assert!(rejected.state_changes.is_empty());
    let xdr::ScVal::Address(xdr::ScAddress::Contract(comet_id)) = address(COMET) else {
        unreachable!()
    };
    assert!(
        rejected.diagnostics.iter().any(|diagnostic| {
            let xdr::ContractEventBody::V0(body) = &diagnostic.event.body;
            diagnostic.failed_call
                && diagnostic.event.contract_id.as_ref() == Some(&comet_id)
                && body.topics.as_slice()
                    == [
                        symbol("error"),
                        xdr::ScVal::Error(xdr::ScError::Contract(20)),
                    ]
        }),
        "the failure originates in the captured Comet contract"
    );
    assert_eq!(changed.ledger_digest().unwrap(), before_rejection);
    assert_eq!(position(&mut changed), post_trade);
    assert_eq!(
        number(&read(&mut changed, reserve())),
        original_reserve + input
    );

    let new_min = q1 * 995 / 1000;
    assert!(new_min > 0);
    let retry = number(&apply(&mut changed, claim(new_min)));
    assert_eq!(retry, q1);
    let after = position(&mut changed);
    assert_eq!(post_trade.reward_custody - after.reward_custody, reward);
    assert_eq!(after.lp_custody - post_trade.lp_custody, retry);
    assert_eq!(
        number(&read(&mut changed, reserve())),
        original_reserve + input + reward
    );
    assert_eq!(after.other_tier, post_trade.other_tier);
    assert_eq!(field(&after.owner, "q4w"), field(&post_trade.owner, "q4w"));
    let tier = item(field(&post_trade.pool, "tiers"), 0);
    let expected_shares = retry * number(field(tier, "shares")) / number(field(tier, "tokens"));
    assert_eq!(
        number(field(&after.owner, "shares")) - number(field(&post_trade.owner, "shares")),
        expected_shares
    );
    let tier_after = item(field(&after.pool, "tiers"), 0);
    assert_eq!(
        number(field(tier_after, "tokens")) - number(field(tier, "tokens")),
        retry
    );
    assert_eq!(
        number(field(tier_after, "shares")) - number(field(tier, "shares")),
        expected_shares
    );
    // With ledger time fixed, the successfully retried entitlement is consumed once.
    assert_eq!(number(&apply(&mut changed, claim(new_min))), 0);
    assert_eq!(position(&mut changed), after);
    assert_eq!(changed.upstream_reads(), 0);
    println!(
        "ledger={} hash={} protocol=29 present={} absent={}",
        captured.provenance().ledger_sequence(),
        captured.provenance().ledger_hash(),
        captured.report().present_entries(),
        captured.report().absent_entries()
    );
    println!("raw 7-decimal units: reward={reward} baseline_lp={q0} old_min={old_min} changed_lp={q1} new_min={new_min} retry_lp={retry} added_shares={expected_shares}");
    println!("market move: reserve_blnt={original_reserve} sold_blnt={input} received_xlm={xlm_out}; rejection=Contract(20); unchanged_ledger=true; upstream_reads=0");
}

#[test]
fn changed_market_rejects_old_claim_minimum_and_preserves_the_retry() {
    let captured = CapturedFixture::from_file(CAPTURE, NETWORK).unwrap();
    check(&captured);
}

#[test]
#[ignore = "read-only RPC capture; BLNT_NEW_CAPTURE must name a new output file"]
fn capture_current_claim_and_market_dependencies() {
    let path = std::path::PathBuf::from(
        std::env::var_os("BLNT_NEW_CAPTURE").expect("supply a new output path"),
    );
    assert!(!path.exists(), "choose a new file");
    let captured = CaptureBuilder::mainnet("https://mainnet.sorobanrpc.com")
        .unwrap()
        .capture(discover)
        .unwrap();
    captured.write_file(&path).unwrap();
    check(&captured);
}
