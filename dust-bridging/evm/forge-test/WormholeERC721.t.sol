// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {WormholeERC721Upgradeable} from "../src/nft/WormholeERC721Upgradeable.sol";
import {MockWormhole} from "wormhole-solidity/MockWormhole.sol";
import {WormholeSimulator, FakeWormholeSimulator} from "wormhole-solidity/WormholeSimulator.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import "wormhole-solidity/BytesLib.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

contract TestCoreRelayer is Test {
    using BytesLib for bytes;

    // Ethereum has wormhole chain id 2
    uint16 constant wormholeChainId = 2;
    // Solana has wormhole chain id 1
    uint16 constant sourceChainId = 1;
    bytes32 constant minterAddress = bytes32("minter address") >> 12 * 8;
    bytes32 constant userAddress = bytes32("user address") >> 12 * 8;
    bytes32 constant baseURI = "testing base uri";
    string constant name = "testing token name";
    string constant symbol = "testing token symbol";

    IWormhole wormhole;
    WormholeSimulator wormholeSimulator;
    WormholeERC721Upgradeable nft;

    function setUp() public {
        // deploy Wormhole
        MockWormhole mockWormhole = new MockWormhole({
            initChainId: wormholeChainId,
            initEvmChainId: block.chainid
        });
        wormhole = mockWormhole;

        wormholeSimulator = new FakeWormholeSimulator(
            mockWormhole
        );
        wormholeSimulator.setMessageFee(100);
        WormholeERC721Upgradeable nftImplementation = new WormholeERC721Upgradeable(wormhole, minterAddress, baseURI);
        ERC1967Proxy proxy = new ERC1967Proxy(address(nftImplementation), abi.encodeCall(nftImplementation.initialize, (name, symbol)));
        nft = WormholeERC721Upgradeable(address(proxy));
    }

    /**
     * TESTS
     */

    function toWormholeFormat(address addr) internal pure returns (bytes32 whFormat) {
        return bytes32(uint256(uint160(addr)));
    }

    function fromWormholeFormat(bytes32 whFormatAddress) internal pure returns (address addr) {
        return address(uint160(uint256(whFormatAddress)));
    }

    function craftValidVaa(uint16 tokenId, address evmRecipient) internal returns (bytes memory) {
        IWormhole.VM memory vaa = IWormhole.VM({
            version: 1,
            timestamp: 0,
            nonce: 0,
            emitterChainId: sourceChainId,
            emitterAddress: minterAddress,
            sequence: 0,
            consistencyLevel: 1,
            payload: abi.encodePacked(tokenId, evmRecipient),
            guardianSetIndex: wormhole.getCurrentGuardianSetIndex(),
            signatures: new IWormhole.Signature[](0),
            hash: 0x00
        });

        return wormholeSimulator.encodeAndSignMessage(vaa);
    }

    function testTokenURI() public {
        // TODO: write this as a unit test, i.e. independently from mint mechanism
        // Beware, modifying `tokenId` here without updating the assert will invalidate the test.
        uint16 tokenId = 5;
        bytes memory mintVaa = craftValidVaa(tokenId, fromWormholeFormat(userAddress));
        nft.mintFromVaa(mintVaa);
        string memory uri = nft.tokenURI(tokenId);
        assertEq(bytes(uri), bytes("testing base uri5.json"));
    }

}