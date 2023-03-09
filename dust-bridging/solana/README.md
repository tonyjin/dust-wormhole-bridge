# Purpose

This project implements a Solana program called DustBridging which facilitates the bridging of Dust's [DeGods](https://degods.com/) and [y00ts](https://www.y00ts.com/) NFT collections from Solana to Ethereum and Polygon respectively using Wormhole for the cross-chain step. It also provides a TypeScript SDK to interact with the on-chain program.

# Design Summary

DustBridging is a program on the Solana blockchain written with the [Anchor framework](https://www.anchor-lang.com/).

## Burn and Send

Its most important instruction is called `burnAndSend` which burns a provided NFT and emits a Wormhole message, thus initiating the bridging process.

In more detail, when invoked, it will:
1. Ensure that all its prerequisites are fulfilled, namely that
  * the NFT belongs to the collection of the given instance of DustBridging
  * the instance isn't paused
  * the NFT is whitelisted (if whitelisting is enabled)
2. Additionally it relies on [Metaplex's new Burn instruction](https://github.com/metaplex-foundation/metaplex-program-library/blob/master/token-metadata/program/src/instruction/mod.rs#L504-L545) to ensure that:
  * the NFT is a [verified item of the collection](https://docs.metaplex.com/programs/token-metadata/instructions#verify-a-collection-item)
  * the transaction was signed by the owner of the NFT or an authorized delegate and is hence authorized to burn the NFT
  * the NFT is the [master edition](https://docs.metaplex.com/programs/token-metadata/accounts#master-edition) and [not some other edition](https://docs.metaplex.com/programs/token-metadata/accounts#edition)
  * that a coherent set of Metaplex accounts was provided
3. [Burn](https://github.com/metaplex-foundation/metaplex-program-library/blob/master/token-metadata/program/src/instruction/mod.rs#L504-L545) the NFT.
4. Emit a Wormhole message which serves as proof for the burning of the NFT and which can be submitted on the target EVM chain to mint its equivalent there. The Wormhole message contains a tokenId (2 bytes) (taken from the URI of the metadata field (see example NFTs at the bottom of this readme)) and an EVM address (20 bytes) of the designated recipient's wallet.

## Admin Instructions

The program can be instantiated multiple times but only once per [Collection NFT](https://docs.metaplex.com/programs/token-metadata/certified-collections#collection-nfts) and only by the [UpdateAuthority](https://docs.metaplex.com/programs/token-metadata/accounts#metadata) of that collection (who can then be thought of as the admin of that program instance) by using the `initialize` instruction.

DustBridging supports:
* optional whitelisting -- when enabled, only NFTs whose tokenId has been whitelisted can be burned by users
* delegation -- delegating admin functionality to a separate delegate account
* pausing -- so `burnAndSend` instructions will fail, even if all other prerequisites are met

Passing a collection size argument of 0 to the initialize instruction disables the whitelist, any other value enables its.

## SDK

The TypeScript SDK can be found in ./ts/dust_bridging_sdk.

## Remarks

* Token ids are always 1 less than the token number (the number in the token's name).
* Both NFT collections currently use the current [Non-Fungible Standard](https://docs.metaplex.com/programs/token-metadata/token-standard#the-non-fungible-standard), however there is a new [Programmable Non-Fungible Standard](https://docs.metaplex.com/programs/token-metadata/token-standard#the-programmable-non-fungible-standard) in development, which has been introduced as a means to enforce payment of royalty fees to the NFT's creator upon NFT sales. Since Dust intends to convert both collections to the new pNFT standard within the given [upgrade window for existing assets](https://github.com/metaplex-foundation/mip/blob/main/mip-1.md#upgrade-window), DustBridging must use [the new, backwards compatible instructions of the Metaplex token metadata program](https://github.com/metaplex-foundation/metaplex-program-library/blob/ecb0dcd82274b8e70dacd171e1a553b6f6dab5c6/token-metadata/program/src/instruction/mod.rs#L502).
* Neither collection ought to have any print editions.

# Building

Install GNU make if you don't have it already and follow the [Anchor installation](https://www.anchor-lang.com/docs/installation) steps to set up the prereqs.

Then build via:
```
make build
```

# Testing

You can run Rust's clippy for the DustBridging program (triggers additional compilation because it is built normally instead of via build-bpf) as well as the included TypeScript tests via
```
make test
```

# Resources

## Anchor
* [Anchor framework](https://www.anchor-lang.com/docs/high-level-overview)

## Wormhole
* [general doc](https://book.wormhole.com/)
* [wormhole-scaffolding](https://github.com/wormhole-foundation/wormhole-scaffolding) - served as the jumping-off point for this repo

## Metaplex
* [general doc (not upated for pNFTs yet!)](https://docs.metaplex.com/)
* [pNFT standard MIP](https://github.com/metaplex-foundation/mip/blob/main/mip-1.md)
* [pNFT dev guide](https://github.com/metaplex-foundation/metaplex-program-library/blob/master/token-metadata/program/ProgrammableNFTGuide.md)
* [js npm package](https://www.npmjs.com/package/@metaplex-foundation/js)
* [mpl-token-metadata npm package](https://www.npmjs.com/package/@metaplex-foundation/mpl-token-metadata)
  * the new Verify instruction for pNFTs hadn't made it into the general js package yet at the time writing

## Dust Collections

### DeGods Collection
Size: 10,000

Will use whitelisting to prevent bridging of DeGods that haven't been transcended or claimed their y00ts (see attributes in off-chain metadata).

* [Explorer](https://app.degods.com/explorer)
* [Collection NFT](https://solscan.io/token/6XxjKYFbcndh2gDcsUrmZgVEsoDxXMnfsaGY6fpTJzNr#metadata)

Examples
* [#3251 (transcended)](https://solscan.io/token/6CCprsgJT4nxBMSitGathXcLshDTL3BE4LcJXvSFwoe2#metadata)
  * [off-chain metadata - tokenId 3250](https://metadata.degods.com/g/3250.json)
  * [MagicEden](https://magiceden.io/item-details/6CCprsgJT4nxBMSitGathXcLshDTL3BE4LcJXvSFwoe2)
  * [SolanaFM](https://solana.fm/address/6CCprsgJT4nxBMSitGathXcLshDTL3BE4LcJXvSFwoe2?cluster=mainnet-solanafmbeta)
* [#8628 (not transcended)](https://solscan.io/token/2973mQSn8ywhXn5swZ9xTWPp1xuygwjWjLijhL7qRYTW#metadata)
  * [off-chain metadata - tokenId 8627](https://metadata.degods.com/g/8627.json)

### y00ts Collection
Size: 15,000

Will not require whitelisting.

* [Explorer](https://www.y00ts.com/explorer)
* [Collection NFT](https://solscan.io/token/4mKSoDDqApmF1DqXvVTSL6tu2zixrSSNjqMxUnwvVzy2#metadata)

Example
* [#68 y00t](https://solscan.io/token/DNWfNYtD91zZThpoM9mewhtyuWKsCSy4MXYLa5ZD37D2#metadata)
  * [off-chain metadata - tokenId 67](https://metadata.y00ts.com/y/67.json)
