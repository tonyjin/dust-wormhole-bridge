// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {DeGods} from "../src/nft/DeGods.sol";
import "wormhole-solidity/BytesLib.sol";

contract ContractScript is Script {
    using BytesLib for bytes;
    DeGods nft = DeGods(0x8821BeE2ba0dF28761AffF119D66390D594CD280);
    bytes constant vaa = hex"01000000000100a36d071cdd6099319b3f2accf18c0bda6e929171542955dbafc3c7da8147f33108a618aaf67af619240e36b04b6a634face027cbb5865160861731c177d8812c0064151b730000000000013a5a8772eeab57012f4a030a584cd8efb87a8996e89bb2d7999ad9dea97a0a4e000000000000001d200143e854ca3612df6d519cc5da425e1452753c5a60d1";

    function mintFromVaa() public {
        nft.receiveAndMint(
          vaa
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // TokenBridgeRelayer.sol
        console.log("Minting from VAA...");
        mintFromVaa();

        // finished
        vm.stopBroadcast();
    }
}
