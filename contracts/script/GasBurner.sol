// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract GasBurner {
    function burn(uint256 amount) public view {
        uint256 startGas = gasleft();
        uint256 adjustedAmount;
        
        if (amount > 22_000) {
            adjustedAmount = amount - 22_000;
        }
        
        // Keep burning gas until we've used the requested amount
        while (startGas - gasleft() < adjustedAmount) {
            assembly {
                pop(0)
            }
        }
    }
}
