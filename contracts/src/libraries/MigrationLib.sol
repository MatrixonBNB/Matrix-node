// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IMigrationManager {
    struct StoredEvent {
        address emitter;
        bytes32 eventHash;
        bytes32[] topics;
        bytes data;
    }
    
    function recordERC20Holder(address holder) external;
    function recordERC721TokenId(uint256 id) external;
    function recordPairCreation(address pair) external;
    function recordEvent(IMigrationManager.StoredEvent memory storedEvent) external;
}

library MigrationLib {
    address public constant DUMMY_ADDRESS = 0x11110000000000000000000000000000000000C5;
    address public constant MIGRATION_MANAGER = 0x22220000000000000000000000000000000000D6;
    address public constant SYSTEM_ADDRESS = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;
    
    function manager() internal pure returns (IMigrationManager) {
        return IMigrationManager(MIGRATION_MANAGER);
    }
    
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
