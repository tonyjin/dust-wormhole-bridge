import { DeBridge } from "./de_bridge_sdk";
import {
  Connection,
  PublicKey,
  Transaction,
  sendAndConfirmRawTransaction,
  Keypair,
} from "@solana/web3.js";
import bs58 from "bs58";
import fs from "fs";
import pLimit from "p-limit";

// const connection = new Connection("https://blissful-purple-daylight.solana-devnet.discover.quiknode.pro/e4a2fc8ffff28953792841fd06f3dd1a87374bc6/");
const connection = new Connection(
  "https://solana-api.syndica.io/access-token/ofILhlxYM1LsldyQI4cbkDpJeE4fpfa7B2zPMSSUt7BFsn9On3NmP684fykO9KF5/rpc"
);
const bridge = new DeBridge(
  connection,
  // "CaSzLCPQEkqeeniLjRXEVqsqShW7AXExWsxU1RtXz9J2", // y00ts devnet collection mint
  // "4mKSoDDqApmF1DqXvVTSL6tu2zixrSSNjqMxUnwvVzy2", // y00ts mainnet collection mint
  // "GUfjvMzmDBVmFGuwY1rsHCcryDg9BnH5qckrBjikJvPn", // degods devnet collection mint
  "6XxjKYFbcndh2gDcsUrmZgVEsoDxXMnfsaGY6fpTJzNr", // degods mainnet collection mint
  {
    metadata: "35iLrpYNNR9ygHLcvE1xKFHbHq6paHthrF6wSovdWgGu", // mainnet program address
    wormholeId: "worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth", // mainnet wormhole id
    // metadata: "HhX1RVWgGTLrRSiEiXnu4kToHZhFLpqi5qkErkfFnqEQ", // devnet
    // wormholeId: "3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5" // devnet
  }
);

const deploy = async () => {
  // Keypair
  var wallet = Keypair.fromSecretKey(
    Uint8Array.from(
      JSON.parse(
        fs
          .readFileSync(
            "./wallet/DeBgVw3fCEMdTNjNYFmvJ1CjC5Mj32TYdUHrpUbbR5w3.json"
          )
          .toString()
      )
    )
  );

  var collectionAuthority = Keypair.fromSecretKey(
    Uint8Array.from(
      JSON.parse(
        fs
          .readFileSync(
            "./wallet/degods.json"
          )
          .toString()
      )
    )
  );

  console.log(wallet.publicKey.toBase58());

  console.log(bridge.getInstanceAddress().toBase58());

  const tx = new Transaction();
  tx.add(await bridge.createInitializeInstruction(wallet.publicKey,
    10000
  ));

  const latestBlockHash = await connection.getLatestBlockhash();
  tx.recentBlockhash = latestBlockHash.blockhash;
  tx.feePayer = wallet.publicKey;
  tx.sign(wallet, collectionAuthority);
  // console.log(tx)

  const txid = await sendAndConfirmRawTransaction(connection, tx.serialize(), {
    blockhash: latestBlockHash.blockhash,
    lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
    signature: bs58.encode(tx.signature as Buffer),
  });
  console.log(txid);
};

const pause = async () => {
  // Keypair
  var wallet = Keypair.fromSecretKey(
    Uint8Array.from(
      JSON.parse(
        fs
          .readFileSync(
            "./wallet/degods.json"
          )
          .toString()
      )
    )
  );

  const tx = new Transaction();
  tx.add(
    await bridge.createSetPausedInstruction(
      wallet.publicKey,
      false //change that to false to unpause
    )
  )

  const latestBlockHash = await connection.getLatestBlockhash();
  tx.recentBlockhash = latestBlockHash.blockhash;
  tx.feePayer = wallet.publicKey;
  tx.sign(wallet);
  // console.log(tx)

  const txid = await sendAndConfirmRawTransaction(connection, tx.serialize(), {
    blockhash: latestBlockHash.blockhash,
    lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
    signature: bs58.encode(tx.signature as Buffer),
  });
  console.log(txid);
};

