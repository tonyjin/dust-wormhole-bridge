// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {y00ts} from "../src/nft/y00ts.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "wormhole-solidity/BytesLib.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ContractScript is Script {
    using BytesLib for bytes;
    bytes32 constant minterAddress = 0x3a5a8772eeab57012f4a030a584cd8efb87a8996e89bb2d7999ad9dea97a0a4e;
    uint256 constant dustAmountOnMint = 0 ether;
    uint256 constant gasTokenAmountOnMint = 0 ether;
    address constant royaltyReceiver = 0xC3920d13F00Dc03DE66FA7111600cD2635564147;
    uint96 constant royaltyFeeNumerator = 333;
    bytes constant baseUri = "https://metadata.y00ts.com/y/";
    string constant name = "y00ts";
    string constant symbol = "y00t";

    IWormhole wormhole = IWormhole(0x0CBE91CF822c73C2315FB05100C2F714765d5c20);
    y00ts nft;
    IERC20 dustToken = IERC20(0xAD290867AEFFA008cDC182dC1092bFB378340Ba8);

    function deployContract() public {
        //Deploy our contract for testing
        y00ts nftImplementation = new y00ts(
                wormhole,
                dustToken,
                minterAddress,
                baseUri
            );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(nftImplementation),
            abi.encodeCall(
                nftImplementation.initialize,
                (
                    name,
                    symbol,
                    dustAmountOnMint,
                    gasTokenAmountOnMint,
                    royaltyReceiver,
                    royaltyFeeNumerator
                )
            )
        );
        nft = y00ts(address(proxy));
    }

    function upgradeContract() public {
        // Get deployed contract from proxy
        nft = y00ts(0x2aC3ff0D83e936b65933f33c7A5D1dFFf8725645);
        // nft = y00ts(0xaED7623ED5F62C238CEE62D36569A40cCdCcC493);

        // Build new implementation
        y00ts newNftImplementation = new y00ts(
                wormhole,
                dustToken,
                minterAddress,
                baseUri
            );
        // Upgrade
        nft.upgradeTo(
            address(newNftImplementation)
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // TokenBridgeRelayer.sol
        console.log("Deploying contract");
        upgradeContract();

        // finished
        vm.stopBroadcast();
    }
}
