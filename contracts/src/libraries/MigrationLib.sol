// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library MigrationLib {
    address public constant DUMMY_ADDRESS = 0x11110000000000000000000000000000000000C5;
    address public constant MIGRATION_MANAGER = address(uint160(uint256(keccak256("migration manager"))));
    address public constant MIGRATOR_ADDRESS = address(uint160(uint256(keccak256("v1 to v2 migrator"))));
    
    function isInV1() internal view returns (bool) {
        return dummyHasCode();
    }
    
    function isInV2() internal view returns (bool) {
        return !isInV1();
    }
    
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
