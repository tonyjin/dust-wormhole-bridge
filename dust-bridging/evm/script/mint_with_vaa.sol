// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {DeBridge} from "../src/nft/DeBridge.sol";
import "wormhole-solidity/BytesLib.sol";

contract ContractScript is Script {
    using BytesLib for bytes;
    DeBridge nft = DeBridge(0x2aC3ff0D83e936b65933f33c7A5D1dFFf8725645);
    bytes constant vaa = hex"0100000000010035852b297ae08f9ac3a3529c21ca88b61b46f4fa772639b04f7a216cbe3ac1af3c489da5b2d6f0b479f85c2b9189f372e0b2f4445e9f3ed8e7b698540b0e388600641203aa0000000100013a5a8772eeab57012f4a030a584cd8efb87a8996e89bb2d7999ad9dea97a0a4e0000000000000003200035c3920d13f00dc03de66fa7111600cd2635564147";

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
