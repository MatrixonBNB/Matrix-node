// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/auth/Ownable.sol";
import "src/libraries/MigrationLib.sol";

abstract contract FacetOwnable is Ownable {
    function transferOwnership(address newOwner) public payable override onlyOwner {
        if (MigrationLib.isInMigration()) {
            _setOwner(newOwner);
        } else {
            super.transferOwnership(newOwner);
        }
    }
}
