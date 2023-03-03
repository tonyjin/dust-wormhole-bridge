// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {DefaultOperatorFiltererUpgradeable} from "./DefaultOperatorFiltererUpgradeable.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {BytesLib} from "wormhole-solidity/BytesLib.sol";

/**
 * @title  WormholeERC721Upgradeable
 * @notice ERC721 that mints tokens based on VAAs.
 *         This contract is configured to use the DefaultOperatorFilterer, which automatically registers the
 *         token and subscribes it to OpenSea's curated filters.
 *         Adding the onlyAllowedOperator modifier to the transferFrom and both safeTransferFrom methods ensures that
 *         the msg.sender (operator) is allowed by the OperatorFilterRegistry.
 */
contract WormholeERC721Upgradeable is
    ERC721Upgradeable,
    ERC2981Upgradeable,
    DefaultOperatorFiltererUpgradeable,
    OwnableUpgradeable
{
    using BytesLib for bytes;

    // Core layer Wormhole contract.
    IWormhole immutable wormhole;
    // Contract address that can mint NFTs. The mint VAA should have this as the emitter address.
    bytes32 immutable minterAddress;
    // Common URI for all NFTs handled by this contract.
    bytes32 immutable baseURI;
    // uint8 immutable baseURISize;
    // Wormhole chain id that valid vaas must have.
    // We only support Solana for now.
    uint16 constant sourceChainId = 1;
    // Dictionary of VAA hash => flag that indicates the VAA was already processed by the contract if true
    mapping(bytes32 => bool) processedVaas;

    error WrongEmitterChainId();
    error WrongEmitterAddress();
    error FailedVaaParseAndVerification(string reason);
    error VaaAlreadyProcessed();
    error InvalidMessageLength();

    constructor(IWormhole initWormhole, bytes32 initMinterAddress, bytes32 initBaseURI) {
        wormhole = initWormhole;
        minterAddress = initMinterAddress;
        baseURI = initBaseURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return string.concat(super.tokenURI(tokenId), ".json");
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return string(abi.encodePacked(baseURI));
    }

    /**
     * @dev Initializes the upgradeable contract.
     */
    function initialize(string memory name, string memory symbol) public initializer {
        __ERC721_init(name, symbol);
        __ERC2981_init();
        __Ownable_init();
        __DefaultOperatorFilterer_init();
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     *      In this example the added modifier ensures that the operator is allowed by the OperatorFilterRegistry.
     */
    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    /**
     * @dev See {IERC721-approve}.
     *      In this example the added modifier ensures that the operator is allowed by the OperatorFilterRegistry.
     */
    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    /**
     * @dev See {IERC721-transferFrom}.
     *      In this example the added modifier ensures that the operator is allowed by the OperatorFilterRegistry.
     */
    function transferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     *      In this example the added modifier ensures that the operator is allowed by the OperatorFilterRegistry.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     *      In this example the added modifier ensures that the operator is allowed by the OperatorFilterRegistry.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * Mints an NFT based on a properly authorized VAA.
     */
    function mintFromVaa(bytes calldata vaa) external {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(vaa);
        if (!valid) {
            revert FailedVaaParseAndVerification(reason);
        }

        if (vm.emitterChainId != sourceChainId) {
            revert WrongEmitterChainId();
        }

        if (vm.emitterAddress != minterAddress) {
            revert WrongEmitterAddress();
        }

        if (processedVaas[vm.hash]) {
            revert VaaAlreadyProcessed();
        }
        processedVaas[vm.hash] = true;

        (uint256 tokenId, address evmRecipient) = parsePayload(vm.payload);
        _safeMint(evmRecipient, tokenId);
    }

    function parsePayload(bytes memory message) pure internal returns (uint256 tokenId, address evmRecipient) {
        if (message.length != BytesLib.uint16Size + BytesLib.addressSize) {
            revert InvalidMessageLength();
        }

        tokenId = message.toUint16(0);
        evmRecipient = message.toAddress(BytesLib.uint16Size);
    }
}
