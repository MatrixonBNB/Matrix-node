// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/predeploys/MigrationManager.sol";
import "../src/libraries/MigrationLib.sol";

// Mock contract that will emit stored events
contract MockEventEmitter is EventReplayable {
    function emitTestEvent(
        string memory eventSignature,
        bytes memory indexedParamsEncoded,
        bytes memory nonIndexedData
    ) public {
        recordAndEmitEvent(eventSignature, indexedParamsEncoded, nonIndexedData);
    }
}

contract MigrationManagerTest is Test {
    MigrationManager manager;
    MockEventEmitter emitter;
    
    function setUp() public {
        emitter = new MockEventEmitter();
        
        // Deploy the mock migration manager to the expected address
        vm.etch(
            MigrationLib.MIGRATION_MANAGER,
            address(new MigrationManager()).code
        );
        
        manager = MigrationManager(MigrationLib.MIGRATION_MANAGER);
    }
    
    function _enterMigrationMode() internal {
        vm.etch(MigrationLib.DUMMY_ADDRESS, hex"00");
    }
    
    function _exitMigrationMode() internal {
        vm.etch(MigrationLib.DUMMY_ADDRESS, "");
    }
    
    function test_StoreAndProcessEvents() public {
        _enterMigrationMode();

        for (uint i = 0; i < 3; i++) {
            emitter.emitTestEvent(
                "TestEvent(uint256)",
                abi.encode(i),
                ""
            );
        }
        
        assertEq(manager.storedEventsCount(), 3, "Should have 3 stored events");
        
        _exitMigrationMode();
        vm.prank(MigrationLib.SYSTEM_ADDRESS);
        manager.executeMigration();
        
        assertEq(manager.storedEventsCount(), 0, "Should have processed all events");
    }
    
    function test_ProcessEventsInOrder() public {
        _enterMigrationMode();
        
        // Record events with different data to verify order
        for (uint i = 0; i < 3; i++) {
            emitter.emitTestEvent(
                "TestEvent(uint256)",
                abi.encode(i),  // Each event has unique indexed param
                abi.encode(100 + i)  // And unique non-indexed data
            );
        }
        
        _exitMigrationMode();
        vm.prank(MigrationLib.SYSTEM_ADDRESS);
        
        // Process and verify order through event emissions
        manager.executeMigration();
        
        // Verify final state
        assertEq(manager.storedEventProcessedCount(), 3, "Should process all events");
        assertEq(manager.lastStoredEventIndex(), 3, "Last event index should match");
    }
    
    function test_BatchLimits() public {
        _enterMigrationMode();
        
        // Record more events than MAX_EVENTS_PER_BATCH
        uint256 totalEvents = manager.MAX_EVENTS_PER_BATCH() + 50;
        
        for (uint i = 0; i < totalEvents; i++) {
            emitter.emitTestEvent(
                "TestEvent(uint256)",
                abi.encode(i),
                ""
            );
        }
        
        assertEq(manager.storedEventsCount(), totalEvents, "Should record all events");
        
        _exitMigrationMode();
        vm.startPrank(MigrationLib.SYSTEM_ADDRESS);
        
        // First batch
        manager.executeMigration();
        assertEq(
            manager.storedEventsCount(), 
            totalEvents - manager.MAX_EVENTS_PER_BATCH(), 
            "Should process MAX_EVENTS_PER_BATCH events"
        );
        
        // Second batch
        manager.executeMigration();
        assertEq(manager.storedEventsCount(), 0, "Should process remaining events");
    }
    
    function test_RevertIfNotSystemAddress() public {
        _enterMigrationMode();
        emitter.emitTestEvent(
            "TestEvent(uint256)",
            abi.encode(1),
            ""
        );
        
        _exitMigrationMode();
        
        // Try to execute migration from non-system address
        vm.expectRevert("Only system address can call");
        manager.executeMigration();
    }
}
