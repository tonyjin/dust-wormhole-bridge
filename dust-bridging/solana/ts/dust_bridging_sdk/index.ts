import {
  Connection,
  PublicKeyInitData,
  PublicKey,
  TransactionInstruction,
  SystemProgram,
  SYSVAR_INSTRUCTIONS_PUBKEY,
} from "@solana/web3.js";
import {TOKEN_PROGRAM_ID} from "@solana/spl-token";
import {Program} from "@project-serum/anchor";
import {Metaplex, NftWithToken} from "@metaplex-foundation/js";
import {PROGRAM_ID as METADATA_ID, TokenStandard} from "@metaplex-foundation/mpl-token-metadata";
import {getPostMessageCpiAccounts} from "@certusone/wormhole-sdk/lib/cjs/solana";
import {CONTRACTS} from "@certusone/wormhole-sdk";
import {ethers} from "ethers";

import {DustBridging as DustBridgingTypes} from "../../target/types/dust_bridging";
import IDL from "../../target/idl/dust_bridging.json";

const WORMHOLE_ID = new PublicKey(CONTRACTS.TESTNET.solana.core);
const PROGRAM_ID = new PublicKey("HhX1RVWgGTLrRSiEiXnu4kToHZhFLpqi5qkErkfFnqEQ");

const SEED_PREFIX_INSTANCE = Buffer.from("instance", "utf-8");
const SEED_PREFIX_MESSAGE = Buffer.from("message", "utf-8");

export class DustBridging {
  private readonly program: Program<DustBridgingTypes>;
  private readonly metaplex: Metaplex;
  readonly collectionMint: PublicKey;

  static readonly programId = PROGRAM_ID;

  static messageAccountAddress(nftMint: PublicKey): PublicKey {
    return PublicKey.findProgramAddressSync(
      [SEED_PREFIX_MESSAGE, nftMint.toBuffer()],
      DustBridging.programId,
    )[0];
  }
  
  static tokenIdFromURI(uri: string): number {
    return parseInt(uri.slice(uri.lastIndexOf("/") + 1, -".json".length));
  }
  
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

  getInstanceAddress(): PublicKey {
    return PublicKey.findProgramAddressSync(
      [SEED_PREFIX_INSTANCE, this.collectionMint.toBuffer()],
      DustBridging.programId,
    )[0];
  }

  async isInitialized(): Promise<boolean> {
    const instance = await this.getInstance(false);
    return instance.isInitialized;
  }

  async isWhitelistEnabled(): Promise<boolean> {
    const instance = await this.getInstance();
    return instance.collectionSize! > 0;
  }

  async isPaused(): Promise<boolean> {
    const instance = await this.getInstance();
    return instance.isPaused!;
  }

  async isNftWhitelisted(nftTokenOrTokenId: PublicKey | number): Promise<boolean> {
    const instance = await this.getInstance();
    if (instance.collectionSize === 0)
      return true;
    const tokenId = (typeof nftTokenOrTokenId === "number"
      ? nftTokenOrTokenId
      : await this.getNftTokenId(nftTokenOrTokenId)
    );
    return DustBridging.isWhitelisted(instance.whitelist!, tokenId);
  }

  async getNftTokenId(nftToken: PublicKey): Promise<number> {
    const nft = await this.getAndCheckNft(nftToken);
    return DustBridging.tokenIdFromURI(nft.uri);
  }

  async getNftAttributes(nftToken: PublicKey) {
    const nft = await this.getAndCheckNft(nftToken, true);
    
    if (!nft.jsonLoaded)
      throw Error("couldn't fetch json metadata of NFT");
    
    return nft.json!.attributes!;
  }

  //must also be signed by the collection's update authority
  async createInitializeInstruction(
    payer: PublicKey, //must be a signer of the transaction
    collectionSize = 0,
  ) : Promise<TransactionInstruction> {
    const instance = await this.getInstance(false);
    if (instance.isInitialized)
      throw Error("DustBridging already initialized for this collection");

    const collectionNft = await this.metaplex.nfts().findByMint({mintAddress: this.collectionMint});

    return this.program.methods.initialize(collectionSize).accounts({
      instance: instance.address,
      payer,
      updateAuthority: collectionNft.updateAuthorityAddress,
      collectionMint: this.collectionMint,
      collectionMeta: collectionNft.metadataAddress,
      systemProgram: SystemProgram.programId,
    }).instruction();
  }

  //must be signed by the update authority (i.e. admin)
  async createSetDelegateInstruction(
    delegate: PublicKey | null,
  ): Promise<TransactionInstruction> {
    const instance = await this.getInstance();
    return this.program.methods.setDelegate(delegate).accounts({
      instance: instance.address,
      updateAuthority: instance.updateAuthority!,
    }).instruction();
  }

  async createSetPausedInstruction(
    authority: PublicKey, //either update_authority or delegate (must sign tx)
    pause: boolean,
  ): Promise<TransactionInstruction> {
    const instance = await this.getInstance();
    if (instance.isPaused === pause)
      throw Error(`DustBridging already ${pause ? "paused" : "unpaused"}`);
    
    return this.program.methods.setPaused(pause).accounts({
      instance: instance.address,
      authority,
    }).instruction();
  }

