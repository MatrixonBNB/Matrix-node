// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library MigrationLib {
    address public constant DUMMY_ADDRESS = 0x11110000000000000000000000000000000000C5;
    
    function isInMigration() internal view returns (bool) {
        return dummyHasCode();
    }
    
    function isNotInMigration() internal view returns (bool) {
        return !isInMigration();
    }
    
    function dummyHasCode() private view returns (bool) {
        return DUMMY_ADDRESS.code.length != 0;
    }
}
