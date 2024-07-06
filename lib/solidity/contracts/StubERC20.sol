// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import '../legacy/FacetERC20.sol';

contract StubERC20 is FacetERC20 {
    constructor(string memory name) {
        _initializeERC20(name, "symbol", 18);
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function airdrop(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function updateName(string memory name) public {
        _FacetERC20Storage().name = name;
    }
}
