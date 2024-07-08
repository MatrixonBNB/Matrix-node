// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract Counter {
    event Deployed(address indexed addr, string greeting);

    uint256 private count;

    constructor(uint256 initial_count) {
        count = initial_count;
        emit Deployed(msg.sender, "Hello, World!");
    }

    function increment() public {
        count += 1;
    }

    function getCount() public view returns (uint256) {
        return count;
    }
    
    function createRevert(bool shouldRevert) public pure {
        if (shouldRevert) {
            revert("Reverted");
        }
    }
    
    function runOutOfGas() public pure {
        uint i = 0;
        
        while(true) {
            i++;
        }
    }
    
    receive() external payable {}
}
