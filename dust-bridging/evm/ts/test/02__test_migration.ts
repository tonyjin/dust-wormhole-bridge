import { expect } from "chai";
import { ethers } from "ethers";
import { Y00tsV2__factory } from "../../ts-types/factories/Y00tsV2__factory";
import { Y00tsV3__factory } from "../../ts-types/factories/Y00tsV3__factory";
import { IWormhole__factory } from "@certusone/wormhole-sdk/lib/cjs/ethers-contracts";
import {
  readY00tsV3Proxy,
  formatWormholeMessageFromReceipt,
} from "./helpers/utils";
import {
  POLYGON_LOCALHOST,
  POLYGON_YOOTS,
  WALLET_PRIVATE_KEY,
  ETH_LOCALHOST,
  SOLANA_TEST_YOOT,
  WORMHOLE_GUARDIAN_SET_INDEX,
  GUARDIAN_PRIVATE_KEY,
  POLYGON_MINTER,
  WALLET_PRIVATE_KEY_TWO,
  POLYGON_YOOTS_OWNER,
  DEPRECATED_ERROR,
  ETH_WORMHOLE_ADDRESS,
} from "./helpers/const";
import {
  MockGuardians,
  MockEmitter,
} from "@certusone/wormhole-sdk/lib/cjs/mock";
import { CHAIN_ID_POLYGON, CHAIN_ID_SOLANA } from "@certusone/wormhole-sdk";

describe("Ethereum Migration", () => {
  // Polygon.
  const polyProvider = new ethers.providers.StaticJsonRpcProvider(
    POLYGON_LOCALHOST
  );
  const polyRelayer = new ethers.Wallet(WALLET_PRIVATE_KEY, polyProvider);
  const polyRecipient = new ethers.Wallet(WALLET_PRIVATE_KEY_TWO, polyProvider);
  const polygon = Y00tsV2__factory.connect(POLYGON_YOOTS, polyRelayer);

  // Ethereum.
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_LOCALHOST);
  const ethRelayer = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);
  const ethRecipient = new ethers.Wallet(WALLET_PRIVATE_KEY_TWO, ethProvider);
  const ethereum = Y00tsV3__factory.connect(readY00tsV3Proxy(), ethRelayer);
  const ethWormhole = IWormhole__factory.connect(
    ETH_WORMHOLE_ADDRESS,
    ethProvider
  );

  // MockGuardians and MockCircleAttester objects
  const guardians = new MockGuardians(WORMHOLE_GUARDIAN_SET_INDEX, [
    GUARDIAN_PRIVATE_KEY,
  ]);

  // Mock Solana Emitter.
  const solanaEmitter = new MockEmitter(
    POLYGON_MINTER.substring(2),
    CHAIN_ID_SOLANA
  );

  let localVars: any = {};

  describe("Test Forward From Solana to Ethereum", () => {
    before(async () => {
      // Create migration message from Solana -> Polygon. This message
      // should be forwarded to ethereum.
      const payload: Buffer = Buffer.alloc(22);
      payload.writeUInt16BE(Number(SOLANA_TEST_YOOT), 0);
      payload.set(Buffer.from(polyRecipient.address.slice(2), "hex"), 2);

      const msgFromSolana = solanaEmitter.publishMessage(
        0, // Nonce
        payload,
        1, // Finality
        1234567 // Timestamp
      );
      localVars["msgFromSolana"] = guardians.addSignatures(msgFromSolana, [0]);
    });

    it("Cannot Invoke `UpdateAmountsOnMint` (Deprecated)", async () => {
      // Start prank (impersonate the attesterManager).
      await polyProvider.send("anvil_impersonateAccount", [
        POLYGON_YOOTS_OWNER,
      ]);

      // Try to call the `getAmountsOnMint` function
      let failed: boolean = false;
      try {
        await polygon
          .connect(polyProvider.getSigner(POLYGON_YOOTS_OWNER))
          .updateAmountsOnMint(69, 420)
          .then(async (tx) => {
            const receipt = await tx.wait();
            return receipt;
          });
      } catch (e: any) {
        expect(e.error.error.data).to.equal(DEPRECATED_ERROR);
        failed = true;
      }

      // End prank.
      await polyProvider.send("anvil_stopImpersonatingAccount", [
        POLYGON_YOOTS_OWNER,
      ]);
    });

    it("Cannot Invoke `getAmountsOnMint` (Deprecated)", async () => {
      // Try to call the `getAmountsOnMint` function
      let failed: boolean = false;
      try {
        await polygon.getAmountsOnMint();
      } catch (e: any) {
        expect(e.data).to.equal(DEPRECATED_ERROR);
        failed = true;
      }
    });

    it("Cannot Invoke `ReceiveAndMint` (Deprecated)", async () => {
      // Try to call the `receiveAndMint` function and post the Solana VAA.
      let failed: boolean = false;
      try {
        await polygon
          .receiveAndMint(localVars["msgFromSolana"])
          .then(async (tx) => {
            const receipt = await tx.wait();
            return receipt;
          });
      } catch (e: any) {
        expect(e.error.error.error.data).to.equal(DEPRECATED_ERROR);
        failed = true;
      }
    });

    it("Invoke `forwardMessage`", async () => {
      const receipt = await polygon
        .forwardMessage(localVars["msgFromSolana"])
        .then(async (tx: ethers.ContractTransaction) => {
          const receipt = await tx.wait();
          return receipt;
        })
        .catch((msg) => {
          // should not happen
          console.log(msg);
          return null;
        });
      expect(receipt).is.not.null;

      // Fetch the forwarded message and sign it.
      const unsignedMessages = await formatWormholeMessageFromReceipt(
        receipt!,
        CHAIN_ID_POLYGON
      );
      expect(unsignedMessages.length).to.equal(1);

      localVars["forwardMsgFromPolygon"] = guardians.addSignatures(
        unsignedMessages[0],
        [0]
      );
    });

    it("Invoke `receiveAndMint` on Ethereum With Forwarded Message", async () => {
      // Fetch the balance of the recipient before the mint.
      const balanceBefore = await ethereum.balanceOf(ethRecipient.address);
      const ethBalanceBefore = await ethProvider.getBalance(
        ethRecipient.address
      );

      const [_, nativeAmount] = await ethereum.getAmountsOnMint();

      const receipt = await ethereum
        .receiveAndMint(localVars["forwardMsgFromPolygon"], {
          value: nativeAmount,
        })
        .then(async (tx: ethers.ContractTransaction) => {
          const receipt = await tx.wait();
          return receipt;
        })
        .catch((msg) => {
          // should not happen
          console.log(msg);
          return null;
        });
      expect(receipt).is.not.null;

      // Fetch the balance of the recipient after the mint.
      const balanceAfter = await ethereum.balanceOf(ethRecipient.address);
      const ethBalanceAfter = await ethProvider.getBalance(
        ethRecipient.address
      );

      // Confirm balance changes.
      expect(balanceAfter.sub(balanceBefore).toNumber()).to.equal(1);
      expect(await ethereum.ownerOf(SOLANA_TEST_YOOT)).to.equal(
        ethRecipient.address
      );
      expect(ethBalanceAfter.sub(ethBalanceBefore).eq(nativeAmount)).to.be.true;
    });
  });
});
