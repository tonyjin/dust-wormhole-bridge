// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {BytesLib} from "wormhole-solidity/BytesLib.sol";
import {DummyERC721EnumerableUpgradeable} from "./DummyERC721EnumerableUpgradeable.sol";

/**
 * @title  DeBridge
 * @notice ERC721 that mints tokens based on VAAs.
 */
contract y00ts is
	UUPSUpgradeable,
	DummyERC721EnumerableUpgradeable,
	ERC2981Upgradeable,
	Ownable2StepUpgradeable
{
	using BytesLib for bytes;
	using SafeERC20 for IERC20;

	// Wormhole chain id that valid vaas must have -- must be Solana.
	uint16 constant SOURCE_CHAIN_ID = 1;
	// Finality for outbound messages from Polygon. An upgrade is required
	// to update this value.
	// - 201 is finalized
	// - 200 is not finalized
	uint8 constant FINALITY = 201;

	// -- immutable members (baked into the code by the constructor of the logic contract)

	// Core layer Wormhole contract. Exposed so higher-level contract can
	// interact with the wormhole interface.
	IWormhole immutable _wormhole;
	// ERC20 DUST token contract.
	IERC20 private immutable _dustToken;
	// Only VAAs from this emitter can mint NFTs with our contract (prevents spoofing).
	bytes32 private immutable _emitterAddress;
	// Common URI for all NFTs handled by this contract.
	bytes32 private immutable _baseUri;
	uint8 private immutable _baseUriLength;

	/**
	 * Both of these state variables have been deprecated, since this contract
	 * no longer mints NFTs. However, they should not be removed to preserve
	 * the current storage layout.
	 */
	uint256 private _dustAmountOnMint;
	uint256 private _gasTokenAmountOnMint;
	// Dictionary of VAA hash => flag that keeps track of claimed VAAs
	mapping(bytes32 => bool) private _claimedVaas;

	error WrongEmitterChainId();
	error WrongEmitterAddress();
	error FailedVaaParseAndVerification(string reason);
	error VaaAlreadyClaimed();
	error InvalidMessageLength();
	error BaseUriEmpty();
	error BaseUriTooLong();
	error InvalidMsgValue();
	error Deprecated();
	error BurnNotApproved();
	error RecipientZeroAddress();
	error InvalidBatchCount();

	event Minted(uint256 indexed tokenId, address indexed receiver);

	//constructor for the logic(!) contract
	constructor(
		IWormhole wormhole,
		IERC20 dustToken,
		bytes32 emitterAddress,
		bytes memory baseUri
	) {
		if (baseUri.length == 0) {
			revert BaseUriEmpty();
		}
		if (baseUri.length > 32) {
			revert BaseUriTooLong();
		}

		_wormhole = wormhole;
		_dustToken = dustToken;
		_emitterAddress = emitterAddress;
		_baseUri = bytes32(baseUri);
		_baseUriLength = uint8(baseUri.length);

		//brick logic contract
		initialize("", "", 0, 0, address(1), 0);
		renounceOwnership();
	}

	//intentionally empty (we only want the onlyOwner modifier "side-effect")
	function _authorizeUpgrade(address) internal override onlyOwner {}

	//"constructor" of the proxy contract
	function initialize(
		string memory name,
		string memory symbol,
		uint256 dustAmountOnMint,
		uint256 gasTokenAmountOnMint,
		address royaltyReceiver,
		uint96 royaltyFeeNumerator
	) public initializer {
		_dustAmountOnMint = dustAmountOnMint;
		_gasTokenAmountOnMint = gasTokenAmountOnMint;
		__UUPSUpgradeable_init();
		__ERC721_init(name, symbol);
		__ERC2981_init();
		__Ownable_init();

		_setDefaultRoyalty(royaltyReceiver, royaltyFeeNumerator);
	}

	function burnAndSend(uint256 tokenId, address recipient) public payable {
		if (!_isApprovedOrOwner(_msgSender(), tokenId)) {
			revert BurnNotApproved();
		}

		if (recipient == address(0)) {
			revert RecipientZeroAddress();
		}

		_burn(tokenId);

		//send wormhole message
		_wormhole.publishMessage{value: msg.value}(
			0, //nonce
			abi.encodePacked(uint16(tokenId), recipient), //payload
			FINALITY
		);
	}

	function forwardMessage(bytes calldata vaa) external payable {
		// Even though this message is being forwarded to Ethereum, we still
		// need to verify that it was sent from the trusted Solana contract,
		// and that it's a valid VAA. Also, weneed to save the VAA hash to
		// prevent spam. This will prevent the relayer from attempting to
		// mint the same token on Ethereum multiple times.
		(IWormhole.VM memory vm, bool valid, string memory reason) = _wormhole.parseAndVerifyVM(
			vaa
		);
		if (!valid) revert FailedVaaParseAndVerification(reason);

		if (vm.emitterChainId != SOURCE_CHAIN_ID) revert WrongEmitterChainId();

		if (vm.emitterAddress != _emitterAddress) revert WrongEmitterAddress();

		if (_claimedVaas[vm.hash]) revert VaaAlreadyClaimed();

		_claimedVaas[vm.hash] = true;

		if (vm.payload.length != BytesLib.uint16Size + BytesLib.addressSize)
			revert InvalidMessageLength();

		//send new message to Ethereum
		_wormhole.publishMessage{value: msg.value}(
			0, //nonce
			vm.payload,
			FINALITY
		);
	}

	// ---- Deprecated Methods ----

	/// @notice This method is deprecated.
	function receiveAndMint(bytes calldata vaa) external payable {
		revert Deprecated();
	}

	/// @notice This method is deprecated.
	function updateAmountsOnMint(
		uint256 dustAmountOnMint,
		uint256 gasTokenAmountOnMint
	) external onlyOwner {
		revert Deprecated();
	}

	/// @notice This method is deprecated.
	function getAmountsOnMint()
		external
		view
		returns (uint256 dustAmountOnMint, uint256 gasTokenAmountOnMint)
	{
		revert Deprecated();
	}

	// ---- ERC721 ----

	function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
		return string.concat(super.tokenURI(tokenId), ".json");
	}

	function _baseURI() internal view virtual override returns (string memory baseUri) {
		baseUri = new string(_baseUriLength);
		bytes32 tmp = _baseUri;
		assembly ("memory-safe") {
			mstore(add(baseUri, 32), tmp)
		}
	}

	// ---- ERC2981 ----

	function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
		_setDefaultRoyalty(receiver, feeNumerator);
	}

	function deleteDefaultRoyalty() external onlyOwner {
		_deleteDefaultRoyalty();
	}

	function setTokenRoyalty(
		uint256 tokenId,
		address receiver,
		uint96 feeNumerator
	) external onlyOwner {
		_setTokenRoyalty(tokenId, receiver, feeNumerator);
	}

	function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
		_resetTokenRoyalty(tokenId);
	}

	// ---- ERC165 ----

	function supportsInterface(
		bytes4 interfaceId
	) public view virtual override(ERC721Upgradeable, ERC2981Upgradeable) returns (bool) {
		return super.supportsInterface(interfaceId);
	}
}
