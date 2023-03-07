// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
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
  ERC721Upgradeable,
  ERC2981Upgradeable,
  DefaultOperatorFiltererUpgradeable,
  OwnableUpgradeable
{
  using BytesLib for bytes;
  using SafeERC20 for IERC20;

  //immutable members are set in the constructor of the logic contract
  
  // Core layer Wormhole contract.
  IWormhole immutable _wormhole;
  // ERC20 DUST token contract.
  IERC20    immutable _dustToken;
  // Contract address that can mint NFTs. The mint VAA should have this as the emitter address.
  bytes32   immutable _minterAddress;
  // Common URI for all NFTs handled by this contract.
  bytes32   immutable _baseUri;
  uint8     immutable _baseUriLength;
  // Wormhole chain id that valid vaas must have.
  // We only support Solana for now.
  uint16 constant SOURCE_CHAIN_ID = 1;

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
  error BaseUriTooLong();
  error InvalidMsgValue();

  //This is the constructor for the logic contract - it sets all immutable members (i.e. bakes
  //  them directly into the deployed bytecode). The logic contract will be used via delegateCall
  //  by the ERC1967 proxy contract.
  constructor(
    IWormhole wormhole,
    IERC20 dustToken,
    bytes32 minterAddress,
    bytes memory baseUri
  ) {
    if (baseUri.length > 32) {
      revert BaseUriTooLong();
    }

    _wormhole = wormhole;
    _dustToken = dustToken;
    _minterAddress = minterAddress;
    _baseUri = bytes32(baseUri);
    _baseUriLength = uint8(baseUri.length);

    //brick logic contract
    initialize("","",0,0);
    renounceOwnership();
  }

  //intentionally empty (we only want the onlyOwner modifier "side-effect")
  function _authorizeUpgrade(address) internal override onlyOwner {}

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    return string.concat(super.tokenURI(tokenId), ".json");
  }

  function _baseURI() internal view override returns (string memory) {
    if (_baseUriLength > 16) {
      if (_baseUriLength > 24) {
        if (_baseUriLength > 28) {
          if (_baseUriLength > 30) {
            if (_baseUriLength == 32)
              return string(abi.encodePacked(bytes32(_baseUri)));
            else
              return string(abi.encodePacked(bytes31(_baseUri)));
          } /*if (_baseUriLength <= 30)*/ else {
            if (_baseUriLength == 30)
              return string(abi.encodePacked(bytes30(_baseUri)));
            else
              return string(abi.encodePacked(bytes29(_baseUri)));
          }
        } /*if (_baseUriLength <= 28)*/ else {
          if (_baseUriLength > 26) {
            if (_baseUriLength == 28)
              return string(abi.encodePacked(bytes28(_baseUri)));
            else
              return string(abi.encodePacked(bytes27(_baseUri)));
          } /*if (_baseUriLength <= 26)*/ else {
            if (_baseUriLength == 26)
              return string(abi.encodePacked(bytes26(_baseUri)));
            else
              return string(abi.encodePacked(bytes25(_baseUri)));
          }
        }
      } /*if (_baseUriLength <= 24)*/ else {
        if (_baseUriLength > 20) {
          if (_baseUriLength > 22) {
            if (_baseUriLength == 24)
              return string(abi.encodePacked(bytes24(_baseUri)));
            else
              return string(abi.encodePacked(bytes23(_baseUri)));
          } /*if (_baseUriLength <= 22)*/ else {
            if (_baseUriLength == 22)
              return string(abi.encodePacked(bytes22(_baseUri)));
            else
              return string(abi.encodePacked(bytes21(_baseUri)));
          }
        } /*if (_baseUriLength <= 20)*/ else {
          if (_baseUriLength > 18) {
            if (_baseUriLength == 20)
              return string(abi.encodePacked(bytes20(_baseUri)));
            else
              return string(abi.encodePacked(bytes19(_baseUri)));
          } /*if (_baseUriLength <= 18)*/ else {
            if (_baseUriLength == 18)
              return string(abi.encodePacked(bytes18(_baseUri)));
            else
              return string(abi.encodePacked(bytes17(_baseUri)));
          }
        }
      }
    } /*if (_baseUriLength <= 16)*/ else {
      if (_baseUriLength > 8) {
        if (_baseUriLength > 12) {
          if (_baseUriLength > 14) {
            if (_baseUriLength == 16)
              return string(abi.encodePacked(bytes16(_baseUri)));
            else
              return string(abi.encodePacked(bytes15(_baseUri)));
          } /*if (_baseUriLength <= 14)*/ else {
            if (_baseUriLength == 14)
              return string(abi.encodePacked(bytes14(_baseUri)));
            else
              return string(abi.encodePacked(bytes13(_baseUri)));
          }
        } /*if (_baseUriLength <= 12)*/ else {
          if (_baseUriLength > 10) {
            if (_baseUriLength == 12)
              return string(abi.encodePacked(bytes12(_baseUri)));
            else
              return string(abi.encodePacked(bytes11(_baseUri)));
          } /*if (_baseUriLength <= 10)*/ else {
            if (_baseUriLength == 10)
              return string(abi.encodePacked(bytes10(_baseUri)));
            else
              return string(abi.encodePacked(bytes9(_baseUri)));
          }
        }
      } /*if (_baseUriLength <= 8)*/ else {
        if (_baseUriLength > 4) {
          if (_baseUriLength > 6) {
            if (_baseUriLength == 8)
              return string(abi.encodePacked(bytes8(_baseUri)));
            else
              return string(abi.encodePacked(bytes7(_baseUri)));
          } /*if (_baseUriLength <= 6)*/ else {
            if (_baseUriLength == 6)
              return string(abi.encodePacked(bytes6(_baseUri)));
            else
              return string(abi.encodePacked(bytes5(_baseUri)));
          }
        } /*if (_baseUriLength <= 4)*/ else {
          if (_baseUriLength > 2) {
            if (_baseUriLength == 4)
              return string(abi.encodePacked(bytes4(_baseUri)));
            else
              return string(abi.encodePacked(bytes3(_baseUri)));
          } /*if (_baseUriLength <= 2)*/ else {
            if (_baseUriLength == 2) {
              return string(abi.encodePacked(bytes2(_baseUri)));
            } else if (_baseUriLength == 1) {
              return string(abi.encodePacked(bytes1(_baseUri)));
            } else {
              return "";
            }
          }
        }
      }
    }
  }

  function initialize(
    string memory name,
    string memory symbol,
    uint256 dustAmountOnMint,
    uint256 gasTokenAmountOnMint
  ) public initializer {
    _dustAmountOnMint = dustAmountOnMint;
    _gasTokenAmountOnMint = gasTokenAmountOnMint;
    __UUPSUpgradeable_init();
    __ERC721_init(name, symbol);
    __ERC2981_init();
    __Ownable_init();
    __DefaultOperatorFilterer_init();
  }

  function updateAmountsOnMint(
    uint256 dustAmountOnMint,
    uint256 gasTokenAmountOnMint
  ) external onlyOwner {
    _dustAmountOnMint = dustAmountOnMint;
    _gasTokenAmountOnMint = gasTokenAmountOnMint;
  }

  function setApprovalForAll(
    address operator,
    bool approved
  ) public override onlyAllowedOperatorApproval(operator) {
    super.setApprovalForAll(operator, approved);
  }

  function approve(
    address operator,
    uint256 tokenId
  ) public override onlyAllowedOperatorApproval(operator) {
    super.approve(operator, tokenId);
  }

  function transferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public override onlyAllowedOperator(from) {
    super.transferFrom(from, to, tokenId);
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public override onlyAllowedOperator(from) {
    super.safeTransferFrom(from, to, tokenId);
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId,
    bytes memory data
  ) public override onlyAllowedOperator(from) {
    super.safeTransferFrom(from, to, tokenId, data);
  }

  function supportsInterface(bytes4 interfaceId)
    public view override(ERC721Upgradeable, ERC2981Upgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
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
}