const burn = async () => {
  let walletFile = JSON.parse(fs.readFileSync("./wallet/devnet.json").toString());
  // Burn Wallet Secret Key
  const burnSecretKey = Uint8Array.from(walletFile);

  // Keypair for burn wallet
  var wallet = Keypair.fromSecretKey(burnSecretKey);
  const tx = new Transaction();
  tx.add(
    await bridge.createSendAndBurnInstruction(
      wallet.publicKey,
      new PublicKey("3VjPfHvPymS6bUzs2WLfyfxGxiBjAYTtePzxeEHamhAF"), //token account
      "0x97b81604aA2efdFdd29F04a472f1c086dF84405b"
    )
  );
  const latestBlockHash = await connection.getLatestBlockhash();
  tx.recentBlockhash = latestBlockHash.blockhash;
  tx.feePayer = wallet.publicKey;
  tx.sign(wallet);

  const txid = await sendAndConfirmRawTransaction(connection, tx.serialize(), {
    blockhash: latestBlockHash.blockhash,
    lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
    signature: bs58.encode(tx.signature as Buffer),
  });
  console.log(txid);
};

const initializeWhitelists = async () => {
  var wallet = Keypair.fromSecretKey(
    Uint8Array.from(
      JSON.parse(
        fs
          .readFileSync(
            "./wallet/degods.json"
          )
          .toString()
      )
    )
  );

  // snapshot of unclaimed deGods t00bs from mainnet
  const unclaimedDeGodsIds = JSON.parse(
    fs.readFileSync('unclaimedDeGods.json').toString()
  ).map((d:any)=>d.deadGodId-1);

  // incinerated ids
  const burntIds = JSON.parse(
    fs.readFileSync('incinerator.json').toString()
  ).map((d:any)=>parseInt(d.id.split('#'))-1);

  // ONLY FOR DEVNET
  // MAINNET SHOULD BE 10000 instead of 9465
  const whitelist = [...Array(10000).keys()].map(
    (id)=>{
      if(!unclaimedDeGodsIds.includes(id) && !burntIds.includes(id)) return true;
      return false;
    });

  const instructions = await bridge.createWhitelistBulkInstructions(
    wallet.publicKey,
    whitelist
  )

  console.log(instructions.length,'instructions');

  //Transaction will be too large, cut in half
  const firstTx = new Transaction().add(instructions[0]);
  let latestBlockHash = await connection.getLatestBlockhash();
  firstTx.recentBlockhash = latestBlockHash.blockhash;
  firstTx.feePayer = wallet.publicKey;
  firstTx.sign(wallet);

  const firstTxId = await sendAndConfirmRawTransaction(connection, firstTx.serialize(), {
    blockhash: latestBlockHash.blockhash,
    lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
    signature: bs58.encode(firstTx.signature as Buffer),
  });
  console.log('firstTx', firstTxId);

  const secondTx = new Transaction().add(instructions[1]);
  latestBlockHash = await connection.getLatestBlockhash();
  secondTx.recentBlockhash = latestBlockHash.blockhash;
  secondTx.feePayer = wallet.publicKey;
  secondTx.sign(wallet);

  const secondTxId = await sendAndConfirmRawTransaction(connection, secondTx.serialize(), {
    blockhash: latestBlockHash.blockhash,
    lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
    signature: bs58.encode(secondTx.signature as Buffer),
  });
  console.log('secondTx', secondTxId);
};

const whitelistOne = async (tokenId: number, keypair: Keypair) => {
  if(await bridge.isNftWhitelisted(tokenId)){
    console.log(tokenId, 'already whitelisted');
    return;
  }

  const instructions = await bridge.createWhitelistInstruction(
    keypair.publicKey,
    tokenId
  )

  //Transaction will be too large, cut in half
  const tx = new Transaction().add(instructions);
  let latestBlockHash = await connection.getLatestBlockhash();
  tx.recentBlockhash = latestBlockHash.blockhash;
  tx.feePayer = keypair.publicKey;
  tx.sign(keypair);

  const txId = await sendAndConfirmRawTransaction(connection, tx.serialize(), {
    blockhash: latestBlockHash.blockhash,
    lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
    signature: bs58.encode(tx.signature as Buffer),
  });
  console.log(tokenId, 'whitelisted', txId);
};

const whitelistMany = async (tokenIds: number[]) => {
  var wallet = Keypair.fromSecretKey(
    Uint8Array.from(
      JSON.parse(
        fs
          .readFileSync(
            "./wallet/degods.json"
          )
          .toString()
      )
    )
  );

  const limit = pLimit(1);

  await Promise.all(
    tokenIds.map((id) => limit(() => whitelistOne(id, wallet)))
  )
};

whitelistMany([])
  .then((res) => console.log("Done"))
  .catch((err) => console.error(err));
