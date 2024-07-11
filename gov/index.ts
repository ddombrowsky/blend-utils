import {
  BondingVotesContract,
  ContractError,
  ContractErrorType,
  ContractResult,
  GovernorContract,
  GovernorSettings,
  ProposalAction,
  Resources,
  TokenVotesContract,
  VoteCount,
} from "@script3/soroban-governor-sdk";
import {
  Account,
  Address,
  Horizon,
  SorobanRpc,
  Transaction,
  TransactionBuilder,
  xdr,
} from "@stellar/stellar-sdk";

const network: Network = {
  rpc:
    process.env.NEXT_PUBLIC_RPC_URL || "https://soroban-testnet.stellar.org",
  passphrase:
    process.env.NEXT_PUBLIC_PASSPHRASE || "Test SDF Network ; September 2015",
  opts: undefined,
};

export interface TxOptions {
  sim: boolean;
  pollingInterval: number;
  timeout: number;
  builderOptions: TransactionBuilder.TransactionBuilderOptions;
}

export interface Network {
  rpc: string;
  passphrase: string;
  maxConcurrentRequests?: number;
  opts?: Horizon.Server.Options;
}

export type SorobanResponse =
  | SorobanRpc.Api.GetTransactionResponse
  | SorobanRpc.Api.SimulateTransactionResponse
  | SorobanRpc.Api.SendTransactionResponse;

/**
 * Invoke a `InvokeHostFunction` operation against the Stellar network.
 *
 * @param source - The source of the transaction.
 * @param sign - The function for signing the transaction.
 * @param network - The network and rpc to invoke the transaction on.
 * @param txOptions - The options for the transaction.
 * @param parse - The function for parsing the result of the transaction.
 * @param operation - The invokeHostFunction operation to invoke.
 * @returns The result of the transaction as a ContractResult.
 */
export async function invokeOperation<T>(
  source: string,
  network: Network,
  txOptions: TxOptions,
  parse: any,
  operation: xdr.Operation | string
): Promise<string> {
  // create TX
  const rpc = new SorobanRpc.Server(network.rpc, network.opts);
  let source_account: Account;
  if (txOptions.sim) {
    // no need to fetch the source account for a simulation, use a random sequence number
    source_account = new Account(source, "123");
  } else {
    source_account = await rpc.getAccount(source);
  }
  console.log(source);
  console.log(source_account);
  const tx_builder = new TransactionBuilder(
    source_account,
    txOptions.builderOptions
  );
  if (typeof operation === "string") {
    operation = xdr.Operation.fromXDR(operation, "base64");
  }

  tx_builder.addOperation(operation);
  const tx = tx_builder.build();

  // simulate the TX
  const simulation_resp = await rpc.simulateTransaction(tx);
  console.log(simulation_resp);
  if (SorobanRpc.Api.isSimulationError(simulation_resp)) {
    // No resource estimation available from a simulation error. Allow the response formatter
    // to fetch the error.
    const empty_resources = new Resources(0, 0, 0, 0, 0, 0, 0);
    /*
    return ContractResult.fromSimulationResponse(
      simulation_resp,
      tx.hash().toString("hex"),
      empty_resources,
      parse
    );
    */
    console.log(tx.hash().toString("hex"));
    // see soroban-governor/contracts/governor/src/errors.rs
    return 'simulation error';
  } else if (txOptions.sim) {
    // Only simulate the TX. Assemble the TX to borrow the resource estimation algorithm in
    // `assembleTransaction` and return the simulation results.
    const prepped_tx = SorobanRpc.assembleTransaction(
      tx,
      simulation_resp
    ).build();
    const resources = Resources.fromTransaction(prepped_tx.toXDR());
    /*
    return ContractResult.fromSimulationResponse(
      simulation_resp,
      prepped_tx.hash().toString("hex"),
      resources,
      parse
    );
    */
    return '';
  }

  // assemble the TX
  const assemble_tx = SorobanRpc.assembleTransaction(
    tx,
    simulation_resp
  ).build();
  console.log(assemble_tx);

  return assemble_tx.toXDR();
}

async function vote(
  proposalId: number,
  support: number, // The vote support type (0=against, 1=for, 2=abstain)
  sim: boolean,
  governorAddress: string,
  walletAddress: string
) {
  try {
    let txOptions: TxOptions = {
      sim,
      pollingInterval: 1000,
      timeout: 15000,
      builderOptions: {
        fee: "10000",
        timebounds: {
          minTime: 0,
          maxTime: Math.floor(Date.now() / 1000) + 5 * 60 * 1000,
        },
        networkPassphrase: network.passphrase,
      },
    };
    let governorClient = new GovernorContract(governorAddress);
    let voteOperation = governorClient.vote({
      voter: walletAddress,
      proposal_id: proposalId,
      support,
    });

    const submission = invokeOperation<xdr.ScVal>(
      walletAddress,
      network,
      txOptions,
      GovernorContract.parsers.vote,
      voteOperation
    );
    const sub = await submission;
    console.log(sub);

    /*
    if (sim) {
      const sub = await submission;
      if (sub instanceof ContractResult) {
        return sub.result.unwrap();
      }
      return sub;
    } else {
      return;
      //return submitTransaction<bigint>(submission, {
      //  notificationMode: "modal",
      //  notificationTitle: "Your vote is in!",
      //  successMessage: "Your vote has been submitted successfully",
      //});
    }
    */
  } catch (e) {
    throw e;
  }
}

vote(2, 1, false,'CANSYFVMIP7JVYEZQ463Y2I2VLEVNLDJJ4QNZTDBGLOOGKURPTW4A6FQ', 'GDJSH2NU2WF6J4P5DL4522DUCABWSTZOKFQ7BHBCFYQ3QKC6FRYWP6OL');
