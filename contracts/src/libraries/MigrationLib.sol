// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library MigrationLib {
    function isInMigration() internal view returns (bool) {
        return dummyHasCode();
    }
    
    function isNotInMigration() internal view returns (bool) {
        return !isInMigration();
    }
    
    function dummyHasCode() private view returns (bool) {
        address dummy = 0x11110000000000000000000000000000000000C5;
        return dummy.code.length != 0;
    }
}
