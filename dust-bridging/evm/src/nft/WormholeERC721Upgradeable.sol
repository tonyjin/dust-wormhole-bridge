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
    bytes32 immutable baseUri;
    uint8 immutable baseUriLength;
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
    error BaseUriTooLong();

    constructor(IWormhole initWormhole, bytes32 initMinterAddress, bytes memory initBaseUri) {
        if (initBaseUri.length > 32) {
            revert BaseUriTooLong();
        }

        wormhole = initWormhole;
        minterAddress = initMinterAddress;
        baseUri = bytes32(initBaseUri);
        baseUriLength = uint8(initBaseUri.length);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return string.concat(super.tokenURI(tokenId), ".json");
    }

    function _baseURI() internal view virtual override returns (string memory) {
        if (baseUriLength > 16) {
            if (baseUriLength > 24) {
                if (baseUriLength > 28) {
                    if (baseUriLength > 30) {
                        if (baseUriLength == 32) {
                            return string(abi.encodePacked(bytes32(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes31(baseUri)));
                        }
                    } /*if (baseUriLength <= 30)*/ else {
                        if (baseUriLength == 30) {
                            return string(abi.encodePacked(bytes30(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes29(baseUri)));
                        }
                    }
                } /*if (baseUriLength <= 28)*/ else {
                    if (baseUriLength > 26) {
                        if (baseUriLength == 28) {
                            return string(abi.encodePacked(bytes28(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes27(baseUri)));
                        }
                    } /*if (baseUriLength <= 26)*/ else {
                        if (baseUriLength == 26) {
                            return string(abi.encodePacked(bytes26(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes25(baseUri)));
                        }
                    }
                }
            } /*if (baseUriLength <= 24)*/ else {
                if (baseUriLength > 20) {
                    if (baseUriLength > 22) {
                        if (baseUriLength == 24) {
                            return string(abi.encodePacked(bytes24(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes23(baseUri)));
                        }
                    } /*if (baseUriLength <= 22)*/ else {
                        if (baseUriLength == 22) {
                            return string(abi.encodePacked(bytes22(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes21(baseUri)));
                        }
                    }
                } /*if (baseUriLength <= 20)*/ else {
                    if (baseUriLength > 18) {
                        if (baseUriLength == 20) {
                            return string(abi.encodePacked(bytes20(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes19(baseUri)));
                        }
                    } /*if (baseUriLength <= 18)*/ else {
                        if (baseUriLength == 18) {
                            return string(abi.encodePacked(bytes18(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes17(baseUri)));
                        }
                    }
                }
            }
        } /*if (baseUriLength <= 16)*/ else {
            if (baseUriLength > 8) {
                if (baseUriLength > 12) {
                    if (baseUriLength > 14) {
                        if (baseUriLength == 16) {
                            return string(abi.encodePacked(bytes16(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes15(baseUri)));
                        }
                    } /*if (baseUriLength <= 14)*/ else {
                        if (baseUriLength == 14) {
                            return string(abi.encodePacked(bytes14(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes13(baseUri)));
                        }
                    }
                } /*if (baseUriLength <= 12)*/ else {
                    if (baseUriLength > 10) {
                        if (baseUriLength == 12) {
                            return string(abi.encodePacked(bytes12(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes11(baseUri)));
                        }
                    } /*if (baseUriLength <= 10)*/ else {
                        if (baseUriLength == 10) {
                            return string(abi.encodePacked(bytes10(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes9(baseUri)));
                        }
                    }
                }
            } /*if (baseUriLength <= 8)*/ else {
                if (baseUriLength > 4) {
                    if (baseUriLength > 6) {
                        if (baseUriLength == 8) {
                            return string(abi.encodePacked(bytes8(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes7(baseUri)));
                        }
                    } /*if (baseUriLength <= 6)*/ else {
                        if (baseUriLength == 6) {
                            return string(abi.encodePacked(bytes6(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes5(baseUri)));
                        }
                    }
                } /*if (baseUriLength <= 4)*/ else {
                    if (baseUriLength > 2) {
                        if (baseUriLength == 4) {
                            return string(abi.encodePacked(bytes4(baseUri)));
                        } else {
                            return string(abi.encodePacked(bytes3(baseUri)));
                        }
                    } /*if (baseUriLength <= 2)*/ else {
                        if (baseUriLength == 2) {
                            return string(abi.encodePacked(bytes2(baseUri)));
                        } else if (baseUriLength == 1) {
                            return string(abi.encodePacked(bytes1(baseUri)));
                        } else {
                            return "";
                        }
                    }
                }
            }
        }
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
