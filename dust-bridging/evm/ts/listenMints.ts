import { ethers, utils } from "ethers";
import { ABI } from "./abi";
import "dotenv/config";

const CONTRACT_ADDRESS = "0x2aC3ff0D83e936b65933f33c7A5D1dFFf8725645";
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const eventSignature: string = "Minted(uint256,address)";
const eventTopic: string = ethers.utils.id(eventSignature);
const intrfc = new ethers.utils.Interface(ABI);

async function getLogHistory() {
  console.log(`Getting the PunkTransfer events...`);
  // Get the data hex string
  const currentBlock = await provider.getBlockNumber();
  console.log(currentBlock);
  const rawLogs = await provider.getLogs({
    address: CONTRACT_ADDRESS,
    topics: [eventTopic],
    fromBlock: currentBlock - 10000,
    toBlock: currentBlock,
  });

  return rawLogs.map((log) => ({
    ...{
      blockNumber: log.blockNumber,
      blockHash: log.blockHash,
      transactionHash: log.transactionHash,
    },
    ...intrfc.parseLog(log),
  }));
}

async function listenToEvents() {
  const filter = {
    address: CONTRACT_ADDRESS,
    topics: [eventTopic],
  };

  provider.on(filter, (log) => {
    // do whatever you want here
    console.log("Minted!");
    console.log(intrfc.parseLog(log));
  });
}

listenToEvents().then(() => {
  console.log("Listening to events...");
});