  //must be signed by the update authority or the delegate
  async createWhitelistBulkInstructions(
    authority: PublicKey,
    whitelist: readonly boolean[]
  ): Promise<readonly TransactionInstruction[]> {
    const instance = await this.getInstance();
    if (instance.collectionSize !== whitelist.length)
      throw Error(
        `whitelist.length (=${whitelist.length}) does not equal` +
        `instance.collectionSize (=${instance.collectionSize})`
      );
    
    //Our transaction size overhead is roughly:
    //  32 bytes for the recent blockhash
    //  32 bytes for the programId
    //  32 bytes for the instance address
    //  32 bytes for the authority
    //  64 bytes for the signature
    //  a couple of bytes for all the compact arrays etc.
    //So give or take we have ~1000 bytes give or take for the whitelist argument.
    // ... and as it turned out after some testing about 990 bytes is the most we can squeeze in
    const whitelistBytes = 990;
    const range = (size: number) => [...Array(size).keys()];
    const chunkSize = whitelistBytes * 8;
    const chunks = Math.ceil(whitelist.length / chunkSize);
    return Promise.all(range(chunks).map(chunk => {
      const whitelistSlice = whitelist.slice(chunk * chunkSize, (chunk + 1) * chunkSize);
      const bytes = range(Math.ceil(whitelistSlice.length/8)).map(byte => {
        let byteValue = 0;
        for (let bit = 0; bit < 8 && byte * 8 + bit < whitelistSlice.length; ++bit)
          byteValue += whitelistSlice[byte * 8 + bit] ? 1 << bit : 0;
        return byteValue;
      });

      return this.program.methods.whitelistBulk(chunk*whitelistBytes, Buffer.from(bytes)).accounts({
        instance: instance.address,
        authority,
      }).instruction();
    }));
  }

  async createWhitelistInstruction(
    authority: PublicKey, //either update_authority or delegate (must sign tx)
    tokenIds: number | readonly number[]
  ) : Promise<TransactionInstruction> {
    const instance = await this.getInstance();
    const tokenIdsArray = Array.isArray(tokenIds) ? tokenIds : [tokenIds];
    if (tokenIdsArray.some(id => id < 0 || id >= instance.collectionSize!))
      throw Error("Invalid token ID");
    return this.program.methods.whitelist(tokenIdsArray).accounts({
      instance: instance.address,
      authority,
    }).instruction();
  }

  //must also be signed by the nft's owner
  async createSendAndBurnInstruction(
    payer: PublicKey, //must be a signer of the transaction
    nftToken: PublicKey,
    evmRecipient: string,
    batchId = 1,
  ) : Promise<TransactionInstruction> {
    if (!ethers.utils.isAddress(evmRecipient))
      throw Error("Invalid EVM recipient address");
    
    const instance = await this.getInstance();
    if (instance.isPaused)
      throw Error("DustBridging is paused");
    
    const nft = await this.getAndCheckNft(nftToken) as NftWithToken;

    if (instance.collectionSize! > 0) {
      const tokenId = DustBridging.tokenIdFromURI(nft.uri);
      if (!DustBridging.isWhitelisted(instance.whitelist!, tokenId))
        throw Error(`NFT with tokenId ${tokenId} not yet whitelisted`);
    }
    
    const evmRecipientArrayified = ethers.utils.zeroPad(evmRecipient, 20);
    //For normal NFTs, we can pass in an arbitrary mutable account for the token record account
    //  since it will be ignored by the DustBridging program anyway and it will substitute it with
    //  the metadata program id which is the canonical solution according to the documentation - see
    //  https://github.com/metaplex-foundation/metaplex-program-library/blob/master/token-metadata/program/ProgrammableNFTGuide.md#%EF%B8%8F--positional-optional-accounts
    //So for our purposes we simply reuse the nftToken account.
    const tokenRecord = 
      nft.tokenStandard === TokenStandard.ProgrammableNonFungible
      ? this.metaplex.nfts().pdas().tokenRecord({mint: nft.mint.address, token: nftToken})
      : nftToken; //will be ignored, but must be writeable because of Anchor checks
    return this.program.methods.burnAndSend(batchId, evmRecipientArrayified).accounts({
      instance: instance.address,
      payer,
      nftOwner: nft.token.ownerAddress,
      nftToken,
      nftMint: nft.mint.address,
      nftMeta: nft.metadataAddress,
      nftMasterEdition: nft.edition.address,
      collectionMeta: this.metaplex.nfts().pdas().metadata({mint: this.collectionMint}),
      tokenRecord,
      wormholeMessage: DustBridging.messageAccountAddress(nft.mint.address),
      metadataProgram: METADATA_ID,
      tokenProgram: TOKEN_PROGRAM_ID,
      sysvarInstructions: SYSVAR_INSTRUCTIONS_PUBKEY,
      ...this.wormholeCpiAccounts(instance.address),
    }).instruction();
  }

  // ----------------------------------------- private -----------------------------------------

  private static isWhitelisted(whitelist: Uint8Array, tokenId: number): boolean {
    return (whitelist[Math.floor(tokenId/8)] & (1 << (tokenId % 8))) > 0;
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

  private async getInstance(mustBeInitialized = true) {
    const address = this.getInstanceAddress();
    const data = await this.program.account.instance.fetchNullable(address);
    const isInitialized = !!data && data.collectionMint.equals(this.collectionMint);
    if (mustBeInitialized && !isInitialized)
      throw Error("DustBridging not initialized for this collection");
    return {address, isInitialized,...data};
  }

  private async getAndCheckNft(nftToken: PublicKey, loadJsonMetadata = false) {
    const nft = await this.metaplex.nfts().findByToken({token: nftToken, loadJsonMetadata});

    if (
      !nft.collection ||
      !nft.collection.verified ||
      !nft.collection.address.equals(this.collectionMint)
    )
      throw Error("NFT is not part of this collection");
    
    return nft;
  }
}
