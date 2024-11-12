// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC20} from "solady/tokens/ERC20.sol";

contract MockWETH is ERC20 {
    constructor() {
        // Maybe mint some initial supply to deployer
        _mint(msg.sender, 1000000 ether);
    }
    
    function name() public pure override returns (string memory) {
        return "Wrapped Ether";
    }
    
    function symbol() public pure override returns (string memory) {
        return "WETH";
    }

    // Optional: Add deposit/withdraw functions to mimic real WETH
    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}
