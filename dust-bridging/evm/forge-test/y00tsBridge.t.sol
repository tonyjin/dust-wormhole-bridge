// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {MockWormhole} from "wormhole-solidity/MockWormhole.sol";
import {WormholeSimulator, FakeWormholeSimulator} from "wormhole-solidity/WormholeSimulator.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {TestHelpers, TestY00tsV2, TestY00tsV3} from "./TestHelpers.sol";
import "wormhole-solidity/BytesLib.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {MockDust} from "./MockDust.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

contract TestY00tsMigration is TestHelpers {
	using BytesLib for bytes;

	// Wormhole chain IDs for Ethereum and Polygon.
	uint16 constant polygonWormholeChain = 6;
	uint16 constant ethereumWormholeChain = 2;
	uint16 constant solanaWormholeChain = 1;

	uint16 constant maxY00tsSupply = 15_000;
	uint8 constant evmFinality = 201;
	bytes32 constant userAddress = bytes32("user address") >> (12 * 8);
	uint256 constant dustAmountOnMint = 1e18;
	uint256 constant gasTokenAmountOnMint = 1e16;
	uint256 constant wormholeFee = 1e6;
	address constant royaltyReceiver = address(0x1234);
	uint96 constant royaltyFeeNumerator = 250;
	bytes constant baseUri = "https://base.uri.test/";
	string constant name = "testing token name";
	string constant symbol = "testing token symbol";

	//deployed contracts required for testing
	Deployed polygon;
	Deployed ethereum;
	TestY00tsV2 polygonNft;
	TestY00tsV3 ethereumNft;

	function _beforeDeployment(
		Deployed storage deployed,
		uint16 initChainId,
		address acceptedEmitter
	) internal {
		// deploy Wormhole to "Polygon"
		MockWormhole mockWormhole = new MockWormhole({
			initChainId: initChainId,
			initEvmChainId: block.chainid
		});
		deployed.wormhole = mockWormhole;
		deployed.wormholeSimulator = new FakeWormholeSimulator(mockWormhole);
		deployed.wormholeSimulator.setMessageFee(wormholeFee);

		// address(this) receives the dust tokens.
		deployed.dustToken = new MockDust(dustAmountOnMint * 10);

		// only VAAs from this emitter can mint NFTs with our contract (prevents spoofing)
		deployed.acceptedEmitter = toWormholeFormat(acceptedEmitter);
	}

	function _deployPolygon(uint16 initChainId, address acceptedEmitter) internal {
		// deploy prerequisites: wormhole, dust token
		_beforeDeployment(polygon, initChainId, acceptedEmitter);

		// deploy our contract for testing
		TestY00tsV2 nftImplementation = new TestY00tsV2(
			polygon.wormhole,
			polygon.dustToken,
			polygon.acceptedEmitter,
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
		polygonNft = TestY00tsV2(address(proxy));
	}

	function _deployEthereum(uint16 initChainId, address acceptedEmitter) internal {
		// deploy prerequisites: wormhole, dust token
		_beforeDeployment(ethereum, initChainId, acceptedEmitter);

		// deploy our contract for testing
		TestY00tsV3 nftImplementation = new TestY00tsV3(
			ethereum.wormhole,
			ethereum.dustToken,
			ethereum.acceptedEmitter,
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
		ethereumNft = TestY00tsV3(address(proxy));
	}

	function setUp() public {
		// deploy polygon with a random accepted emitter
		_deployPolygon(polygonWormholeChain, makeAddr("solanaEmitter"));

		// deploy ethereum with the polygon emitter
		_deployEthereum(ethereumWormholeChain, address(polygonNft));
	}

	/**
	 * TESTS
	 */

	function testUpgradeY00tsV2() public {
		address newImplementation = address(
			new TestY00tsV2(polygon.wormhole, polygon.dustToken, polygon.acceptedEmitter, baseUri)
		);

		// upgrade the implementation
		TestY00tsV2(address(polygonNft)).upgradeTo(newImplementation);

		assertEq(polygonNft.getImplementation(), newImplementation);
	}

	function testUpgradeY00tsV3() public {
		address newImplementation = address(
			new TestY00tsV3(
				ethereum.wormhole,
				ethereum.dustToken,
				ethereum.acceptedEmitter,
				baseUri
			)
		);

		// upgrade the implementation
		TestY00tsV2(address(ethereumNft)).upgradeTo(newImplementation);

		assertEq(ethereumNft.getImplementation(), newImplementation);
	}

	function testCannotUpgradeY00tsV2OwnerOnly() public {
		address newImplementation = address(
			new TestY00tsV2(polygon.wormhole, polygon.dustToken, polygon.acceptedEmitter, baseUri)
		);

		// upgrade the implementation
		vm.prank(makeAddr("0xdeadbeef"));
		vm.expectRevert("Ownable: caller is not the owner");
		TestY00tsV2(address(polygonNft)).upgradeTo(newImplementation);
	}

	function testCannotUpgradeY00tsV3OwnerOnly() public {
		address newImplementation = address(
			new TestY00tsV3(
				ethereum.wormhole,
				ethereum.dustToken,
				ethereum.acceptedEmitter,
				baseUri
			)
		);

		// upgrade the implementation
		vm.prank(makeAddr("0xdeadbeef"));
		vm.expectRevert("Ownable: caller is not the owner");
		TestY00tsV2(address(ethereumNft)).upgradeTo(newImplementation);
	}

	function testCannotReceiveAndMintOnPolygon(uint16 tokenId) public {
		vm.assume(tokenId < maxY00tsSupply);

		bytes memory mintVaa = craftValidVaa(
			polygon,
			tokenId,
			fromWormholeFormat(userAddress),
			solanaWormholeChain,
			polygon.acceptedEmitter
		);

		(uint256 dustAmount, uint256 gasTokenAmount) = polygonNft.getAmountsOnMint();
		vm.deal(address(this), gasTokenAmount);

		polygon.dustToken.approve(address(polygonNft), dustAmount);

		vm.expectRevert(abi.encodeWithSignature("Deprecated()"));
		polygonNft.receiveAndMint{value: gasTokenAmount}(mintVaa);
	}

	function testBurnAndSendOnPolygon(uint16 tokenId) public {
		vm.assume(tokenId < maxY00tsSupply);

		address recipient = fromWormholeFormat(userAddress);

		// mint an NFT on Polygon
		polygonNft.mintTestOnly(recipient, tokenId);

		// burn and send the NFT on polygon
		vm.prank(address(recipient));
		polygonNft.approve(address(polygonNft), tokenId);
		vm.deal(address(this), wormholeFee);

		Balances memory beforeBal = getBalances(
			polygon,
			polygonNft,
			fromWormholeFormat(userAddress),
			address(this)
		);

		// start recording logs to capture the wormhole message
		vm.recordLogs();
		polygonNft.burnAndSend{value: wormholeFee}(tokenId, recipient);

		// Fetch the emitted VM and parse the payload. The wormhole message will
		// be the second log, since the first log is the `Transfer` event.
		Vm.Log[] memory entries = vm.getRecordedLogs();

		IWormhole.VM memory vm_ = polygon.wormholeSimulator.parseVMFromLogs(entries[2]);
		assertEq(vm_.payload.toUint16(0), tokenId);
		assertEq(vm_.payload.toAddress(BytesLib.uint16Size), recipient);

		Balances memory afterBal = getBalances(
			polygon,
			polygonNft,
			fromWormholeFormat(userAddress),
			address(this)
		);

		assertBalanceCheckOutbound(beforeBal, afterBal, 1);
	}

	function testCannotBurnAndSendOnPolygonBurnNotApproved(uint16 tokenId) public {
		vm.assume(tokenId < maxY00tsSupply);

		address recipient = fromWormholeFormat(userAddress);

		// mint an NFT on Polygon
		polygonNft.mintTestOnly(recipient, tokenId);

		// burn and send the NFT on polygon
		vm.prank(address(recipient));
		vm.deal(address(this), wormholeFee);

		vm.expectRevert();
		// forge is not reverting with data here (bug)
		polygonNft.burnAndSend{value: wormholeFee}(tokenId, recipient);
	}

	function testCannotBurnAndSendOnPolygonLocked(uint16 tokenId) public {
		vm.assume(tokenId < maxY00tsSupply);

		address recipient = fromWormholeFormat(userAddress);

		// mint an NFT on Polygon
		polygonNft.mintTestOnly(recipient, tokenId);

		// burn and send the NFT on polygon
		vm.prank(address(recipient));

		//lock the NFT
		polygonNft.lock(
			tokenId,
			0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
		);

		vm.prank(address(recipient));
		polygonNft.approve(address(polygonNft), tokenId);

		vm.expectRevert("ERC5058: token transfer while locked");
		polygonNft.burnAndSend{value: wormholeFee}(tokenId, recipient);
	}

	function testCannotBurnAndSendOnPolygonRecipientZeroAddress(uint16 tokenId) public {
		vm.assume(tokenId < maxY00tsSupply);

		address recipient = fromWormholeFormat(userAddress);

		// mint an NFT on Polygon
		polygonNft.mintTestOnly(recipient, tokenId);

		vm.prank(address(recipient));
		polygonNft.approve(address(polygonNft), tokenId);

		vm.expectRevert(abi.encodeWithSignature("RecipientZeroAddress()"));
		polygonNft.burnAndSend{value: wormholeFee}(tokenId, address(0));
	}

	function testReceiveAndMintOnEthereum(uint16 tokenId) public {
		vm.assume(tokenId < maxY00tsSupply);

		// craft a VAA sent from the Polygon contract to Ethereum
		bytes memory mintVaa = craftValidVaa(
			ethereum,
			tokenId,
			fromWormholeFormat(userAddress),
			polygonWormholeChain, // emitter chainId
			ethereum.acceptedEmitter
		);

		(uint256 dustAmount, uint256 gasTokenAmount) = ethereumNft.getAmountsOnMint();
		vm.deal(address(this), gasTokenAmount);

		// We need to balance check after dealing the dust token.
		Balances memory beforeBal = getBalances(
			ethereum,
			ethereumNft,
			fromWormholeFormat(userAddress),
			address(this)
		);

		ethereum.dustToken.approve(address(ethereumNft), dustAmount);
		ethereumNft.receiveAndMint{value: gasTokenAmount}(mintVaa);

		Balances memory afterBal = getBalances(
			ethereum,
			ethereumNft,
			fromWormholeFormat(userAddress),
			address(this)
		);

		assertBalanceCheckInbound(beforeBal, afterBal, dustAmount, gasTokenAmount, 1);
	}

	function testCannotReceiveAndMintOnEthereumWrongEmitterAddress() public {
		uint16 tokenId = 5;

		// craft a VAA sent from the Polygon contract to Ethereum
		bytes memory mintVaa = craftValidVaa(
			ethereum,
			tokenId,
			fromWormholeFormat(userAddress),
			polygonWormholeChain, // emitter chainId
			toWormholeFormat(makeAddr("spoofedEmitter"))
		);

		(uint256 dustAmount, uint256 gasTokenAmount) = ethereumNft.getAmountsOnMint();
		vm.deal(address(this), gasTokenAmount);

		ethereum.dustToken.approve(address(ethereumNft), dustAmount);

		vm.expectRevert(abi.encodeWithSignature("WrongEmitterAddress()"));
		ethereumNft.receiveAndMint{value: gasTokenAmount}(mintVaa);
	}

	function testCannotReceiveAndMintOnEthereumWrongEmitterChainId() public {
		uint16 tokenId = 5;

		// craft a VAA sent from the Polygon contract to Ethereum
		bytes memory mintVaa = craftValidVaa(
			ethereum,
			tokenId,
			fromWormholeFormat(userAddress),
			solanaWormholeChain, // invalid emitter chain
			ethereum.acceptedEmitter
		);

		(uint256 dustAmount, uint256 gasTokenAmount) = ethereumNft.getAmountsOnMint();
		vm.deal(address(this), gasTokenAmount);

		ethereum.dustToken.approve(address(ethereumNft), dustAmount);

		vm.expectRevert(abi.encodeWithSignature("WrongEmitterChainId()"));
		ethereumNft.receiveAndMint{value: gasTokenAmount}(mintVaa);
	}

	function testCannotReceiveAndMintOnEthereumAgain() public {
		uint16 tokenId = 5;

		//craft a VAA sent from the Polygon contract to Ethereum
		bytes memory mintVaa = craftValidVaa(
			ethereum,
			tokenId,
			fromWormholeFormat(userAddress),
			polygonWormholeChain, // emitter chainId
			ethereum.acceptedEmitter
		);

		(uint256 dustAmount, uint256 gasTokenAmount) = ethereumNft.getAmountsOnMint();
		vm.deal(address(this), gasTokenAmount);

		ethereum.dustToken.approve(address(ethereumNft), dustAmount);
		ethereumNft.receiveAndMint{value: gasTokenAmount}(mintVaa);

		// try to mint again
		vm.deal(address(this), gasTokenAmount);
		vm.expectRevert(); // forge is not reverting with data here (bug)
		ethereumNft.receiveAndMint{value: gasTokenAmount}(mintVaa);
	}

	function testTokenURIOnEthereum(uint16 tokenId) public {
		vm.assume(tokenId < maxY00tsSupply);

		//craft a VAA sent from the Polygon contract to Ethereum
		bytes memory mintVaa = craftValidVaa(
			ethereum,
			tokenId,
			fromWormholeFormat(userAddress),
			polygonWormholeChain, // emitter chainId
			ethereum.acceptedEmitter
		);

		(uint256 dustAmount, uint256 gasTokenAmount) = ethereumNft.getAmountsOnMint();
		ethereum.dustToken.approve(address(ethereumNft), dustAmount);
		vm.deal(address(this), gasTokenAmount);
		ethereumNft.receiveAndMint{value: gasTokenAmount}(mintVaa);

		string memory uri = ethereumNft.tokenURI(tokenId);
		assertEq(
			bytes(uri),
			bytes(abi.encodePacked(baseUri, Strings.toString(tokenId), string(".json")))
		);
	}
}
