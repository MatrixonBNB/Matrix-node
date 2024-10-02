// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/auth/Ownable.sol";

abstract contract FacetOwnable is Ownable {
    function transferOwnership(address newOwner) public payable override onlyOwner {
        _setOwner(newOwner);
    }
}
