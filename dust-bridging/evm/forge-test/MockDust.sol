// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDust is ERC20 {
    constructor(uint256 supply) ERC20("MockDust", "MockDUST") {
        _mint(msg.sender, supply);
    }
}