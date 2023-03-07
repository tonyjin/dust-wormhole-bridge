import {expect, use as chaiUse} from "chai";
import chaiAsPromised from 'chai-as-promised';
chaiUse(chaiAsPromised);
import {
  Connection,
  PublicKey,
  Keypair,
  Transaction,
  sendAndConfirmTransaction,
  LAMPORTS_PER_SOL,
} from "@solana/web3.js";
import {CONTRACTS} from "@certusone/wormhole-sdk";
import * as wormhole from "@certusone/wormhole-sdk/lib/cjs/solana/wormhole";
import {Metaplex, keypairIdentity, CreateNftOutput} from "@metaplex-foundation/js";
import {TokenStandard} from '@metaplex-foundation/mpl-token-metadata';
import {DustBridging} from "../dust_bridging_sdk";

const LOCALHOST = "http://localhost:8899";
const GUARDIAN_ADDRESS = "0xbefa429d57cd18b7f8a4d91a2da9ab4af05d0fbe";
const WORMHOLE_ID = new PublicKey(CONTRACTS.MAINNET.solana.core);

const range = (size: number) => [...Array(size).keys()];

describe("Dust NFT bridging", function() {
  const admin = Keypair.generate();
  const delegate = Keypair.generate();
  const user = Keypair.generate();
  const connection = new Connection(LOCALHOST, "processed");
  const metaplex = Metaplex.make(connection).use(keypairIdentity(admin));
  const tokenId = 3250;
  const whitelistSize = 10000;

  const tokenStandardTestCases =
    ["NonFungible" /*, "ProgrammableNonFungible"*/] as (keyof typeof TokenStandard)[];
  const truthValues = [true, false];
  const allHighlevelCombinations = tokenStandardTestCases.flatMap(
    tokenStandardName => truthValues.flatMap(useWhitelist => {
      return {
        tokenStandardName,
        useWhitelist,
      };
    })
  );

  const nftCount = (owner: Keypair) =>
    metaplex.nfts().findAllByOwner({owner: owner.publicKey}).then(arr => arr.length);
  // const getCollectionNft = () =>
  //   metaplex.nfts().findByMint({mintAddress: collectionMint}) as Promise<Nft>;

  before("Setup the environment", async function() {
    const airdropSol = async (keypair: Keypair) => {
      return connection.confirmTransaction(
        await connection.requestAirdrop(keypair.publicKey, 1000 * LAMPORTS_PER_SOL)
      );
    };

    await airdropSol(admin);
    await airdropSol(delegate);
    await airdropSol(user);
    
    const guardianSetExpirationTime = 86400;
    const fee = 100n;
    const devnetGuardian = Buffer.from(GUARDIAN_ADDRESS.substring(2), "hex");

    await sendAndConfirmTransaction(
      connection,
      new Transaction().add(
        wormhole.createInitializeInstruction(
          WORMHOLE_ID,
          admin.publicKey,
          guardianSetExpirationTime,
          fee,
          [devnetGuardian]
        )
      ),
      [admin]
    );
  });

  allHighlevelCombinations.forEach(({tokenStandardName, useWhitelist}) =>
  describe("NFT with token standard " + tokenStandardName +
      + " with" + (useWhitelist ? "" : "out") + " using a whitelist", function() {
    const collectionMintPair = Keypair.generate();
    const collectionMint = collectionMintPair.publicKey;
    const dustBridging = new DustBridging(connection, collectionMint);
    const tokenStandard = TokenStandard[tokenStandardName];
    //const isSizedCollection = tokenStandard === TokenStandard.ProgrammableNonFungible;

    const setPause = async (sender: Keypair, paused: boolean) => sendAndConfirmTransaction(
      connection,
      new Transaction().add(await dustBridging.createSetPausedInstruction(
        sender.publicKey,
        paused,
      )),
      [sender]
    );

    before("Create NFT", async function() {
      await metaplex.nfts().create({
        useNewMint: collectionMintPair,
        name: "DeGods",
        symbol: "DGOD",
        uri: "https://arweave.net/k8ZelfKwFjZcxNMyfhnXAaPfZPp5YISLZmvBha6gz48",
        sellerFeeBasisPoints: 333,
        tokenStandard,
        //for NFTs with the "old", non-programmable standard, we also don't set isCollection
        isCollection: false, //tokenStandard === TokenStandard.ProgrammableNonFungible,
      });
    });

    describe("Initialize Ix", function() {
      const initialize = (deployer: Keypair) => async function() {
        expect(await dustBridging.isInitialized()).equals(false);

        const dustInitTx = sendAndConfirmTransaction(
          connection,
          new Transaction().add(await dustBridging.createInitializeInstruction(
            deployer.publicKey,
            useWhitelist ? whitelistSize : 0,
          )),
          [deployer]
        );
        
        await expect(dustInitTx).to.be[(deployer === admin) ? "fulfilled" : "rejected"];
        expect(await dustBridging.isInitialized()).equals(deployer === admin);
      };

      it("as user", initialize(user));
      it("as admin", initialize(admin));
    });

    if (useWhitelist)
      describe("bulk whitelisting (takes a while)", function() {
        it("test and reset", async function() {
          const tokenIdsToWhitelist = [0, 1, 8, whitelistSize-9, whitelistSize-2, whitelistSize-1];
          const notWhitelisted = [2,7,9,whitelistSize-10,whitelistSize-8, whitelistSize-3];
          const bulkWhitelistIxs = await dustBridging.createWhitelistBulkInstructions(
            admin.publicKey,
            range(whitelistSize).map(index => tokenIdsToWhitelist.includes(index))
          );

          for (const ix of bulkWhitelistIxs)
            await expect(
              sendAndConfirmTransaction(connection, new Transaction().add(ix), [admin])
            ).to.be.fulfilled;
          
          for (const tokenId of tokenIdsToWhitelist)
            expect(await dustBridging.isNftWhitelisted(tokenId)).to.equal(true);
          
          for (const tokenId of notWhitelisted)
            expect(await dustBridging.isNftWhitelisted(tokenId)).to.equal(false);
          
          const resetWhitelistIxs = await dustBridging.createWhitelistBulkInstructions(
            admin.publicKey,
            range(whitelistSize).map(_ => false)
          );

          for (const ix of resetWhitelistIxs)
            await expect(
              sendAndConfirmTransaction(connection, new Transaction().add(ix), [admin])
            ).to.be.fulfilled;
          
          for (const tokenId of tokenIdsToWhitelist)
            expect(await dustBridging.isNftWhitelisted(tokenId)).to.equal(false);
        })
      });
    
    if (useWhitelist)
      describe("delegation", function() {
        const setDelegate = async (newDelegate: PublicKey | null) => sendAndConfirmTransaction(
          connection,
          new Transaction().add(await dustBridging.createSetDelegateInstruction(newDelegate)),
          [admin]
        );

        const delegateWhitelist = async (tokenId: number) => sendAndConfirmTransaction(
          connection,
          new Transaction().add(await dustBridging.createWhitelistInstruction(
            delegate.publicKey,
            tokenId,
          )),
          [delegate]
        );

        it("unauthorized delegate can't pause", async function() {
          await expect(delegateWhitelist(whitelistSize-1)).to.be.rejected;
        });

        it("unauthorized delegate can't whitelist", async function() {
          await expect(setPause(delegate, true)).to.be.rejected;
        });

        it("admin authorizes delegate", async function() {
          await expect(setDelegate(delegate.publicKey)).to.be.fulfilled;
        });

        it("authorized delegate pauses", async function() {
          await expect(setPause(delegate, true)).to.be.fulfilled;
        });

        it("admin unpauses", async function() {
          await expect(setPause(admin, false)).to.be.fulfilled;
        });

        it("delegate whitelists", async function() {
          await expect(delegateWhitelist(whitelistSize-1)).to.be.fulfilled;
        });

        it("admin revokes authorization", async function() {
          await expect(setDelegate(null)).to.be.fulfilled;
        });

        it("delegate can't pause anymore", async function() {
          await expect(setPause(delegate, true)).to.be.rejected;
        });

        it("delegate can't whitelist anymore", async function() {
          await expect(delegateWhitelist(0)).to.be.rejected;
        });
      });

    describe("BurnAndSend Ix", function() {
      let createdNftOutput: CreateNftOutput;
      const evmRecipient = "0x" + "00123456".repeat(5);
      const burnAndSend = async (sender: Keypair) => sendAndConfirmTransaction(
        connection,
        new Transaction().add(await dustBridging.createSendAndBurnInstruction(
          sender.publicKey,
          createdNftOutput.tokenAddress,
          evmRecipient,
        )),
        //if admin != nft token owner, then the nft token owner must sign the transaction as well
        [sender]
      );

      before("create the NFT", async function() {
        expect(await nftCount(user)).equals(0);

        //does not verify that the NFT belongs to the collection
        createdNftOutput = await metaplex.nfts().create({
          name: "DeGod #" + (tokenId+1),
          symbol: "DGOD",
          uri: "https://metadata.degods.com/g/" + tokenId + ".json",
          sellerFeeBasisPoints: 333,
          collection: collectionMint,
          tokenOwner: user.publicKey,
        });

        expect(await nftCount(user)).equals(1);
      });

      describe("without verifying that the NFT belongs to the collection", function() {
        it("when not the owner of the NFT", async function() {
          await expect(burnAndSend(admin)).to.be.rejected;
        });

        it("as the owner of the NFT", async function() {
          await expect(burnAndSend(user)).to.be.rejected;
        });
      });

      describe("after verifying the NFT", function() {
        before("verify the NFT as part of the collection", async function() {
          await metaplex.nfts().verifyCollection({
            mintAddress: createdNftOutput.mintAddress,
            collectionMintAddress: collectionMint,
            isSizedCollection: false, //DeGods and y00ts are both legacy collections
          });
        });

        it("when not the owner of the NFT", async function() {
          await expect(burnAndSend(admin)).to.be.rejected;
        });
      });
      
      if (useWhitelist) {
        describe("without whitelisting the NFT", function() {
          it("as the owner of the NFT ", async function() {
            expect (await dustBridging.isNftWhitelisted(tokenId)).to.equal(false);
            await expect(burnAndSend(user)).to.be.rejected;
          });
        });

        describe("after whitelisting the NFT", function() {
          before("whitelist the NFT via whitelist instruction", async function() {
            expect (await dustBridging.isNftWhitelisted(tokenId)).to.equal(false);

            await expect(sendAndConfirmTransaction(
              connection,
              new Transaction().add(await dustBridging.createWhitelistInstruction(
                admin.publicKey,
                tokenId
              )),
              [admin]
            )).to.be.fulfilled;

            expect (await dustBridging.isNftWhitelisted(tokenId)).to.equal(true);
          });

          it("when not the owner of the NFT", async function() {
            await expect(burnAndSend(admin)).to.be.rejected;
          });
        });
      }

      describe("not while paused", function() {
        before("pause", async function() {
          await expect(setPause(admin, true)).to.be.fulfilled;
        });

        it("as the owner of the NFT", async function() {
          await expect(burnAndSend(user)).to.be.rejected;
        });

        after("unpause", async function() {
          await expect(setPause(admin, false)).to.be.fulfilled;
        });
      });

      describe("and finally successfully", function() {
        it("as the owner of the NFT", async function() {
          await expect(burnAndSend(user)).to.be.fulfilled;
        });

        it("... and verify that the NFT was burned", async function() {
          expect(await nftCount(user)).equals(0);
        });

        it("... and that the correct Wormhole message was emitted", async function() {
          const {payload} = (await wormhole.getPostedMessage(
            connection, DustBridging.messageAccountAddress(createdNftOutput.mintAddress)
          )).message;

          expect(payload.readUint16LE(0)).to.equal(tokenId);
          expect(Buffer.compare(
            payload.subarray(2),
            Buffer.from(evmRecipient.substring(2), "hex")
          )).to.equal(0);
        });
      });
    });
  }));
});
