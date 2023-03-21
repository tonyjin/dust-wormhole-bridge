# Purpose

This repo contains all the necessary components to facilitate bridging of DeLabs's [DeGods](https://degods.com/) and [y00ts](https://www.y00ts.com/) NFT collection from Solana to Ethereum and Polygon respectively, namely:
* A [Solana program](https://docs.solana.com/terminology#program) which burns NFTs and publishes [Wormhole message](https://book.wormhole.com/wormhole/3_coreLayerContracts.html#sending)s, thus initiating the bridging process.
* A relayer engine which observes the [Wormhole Guardian Network](https://book.wormhole.com/wormhole/5_guardianNetwork.html), picks up [VAA](https://book.wormhole.com/wormhole/4_vaa.html)s corresponding to these messages, and submits them to ...
* An EVM NFT token contract deployed to both target chains which takes such VAAs and mints the equivalent NFTs on that chain, thus concluding the bridging process.

# Component Interfaces

## Message Format

The Wormhole message published upon burning an NFT on Solana contains the NFT's token id (number in the token's metadata URI - see examples below) followed by the EVM recipient address provided by the NFT's owner when invoking the Solana program's `burnAndSend` instruction.

Format (both big endian byte order):
* token_id - 2 bytes, uint16
* evm recipient - 20 bytes, evm address

So burning token with id 1 and naming `0xa1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0` as the recipient yields the message:
`0x0001a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0`

## Emitter Address

Every message published via Wormhole contains an [emitter address](https://book.wormhole.com/wormhole/4_vaa.html#body) which allows a receiver to check that the message was actually published by the expected entity and not spoofed by somebody else.

The Solana program is initiated separately for each NFT collection and uses a separate Wormhole emitter for each instance. So for both the DeGods and y00ts collection, their respective emitters (queriable by the provided SDK) must be specified when instantiating their EVM NFT token contracts on their respective target chains.

## Token Airdrop

Upon relaying, besides minting the bridged NFT itself, the EVM NFT token contract also forwards a configurable amount of gas tokens (EVM or MATIC) as well as DUST tokens to the specified recipient of the NFT. The relayer wallet must ensure to include this amount of gas tokens in the transaction when relaying it and to approve a sufficient [allowance](https://docs.openzeppelin.com/contracts/2.x/api/token/erc20#IERC20-allowance-address-address-) for the smart contract to facilitate the DUST transfer.

# Testing

## Fetching VAAs

VAAs from the Solana devnet can be retrieved via the following endpoint:
https://wormhole-v2-testnet-api.certus.one/v1/signed_vaa/1/<emitterAddressInHex(32bytes)>/<sequenceNumber>

So given an emitter address of e.g. `4vniELt2jFdsCHCKRdxTSe5LpLFar7SZaakCYtMjbDNm`, the base58 decoded hex representation is `3a5a8772eeab57012f4a030a584cd8efb87a8996e89bb2d7999ad9dea97a0a4e` and thus to look up the message with Wormhole sequence number 1, one can query this endpoint like so:
https://wormhole-v2-testnet-api.certus.one/v1/signed_vaa/1/3a5a8772eeab57012f4a030a584cd8efb87a8996e89bb2d7999ad9dea97a0a4e/1

## Parsing VAAs

To parse a VAA thus retrieved one can use the following dev tool:
https://vaa.dev/

# DeLabs Collections

* Token ids (the number in the token's metadata URI) are always 1 less than the token number (the number in the token's name).

## DeGods Collection
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

## y00ts Collection
Size: 15,000

Will not require whitelisting.

* [Explorer](https://www.y00ts.com/explorer)
* [Collection NFT](https://solscan.io/token/4mKSoDDqApmF1DqXvVTSL6tu2zixrSSNjqMxUnwvVzy2#metadata)

Example
* [#68 y00t](https://solscan.io/token/DNWfNYtD91zZThpoM9mewhtyuWKsCSy4MXYLa5ZD37D2#metadata)
  * [off-chain metadata - tokenId 67](https://metadata.y00ts.com/y/67.json)