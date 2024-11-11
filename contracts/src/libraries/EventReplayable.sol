// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MigrationLib.sol";

abstract contract EventReplayable {
    function recordAndEmitEvent(
        string memory eventSignature,
        bytes memory indexedParamsEncoded,
        bytes memory nonIndexedData
    ) internal {
        bytes32 eventHash = keccak256(bytes(eventSignature));

        // Convert indexed params to topics using shared helper
        bytes32[] memory topics = _bytesToTopics(indexedParamsEncoded);
        
        IMigrationManager.StoredEvent memory storedEvent = IMigrationManager.StoredEvent({
            emitter: address(this),
            eventHash: eventHash,
            topics: topics,
            data: nonIndexedData
        });
        
        if (MigrationLib.isInMigration()) {
            MigrationLib.manager().recordEvent(storedEvent);
        }
        
        _emitStoredEvent(storedEvent);
    }
    
    function _emitStoredEvent(IMigrationManager.StoredEvent memory storedEvent) internal {
        bytes32 eventHash = storedEvent.eventHash;
        bytes32[] memory topics = storedEvent.topics;
        bytes memory nonIndexedData = storedEvent.data;
        
        uint256 dataLength = nonIndexedData.length;
        uint256 dataPtr;
        assembly {
            dataPtr := add(nonIndexedData, 0x20)
        }
        
        uint256 indexedCount = topics.length;

        // Emit the event
        assembly {
            switch indexedCount
            case 0 { log1(dataPtr, dataLength, eventHash) }
            case 1 { log2(dataPtr, dataLength, eventHash, mload(add(topics, 0x20))) }
            case 2 { log3(dataPtr, dataLength, eventHash, mload(add(topics, 0x20)), mload(add(topics, 0x40))) }
            case 3 { log4(dataPtr, dataLength, eventHash, mload(add(topics, 0x20)), mload(add(topics, 0x40)), mload(add(topics, 0x60))) }
        }
    }
    
    function emitStoredEvent(IMigrationManager.StoredEvent memory storedEvent) external {
        require(msg.sender == MigrationLib.MIGRATION_MANAGER, "Only MigrationManager can emit events");
        _emitStoredEvent(storedEvent);
    }
    
    function _bytesToTopics(bytes memory indexedParams) internal pure returns (bytes32[] memory) {
        uint256 indexedCount = indexedParams.length / 32;
        require(indexedCount <= 3, "Too many indexed parameters");
        
        bytes32[] memory topics = new bytes32[](indexedCount);
        assembly {
            if gt(indexedCount, 0) { mstore(add(topics, 0x20), mload(add(indexedParams, 0x20))) }
            if gt(indexedCount, 1) { mstore(add(topics, 0x40), mload(add(indexedParams, 0x40))) }
            if gt(indexedCount, 2) { mstore(add(topics, 0x60), mload(add(indexedParams, 0x60))) }
        }
        return topics;
    }
}
