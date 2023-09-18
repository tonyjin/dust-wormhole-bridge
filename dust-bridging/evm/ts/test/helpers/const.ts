import { ethers } from "ethers";

// ethereum goerli testnet fork
export const ETH_LOCALHOST = "http://localhost:8546";
export const ETH_WORMHOLE_ADDRESS = process.env.ETH_WORMHOLE!;

// polygon mumbai testnet fork
export const POLYGON_LOCALHOST = "http://localhost:8547";
export const POLYGON_WORMHOLE_ADDRESS = process.env.POLYGON_WORMHOLE!;
export const POLYGON_YOOTS = process.env.POLYGON_YOOTS!;
export const POLYGON_YOOTS_OWNER = process.env.POLYGON_YOOTS_OWNER!;
export const POLYGON_DUST = process.env.POLYGON_DUST!;
export const POLYGON_MINTER = process.env.POLYGON_MINTER!;

// global
export const WORMHOLE_MESSAGE_FEE = ethers.BigNumber.from(
  process.env.TESTING_WORMHOLE_MESSAGE_FEE!
);
export const WORMHOLE_GUARDIAN_SET_INDEX = Number(
  process.env.TESTING_WORMHOLE_GUARDIAN_SET_INDEX!
);
export const GUARDIAN_PRIVATE_KEY = process.env.TESTING_DEVNET_GUARDIAN!;
export const WALLET_PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY!;
export const WALLET_PRIVATE_KEY_TWO = process.env.WALLET_PRIVATE_KEY_TWO!;
export const Y00TS_URI = "https://metadata.y00ts.com/y/";
