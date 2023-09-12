// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeGods} from "../src/nft/DeGods.sol";
import {DeGodsV2} from "../src/nft/DeGodsV2.sol";

contract UpgradeDeGodsDevnetScript is Script {
	address constant proxyAddress = 0xD1170333F5a7Daa4f1169Df30518C03074A06c36;
	address constant wormholeAddress = 0x706abc4E45D419950511e474C7B9Ed348A4a716c;
	address constant dustAddress = 0xAD290867AEFFA008cDC182dC1092bFB378340Ba8;
	bytes32 constant emitterAddress =
		0x34a23b4d22d5b0c4b851498188c27d94fe0f90d6258705db3c6975835b75beb8;
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

		console.log("Upgrading DeGods devnet");
		upgrade();

		vm.stopBroadcast();
	}
}
