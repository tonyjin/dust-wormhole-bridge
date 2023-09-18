import { expect } from "chai";
import { ethers } from "ethers";
import { Y00tsV2__factory } from "../../ts-types/factories/Y00tsV2__factory";
import { Y00tsV3__factory } from "../../ts-types/factories/Y00tsV3__factory";
import { readY00tsV3Proxy } from "./helpers/utils";
import {
  POLYGON_LOCALHOST,
  POLYGON_YOOTS,
  WALLET_PRIVATE_KEY,
  POLYGON_WORMHOLE_ADDRESS,
  POLYGON_DUST,
  POLYGON_MINTER,
  Y00TS_URI,
  POLYGON_YOOTS_OWNER,
  ETH_LOCALHOST,
} from "./helpers/const";

describe("Ethereum Migration", () => {
  // Polygon.
  const polyProvider = new ethers.providers.StaticJsonRpcProvider(
    POLYGON_LOCALHOST
  );
  const polyWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, polyProvider);
  const polygon = Y00tsV2__factory.connect(POLYGON_YOOTS, polyWallet);

  // Ethereum.
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_LOCALHOST);
  const ethWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);
  const ethereum = Y00tsV3__factory.connect(readY00tsV3Proxy(), ethWallet);

  let localVars: any = {};

  it("test", async () => {});
});
