// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721Upgradeable, ERC721Upgradeable, ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {DefaultOperatorFiltererUpgradeable} from "./DefaultOperatorFiltererUpgradeable.sol";
import {IWormhole} from "wormhole-solidity/IWormhole.sol";
import {BytesLib} from "wormhole-solidity/BytesLib.sol";

/**
 * @title  DustWormholeERC721Upgradeable
 * @notice ERC721 that mints tokens based on VAAs.
 *         This contract is configured to use the DefaultOperatorFilterer, which automatically
 *         registers the token and subscribes it to OpenSea's curated filters.
 *         Adding the onlyAllowedOperator modifier to the transferFrom and both safeTransferFrom
 *         methods ensures that the msg.sender (operator) is allowed by the OperatorFilterRegistry.
 */
contract DustWormholeERC721Upgradeable is
  UUPSUpgradeable,
  ERC721EnumerableUpgradeable,
  ERC2981Upgradeable,
  DefaultOperatorFiltererUpgradeable,
  OwnableUpgradeable
{
  using BytesLib for bytes;
  using SafeERC20 for IERC20;

  // Wormhole chain id that valid vaas must have -- must be Solana.
  uint16 constant SOURCE_CHAIN_ID = 1;

  // -- immutable members (baked into the code by the constructor of the logic contract)
  
  // Core layer Wormhole contract.
  IWormhole immutable _wormhole;
  // ERC20 DUST token contract.
  IERC20    immutable _dustToken;
  // Contract address that can mint NFTs. The mint VAA should have this as the emitter address.
  bytes32   immutable _minterAddress;
  // Common URI for all NFTs handled by this contract.
  bytes32   immutable _baseUri;
  uint8     immutable _baseUriLength;

  // Amount of DUST to transfer to the minter on upon relayed mint.
  uint256 _dustAmountOnMint;
  // Amount of gas token (ETH, MATIC, etc.) to transfer to the minter on upon relayed mint.
  uint256 _gasTokenAmountOnMint;
  // Dictionary of VAA hash => flag that keeps track of claimed VAAs
  mapping(bytes32 => bool) _claimedVaas;

  error WrongEmitterChainId();
  error WrongEmitterAddress();
  error FailedVaaParseAndVerification(string reason);
  error VaaAlreadyClaimed();
  error InvalidMessageLength();
  error BaseUriEmpty();
  error BaseUriTooLong();
  error InvalidMsgValue();

  //constructor for the logic(!) contract
  constructor(
    IWormhole wormhole,
    IERC20 dustToken,
    bytes32 minterAddress,
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
    _minterAddress = minterAddress;
    _baseUri = bytes32(baseUri);
    _baseUriLength = uint8(baseUri.length);

    //brick logic contract
    //initialize("","",0,0);
    initialize("","",0,0,address(1),0);
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
    __DefaultOperatorFilterer_init();

    _setDefaultRoyalty(royaltyReceiver, royaltyFeeNumerator);
  }

  function updateAmountsOnMint(
    uint256 dustAmountOnMint,
    uint256 gasTokenAmountOnMint
  ) external onlyOwner {
    _dustAmountOnMint = dustAmountOnMint;
    _gasTokenAmountOnMint = gasTokenAmountOnMint;
  }

  function getAmountsOnMint() external view returns (uint256 dustAmountOnMint, uint256 gasTokenAmountOnMint) {
    dustAmountOnMint = _dustAmountOnMint;
    gasTokenAmountOnMint = _gasTokenAmountOnMint;
  }

  /**
   * Mints an NFT based on an valid VAA and kickstarts the recipient's wallet with
   *   gas tokens (ETH or MATIC) and DUST (taken from msg.sender unless msg.sender is recipient).
   * TokenId and recipient address are taken from the VAA.
   * The VAA must have been emitted by the minterAddress on Solana (chainId = 1).
   */
  function receiveAndMint(bytes calldata vaa) external payable {
    (IWormhole.VM memory vm, bool valid, string memory reason) = _wormhole.parseAndVerifyVM(vaa);
    if (!valid)
      revert FailedVaaParseAndVerification(reason);

    if (vm.emitterChainId != SOURCE_CHAIN_ID)
      revert WrongEmitterChainId();

    if (vm.emitterAddress != _minterAddress)
      revert WrongEmitterAddress();

    if (_claimedVaas[vm.hash])
      revert VaaAlreadyClaimed();
    
    _claimedVaas[vm.hash] = true;

    (uint256 tokenId, address evmRecipient) = parsePayload(vm.payload);
    _safeMint(evmRecipient, tokenId);
    
    if (msg.sender != evmRecipient) {
      if (msg.value != _gasTokenAmountOnMint)
        revert InvalidMsgValue();
      
      payable(evmRecipient).transfer(msg.value);
      _dustToken.safeTransferFrom(msg.sender, evmRecipient, _dustAmountOnMint);
    }
    else //if the recipient relays the message themselves then they must not include any gas token
      if (msg.value != 0)
        revert InvalidMsgValue();
  }

  function parsePayload(
    bytes memory message
  ) internal pure returns (uint256 tokenId, address evmRecipient) {
    if (message.length != BytesLib.uint16Size + BytesLib.addressSize)
      revert InvalidMessageLength();

    tokenId = message.toUint16(0);
    evmRecipient = message.toAddress(BytesLib.uint16Size);
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

  // ---- ERC721 ----

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    return string.concat(super.tokenURI(tokenId), ".json");
  }

  function _baseURI() internal view override returns (string memory baseUri) {
    baseUri = new string(_baseUriLength);
    bytes32 tmp = _baseUri;
    assembly ("memory-safe") {
      mstore(add(baseUri, 32), tmp)
    }
  }

  function setApprovalForAll(
    address operator,
    bool approved
  ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperatorApproval(operator) {
    super.setApprovalForAll(operator, approved);
  }

  function approve(
    address operator,
    uint256 tokenId
  ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperatorApproval(operator) {
    super.approve(operator, tokenId);
  }

  function transferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
    super.transferFrom(from, to, tokenId);
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
    super.safeTransferFrom(from, to, tokenId);
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId,
    bytes memory data
  ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
    super.safeTransferFrom(from, to, tokenId, data);
  }

  // ---- ERC165 ----

  function supportsInterface(bytes4 interfaceId)
    public view override(ERC721EnumerableUpgradeable, ERC2981Upgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}
