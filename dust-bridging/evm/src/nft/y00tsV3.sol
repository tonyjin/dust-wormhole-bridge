// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {BytesLib} from "wormhole-solidity/BytesLib.sol";
import {ERC5058Upgradeable} from "ERC5058/ERC5058Upgradeable.sol";
import {IERC5192} from "ERC5192/IERC5192.sol";

/**
 * @title  DeBridge
 * @notice ERC721 that mints tokens based on VAAs.
 */
contract y00tsV3 is
	ERC5058Upgradeable,
	IERC5192,
	UUPSUpgradeable,
	ERC2981Upgradeable,
	Ownable2StepUpgradeable
{
	using BytesLib for bytes;
	using SafeERC20 for IERC20;

	// Wormhole chain id that valid vaas must have -- must be Polygon.
	uint16 constant SOURCE_CHAIN_ID = 6;
	uint256 private constant MAX_EXPIRE_TIME =
		0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

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

	// Amount of DUST to transfer to the minter on upon relayed mint.
	uint256 private _dustAmountOnMint;
	// Amount of gas token (ETH, MATIC, etc.) to transfer to the minter on upon relayed mint.
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

	event Minted(uint256 indexed tokenId, address indexed receiver);
	event BatchMinted(uint256[] indexed tokenIds, address indexed receiver);

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

	function updateAmountsOnMint(
		uint256 dustAmountOnMint,
		uint256 gasTokenAmountOnMint
	) external onlyOwner {
		_dustAmountOnMint = dustAmountOnMint;
		_gasTokenAmountOnMint = gasTokenAmountOnMint;
	}

	function getAmountsOnMint()
		external
		view
		returns (uint256 dustAmountOnMint, uint256 gasTokenAmountOnMint)
	{
		dustAmountOnMint = _dustAmountOnMint;
		gasTokenAmountOnMint = _gasTokenAmountOnMint;
	}

	/**
	 * Mints an NFT based on an valid VAA and kickstarts the recipient's wallet with
	 *   gas tokens (ETH or MATIC) and DUST (taken from msg.sender unless msg.sender is recipient).
	 * TokenId and recipient address are taken from the VAA.
	 * The Wormhole message must have been published by the DeBridge instance of the
	 *   NFT collection with the specified emitter on Solana (chainId = 1).
	 */
	function receiveAndMint(bytes calldata vaa) external payable {
		IWormhole.VM memory vm = verifyMintMessage(vaa);

		(uint256 tokenId, address evmRecipient) = parsePayload(vm.payload);
		_safeMint(evmRecipient, tokenId);
		emit Minted(tokenId, evmRecipient);

		handleGasDropOff(evmRecipient);
	}

	function receiveAndMintBatch(bytes calldata vaa) external payable {
		IWormhole.VM memory vm = verifyMintMessage(vaa);

		(uint256 tokenCount, uint256[] memory tokenIds, address evmRecipient) = parseBatchPayload(
			vm.payload
		);

		for (uint256 i = 0; i < tokenCount; ) {
			_safeMint(evmRecipient, tokenIds[i]);

			unchecked {
				i += 1;
			}
		}
		emit BatchMinted(tokenIds, evmRecipient);

		handleGasDropOff(evmRecipient);
	}

	function handleGasDropOff(address evmRecipient) internal {
		if (msg.sender != evmRecipient) {
			if (msg.value != _gasTokenAmountOnMint) revert InvalidMsgValue();

			payable(evmRecipient).transfer(msg.value);
			_dustToken.safeTransferFrom(msg.sender, evmRecipient, _dustAmountOnMint);
		}
		//if the recipient relays the message themselves then they must not include any gas token
		else if (msg.value != 0) revert InvalidMsgValue();
	}

	function parsePayload(
		bytes memory message
	) internal pure returns (uint256 tokenId, address evmRecipient) {
		if (message.length != BytesLib.uint16Size + BytesLib.addressSize)
			revert InvalidMessageLength();

		tokenId = message.toUint16(0);
		evmRecipient = message.toAddress(BytesLib.uint16Size);
	}

	function parseBatchPayload(
		bytes memory message
	) internal pure returns (uint256, uint256[] memory, address) {
		uint256 messageLength = message.length;
		uint256 endTokenIndex = messageLength - BytesLib.addressSize;
		uint256 batchSize = endTokenIndex / BytesLib.uint16Size;

		if (
			messageLength <= BytesLib.uint16Size + BytesLib.addressSize ||
			endTokenIndex % BytesLib.uint16Size != 0
		) {
			revert InvalidMessageLength();
		}

		//parse the recipient
		address evmRecipient = message.toAddress(endTokenIndex);

		//parse the tokenIds
		uint256[] memory tokenIds = new uint256[](batchSize);
		for (uint256 i = 0; i < batchSize; ) {
			unchecked {
				tokenIds[i] = message.toUint16(i * BytesLib.uint16Size);
				i += 1;
			}
		}

		return (batchSize, tokenIds, evmRecipient);
	}

	function verifyMintMessage(bytes calldata vaa) internal returns (IWormhole.VM memory) {
		(IWormhole.VM memory vm, bool valid, string memory reason) = _wormhole.parseAndVerifyVM(
			vaa
		);
		if (!valid) revert FailedVaaParseAndVerification(reason);

		if (vm.emitterChainId != SOURCE_CHAIN_ID) revert WrongEmitterChainId();

		if (vm.emitterAddress != _emitterAddress) revert WrongEmitterAddress();

		if (_claimedVaas[vm.hash]) revert VaaAlreadyClaimed();

		_claimedVaas[vm.hash] = true;

		return vm;
	}

	function locked(uint256 tokenId) external view override returns (bool) {
		return isLocked(tokenId);
	}

	// ---- ERC5058 ----

	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 tokenId,
		uint256 batchSize
	) internal virtual override(ERC5058Upgradeable) {
		ERC5058Upgradeable._beforeTokenTransfer(from, to, tokenId, batchSize);
	}

	function _afterTokenTransfer(
		address from,
		address to,
		uint256 tokenId,
		uint256 batchSize
	) internal virtual override(ERC5058Upgradeable) {
		ERC5058Upgradeable._afterTokenTransfer(from, to, tokenId, batchSize);
	}

	function _beforeTokenLock(
		address operator,
		address owner,
		uint256 tokenId,
		uint256 expired
	) internal virtual override {
		super._beforeTokenLock(operator, owner, tokenId, expired);
		require(expired == 0 || expired == MAX_EXPIRE_TIME, "Auto expiration is not supported.");

		// Emit events for ERC5192
		if (expired != 0) {
			emit Locked(tokenId);
		} else {
			emit Unlocked(tokenId);
		}
	}

	function _burn(uint256 tokenId) internal virtual override(ERC5058Upgradeable) {
		ERC5058Upgradeable._burn(tokenId);
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

	// ---- ERC165 ----

	function supportsInterface(
		bytes4 interfaceId
	) public view virtual override(ERC5058Upgradeable, ERC2981Upgradeable) returns (bool) {
		return
			interfaceId == type(IERC5192).interfaceId ||
			ERC5058Upgradeable.supportsInterface(interfaceId) ||
			super.supportsInterface(interfaceId);
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
}
