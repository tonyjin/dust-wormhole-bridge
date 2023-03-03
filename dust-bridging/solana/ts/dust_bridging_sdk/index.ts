import {
  Connection,
  PublicKeyInitData,
  PublicKey,
  TransactionInstruction,
  SystemProgram,
} from "@solana/web3.js";
import {TOKEN_PROGRAM_ID} from "@solana/spl-token";
import {Program} from "@project-serum/anchor";
import {Metaplex, NftWithToken} from "@metaplex-foundation/js";
import {PROGRAM_ID as METADATA_ID} from "@metaplex-foundation/mpl-token-metadata";
import {getPostMessageCpiAccounts} from "@certusone/wormhole-sdk/lib/cjs/solana";
import {CONTRACTS} from "@certusone/wormhole-sdk";
import {ethers} from "ethers";

import {DustBridging as DustBridgingTypes} from "../../target/types/dust_bridging";
import IDL from "../../target/idl/dust_bridging.json";

const WORMHOLE_ID = new PublicKey(CONTRACTS.MAINNET.solana.core);
const PROGRAM_ID = new PublicKey("DxPDCoSdg5DWqE89uKh6qpsergPX8nd7DLH5EmyWY5uq");

const SEED_PREFIX_INSTANCE = Buffer.from("instance", "utf-8");
const SEED_PREFIX_MESSAGE = Buffer.from("message", "utf-8");

export class DustBridging {
  private readonly program: Program<DustBridgingTypes>;
  private readonly metaplex: Metaplex;
  readonly collectionMint: PublicKey;

  static readonly programId = PROGRAM_ID;
  
  constructor(
    connection: Connection,
    collectionMint: PublicKeyInitData,
  ) {
    //we don't pass a cluster argument but let metaplex figure it out from the connection
    this.metaplex = new Metaplex(connection);
    this.program = new Program<DustBridgingTypes>(IDL as any, DustBridging.programId, {connection});
    this.collectionMint = new PublicKey(collectionMint);
    if (this.collectionMint.equals(PublicKey.default))
      throw Error("Collection mint can't be zero address");
  }

  async isInitialized(): Promise<boolean> {
    const instanceData =
      await this.program.account.instance.fetchNullable(this.instanceAddress());
    return !!instanceData && instanceData.collectionMint.equals(this.collectionMint);
  }

  async createInitializeInstruction(payer: PublicKey) : Promise<TransactionInstruction> {
    if (await this.isInitialized())
      throw Error("DustBridging already initialized for this collection");

    const collectionNft = await this.metaplex.nfts().findByMint({mintAddress: this.collectionMint});

    return this.program.methods.initialize().accounts({
      instance: this.instanceAddress(),
      payer,
      admin: collectionNft.updateAuthorityAddress,
      collectionMint: this.collectionMint,
      collectionMeta: collectionNft.metadataAddress,
      systemProgram: SystemProgram.programId,
    }).instruction();
  }

  async getNftAttributes(nftToken: PublicKey) {
    const nft = await this.getAndCheckNft(nftToken);
    
    if (!nft.jsonLoaded)
      throw Error("couldn't fetch json metadata of NFT");
    
    return nft.json!.attributes!;
  }

  async createSendAndBurnInstruction(
    payer: PublicKey,
    nftToken: PublicKey,
    evmRecipient: string,
    batchId = 1,
  ) : Promise<TransactionInstruction> {
    if (!await this.isInitialized())
      throw Error("DustBridging not initialized for this collection");
    
    if (!ethers.utils.isAddress(evmRecipient))
      throw Error("Invalid EVM recipient address");
    
    const nft = await this.getAndCheckNft(nftToken);
    
    //TODO check for transcended and t00b claimed attributes?
    
    const instance = this.instanceAddress();
    const evmRecipientArrayified = ethers.utils.zeroPad(evmRecipient, 20);

    return this.program.methods.burnAndSend(batchId, evmRecipientArrayified).accounts({
      instance,
      payer,
      nftOwner: nft.token.ownerAddress,
      nftToken,
      nftMint: nft.mint.address,
      nftMeta: nft.metadataAddress,
      nftMasteredition: nft.edition.address,
      collectionMeta: this.metaplex.nfts().pdas().metadata({mint: this.collectionMint}),
      wormholeMessage: this.messageAccount(nft.mint.address),
      metadataProgram: METADATA_ID,
      tokenProgram: TOKEN_PROGRAM_ID,
      ...this.wormholeCpiAccounts(instance),
    }).instruction();
  }

  messageAccount(nftMint: PublicKey): PublicKey {
    return PublicKey.findProgramAddressSync(
      [SEED_PREFIX_MESSAGE, nftMint.toBuffer()],
      DustBridging.programId,
    )[0];
  }

  private wormholeCpiAccounts(emitter: PublicKey) {
    //workaround:
    //We'd like to get all the accounts/keys we need from getPostMessageCpiAccounts() but the SDK
    // (not the actual core bridge program!) assumes that there is 1:1 relationship between
    // programs and emitters and thus creates a singular emitter account using the fixed seed
    // "emitter".
    //In turn, it then derives the sequence account from that emitter account. Since we have no way
    // to substitute our own emitter address, we therefore have to rederive the sequence account
    // ourselves, hardcoding the sequence seed (which ought to be abstracted away by the SDK)
    // ourselves.
    const unused = PublicKey.default;
    const {wormholeBridge, wormholeFeeCollector, rent, clock, systemProgram} =
      getPostMessageCpiAccounts(DustBridging.programId, WORMHOLE_ID, unused, unused);
    
    const SEED_PREFIX_SEQUENCE = Buffer.from("Sequence", "utf-8");
    const wormholeSequence =
      PublicKey.findProgramAddressSync(
        [SEED_PREFIX_SEQUENCE, emitter.toBuffer()],
        WORMHOLE_ID
      )[0];
    
    return {
      wormholeBridge,
      wormholeFeeCollector,
      wormholeSequence,
      wormholeProgram: WORMHOLE_ID,
      rent,
      clock,
      systemProgram,
    };
  }

  private instanceAddress(): PublicKey {
    return PublicKey.findProgramAddressSync(
      [SEED_PREFIX_INSTANCE, this.collectionMint.toBuffer()],
      DustBridging.programId
    )[0];
  }

  private async getAndCheckNft(nftToken: PublicKey) {
    const nft = await this.metaplex.nfts().findByToken({token: nftToken}) as NftWithToken;

    if (
      !nft.collection ||
      !nft.collection.verified ||
      !nft.collection.address.equals(this.collectionMint)
    )
      throw Error("NFT is not part of this collection");
    
    return nft;
  }
}
