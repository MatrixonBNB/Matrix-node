// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/libraries/EventReplayable.sol";
import "src/libraries/MigrationLib.sol";
import "src/predeploys/MigrationManager.sol";

// Test contract that emits events
contract TestEventEmitter is EventReplayable {
    function emitTestEvent(
        string memory eventSignature,
        bytes memory indexedParamsEncoded,
        bytes memory nonIndexedData
    ) public {
        recordAndEmitEvent(eventSignature, indexedParamsEncoded, nonIndexedData);
    }
}

contract EventReplayableTest is Test {
    TestEventEmitter emitter;
    MigrationManager migrationManager;
    
    // Define different event types for testing
    event TestEvent(address indexed sender, uint256 indexed id, string data);
    event OneIndexedEvent(address indexed sender, string data);
    event ThreeIndexedEvent(address indexed sender, uint256 indexed id, bytes32 indexed hash, string data);
    event NoIndexedEvent(string data, uint256 number);
    
    function setUp() public {
        migrationManager = new MigrationManager();
        emitter = new TestEventEmitter();
        
        // Deploy the mock migration manager to the expected address
        vm.etch(
            MigrationLib.MIGRATION_MANAGER,
            address(migrationManager).code
        );
        
        migrationManager = MigrationManager(MigrationLib.MIGRATION_MANAGER);
    }

    function testEventStorage() public {
        string memory eventSig = "TestEvent(address,uint256,string)";
        address sender = address(this);
        uint256 id = 123;
        bytes memory indexedParams = abi.encode(sender, id);
        string memory data = "Hello World";
        bytes memory nonIndexedData = abi.encode(data);
        
        // Test in V1 mode - should store
        vm.etch(MigrationLib.DUMMY_ADDRESS, hex"00");
        
        emitter.emitTestEvent(eventSig, indexedParams, nonIndexedData);
        
        // Verify event was stored
        assertEq(migrationManager.storedEventsLength(), 1);
        
        // Test in V2 mode - should not store
        vm.etch(MigrationLib.DUMMY_ADDRESS, "");
        
        emitter.emitTestEvent(eventSig, indexedParams, nonIndexedData);
        
        // Verify no new event was stored
        assertEq(migrationManager.storedEventsLength(), 1);
    }

    function testEmitEventWithOneIndexedParam() public {
        string memory eventSig = "OneIndexedEvent(address,string)";
        address sender = address(this);
        bytes memory indexedParams = abi.encode(sender);
        string memory data = "Hello World";
        bytes memory nonIndexedData = abi.encode(data);
        
        vm.recordLogs();
        
        // Test in V1 mode - should emit and record
        vm.store(
            address(MigrationLib),
            bytes32(uint256(1)), // slot for isInV1
            bytes32(uint256(1))
        );
        
        emitter.emitTestEvent(eventSig, indexedParams, nonIndexedData);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        
        assertEq(entries[0].topics[0], keccak256(bytes(eventSig)));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(sender))));
        
        (string memory emittedData) = abi.decode(entries[0].data, (string));
        assertEq(emittedData, data);
    }

    function testEmitEventWithThreeIndexedParams() public {
        string memory eventSig = "ThreeIndexedEvent(address,uint256,bytes32,string)";
        address sender = address(this);
        uint256 id = 456;
        bytes32 hash = keccak256("test");
        bytes memory indexedParams = abi.encode(sender, id, hash);
        string memory data = "Hello World";
        bytes memory nonIndexedData = abi.encode(data);
        
        vm.recordLogs();
        
        // Test in V1 mode - should emit and record
        vm.store(
            address(MigrationLib),
            bytes32(uint256(1)), // slot for isInV1
            bytes32(uint256(1))
        );
        
        emitter.emitTestEvent(eventSig, indexedParams, nonIndexedData);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        
        assertEq(entries[0].topics[0], keccak256(bytes(eventSig)));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(sender))));
        assertEq(entries[0].topics[2], bytes32(id));
        assertEq(entries[0].topics[3], hash);
        
        (string memory emittedData) = abi.decode(entries[0].data, (string));
        assertEq(emittedData, data);
    }

    function testEmitEventWithNoIndexedParams() public {
        string memory eventSig = "NoIndexedEvent(string,uint256)";
        bytes memory indexedParams = "";
        string memory str = "Hello";
        uint256 number = 789;
        bytes memory nonIndexedData = abi.encode(str, number);
        
        vm.recordLogs();
        
        // Test in V1 mode
        vm.store(
            address(MigrationLib),
            bytes32(uint256(1)),
            bytes32(uint256(1))
        );
        
        emitter.emitTestEvent(eventSig, indexedParams, nonIndexedData);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        
        assertEq(entries[0].topics[0], keccak256(bytes(eventSig)));
        
        (string memory emittedStr, uint256 emittedNumber) = abi.decode(entries[0].data, (string, uint256));
        assertEq(emittedStr, str);
        assertEq(emittedNumber, number);
    }

    function testFailEmitEventWithTooManyIndexedParams() public {
        string memory eventSig = "TooManyParams(address,uint256,bytes32,bytes32,string)";
        bytes memory indexedParams = abi.encode(
            address(this),
            uint256(1),
            bytes32("test1"),
            bytes32("test2")
        );
        bytes memory nonIndexedData = abi.encode("Hello");
        
        emitter.emitTestEvent(eventSig, indexedParams, nonIndexedData);
    }
} 