import { DustBridging } from "./dust_bridging_sdk";
import { Connection, PublicKey, Transaction, sendAndConfirmRawTransaction, Keypair } from "@solana/web3.js";
import bs58 from "bs58";
import fs from 'fs';

const connection = new Connection("https://blissful-purple-daylight.solana-devnet.discover.quiknode.pro/e4a2fc8ffff28953792841fd06f3dd1a87374bc6/");
const bridge = new DustBridging(
  connection,
  "CaSzLCPQEkqeeniLjRXEVqsqShW7AXExWsxU1RtXz9J2"
);

const deployY00ts = async () => {
  let walletFile = JSON.parse(fs.readFileSync('./wallet/devnet.json').toString());
  // Burn Wallet Secret Key
  const burnSecretKey = Uint8Array.from(walletFile);

  // Keypair for burn wallet
  var wallet = Keypair.fromSecretKey(burnSecretKey);

  const tx = new Transaction();
  tx.add(await bridge.createInitializeInstruction(
    new PublicKey('9mo4RgGdehjpzukvTTAJosfXE1yuco17qS25jhMC3u8Y'),
  ));

  const latestBlockHash = await connection.getLatestBlockhash();
  tx.recentBlockhash = latestBlockHash.blockhash;
  tx.feePayer = wallet.publicKey;
  tx.sign(wallet);

  const txid = await sendAndConfirmRawTransaction(
    connection,
    tx.serialize(),
    {
      blockhash: latestBlockHash.blockhash,
      lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
      signature: bs58.encode(tx.signature as Buffer),
    }
  )
  console.log(txid);
};

const burnY00T = async () => {
  let walletFile = JSON.parse(fs.readFileSync('./wallet/smx.json').toString());
  // Burn Wallet Secret Key
  const burnSecretKey = Uint8Array.from(walletFile);

  // Keypair for burn wallet
  var wallet = Keypair.fromSecretKey(burnSecretKey);
  const tx = new Transaction();
  tx.add(await bridge.createSendAndBurnInstruction(
    wallet.publicKey,
    new PublicKey('29BSMwFtgZXa5GBiArutD2zafn2GT8GawdCKHkzqgV6Y'),//token account
    "0xC3920d13F00Dc03DE66FA7111600cD2635564147"
  ));
  const latestBlockHash = await connection.getLatestBlockhash();
  tx.recentBlockhash = latestBlockHash.blockhash;
  tx.feePayer = wallet.publicKey;
  tx.sign(wallet);

  const txid = await sendAndConfirmRawTransaction(
    connection,
    tx.serialize(),
    {
      blockhash: latestBlockHash.blockhash,
      lastValidBlockHeight: latestBlockHash.lastValidBlockHeight,
      signature: bs58.encode(tx.signature as Buffer),
    }
  )
  console.log(txid);
};

burnY00T().then(() => console.log("Done")).catch((err) => console.error(err));