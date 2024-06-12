// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './ERC20.sol';

contract MyToken is ERC20 {
    event SayHi(string message);
    constructor()
        ERC20("MyToken", "MTK", 18)
    {}
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
        emit SayHi("hello!");
    }
}
