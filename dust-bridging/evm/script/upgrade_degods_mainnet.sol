// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeGods} from "../src/nft/DeGods.sol";
import {DeGodsV2} from "../src/nft/DeGodsV2.sol";

contract UpgradeDeGodsMainnetScript is Script {
	address constant proxyAddress = 0x8821BeE2ba0dF28761AffF119D66390D594CD280;
	address constant wormholeAddress = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;
	address constant dustAddress = 0xB5b1b659dA79A2507C27AaD509f15B4874EDc0Cc;
	bytes32 constant emitterAddress =
		0xe298490ef8d01f56d0460c07e60e753040fe2ca53f56d39925df0f654cd995bd;
	bytes constant degodsBaseUri = "https://metadata.degods.com/g/";

	function upgrade() public {
		DeGods(proxyAddress).upgradeTo(
			address(
				new DeGodsV2(
					IWormhole(wormholeAddress),
					IERC20(dustAddress),
					emitterAddress,
					degodsBaseUri
				)
			)
		);
	}

	function run() public {
		vm.startBroadcast();

		console.log("Upgrading DeGods mainnet");
		upgrade();

		vm.stopBroadcast();
	}
}
