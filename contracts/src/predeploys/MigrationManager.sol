// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetERC20.sol";
import "src/libraries/FacetERC721.sol";
import "lib/solady/utils/EnumerableSetLib.sol";
import "lib/solady/utils/LibString.sol";
import "src/libraries/MigrationLib.sol";
import "src/libraries/EventReplayable.sol";

interface FacetSwapFactory {
    function allPairs(uint256 index) external view returns (address);
    function allPairsLength() external view returns (uint256);
    function emitPairCreated(address token0, address token1, address pair, uint256 pairLength) external;
}

interface FacetSwapPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function sync() external;
}

contract MigrationManager is EventReplayable, IMigrationManager {
    using EnumerableSetLib for EnumerableSetLib.AddressSet;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;
    
    uint256 public constant MAX_EVENTS_PER_BATCH = 100;
    
    bool public migrationExecuted;
    
    uint32 public lastStoredEventIndex;
    uint32 public storedEventProcessedCount;
    uint32 public currentBatchEmittedEvents;
    uint32 public totalEmittedEvents;
    uint32 public totalEventsToEmit;
    
    mapping(uint256 => StoredEvent) public storedEvents;
    
    EnumerableSetLib.AddressSet factories;
    mapping(address => EnumerableSetLib.AddressSet) factoryToPairs;
    EnumerableSetLib.AddressSet pairCreateEventEmitted;
    
    EnumerableSetLib.AddressSet allERC20Tokens;
    mapping(address => EnumerableSetLib.AddressSet) erc20TokenToHolders;
    
    EnumerableSetLib.AddressSet allERC721Tokens;
    mapping(address => EnumerableSetLib.Uint256Set) erc721TokenToTokenIds;
    
    function recordEvent(
        bytes32 eventHash,
        bytes32[] memory topics,
        bytes memory data
    ) external whileInV1 {
        require(eventHash != bytes32(0), "Event hash cannot be zero");
        
        StoredEvent memory storedEvent = StoredEvent({
            emitter: msg.sender,
            eventHash: eventHash,
            topics: topics,
            data: data
        });
        
        storedEvents[lastStoredEventIndex] = storedEvent;
        
        unchecked { ++lastStoredEventIndex; }
    }
    
    function storedEventsCount() public view returns (uint256) {
        return lastStoredEventIndex - storedEventProcessedCount;
    }
    
    function getFactories() public view returns (address[] memory) {
        return factories.values();
    }
    
    function getFactoryToPairs(address factory) public view returns (address[] memory) {
        return factoryToPairs[factory].values();
    }
    
    function getAllERC20Tokens() public view returns (address[] memory) {
        return allERC20Tokens.values();
    }
    
    function getERC20TokenToHolders(address token) public view returns (address[] memory) {
        return erc20TokenToHolders[token].values();
    }
    
    function getAllERC721Tokens() public view returns (address[] memory) {
        return allERC721Tokens.values();
    }
    
    function getERC721TokenToTokenIds(address token) public view returns (uint256[] memory) {
        return erc721TokenToTokenIds[token].values();
    }
    
    function getPairCreateEventEmitted() public view returns (address[] memory) {
        return pairCreateEventEmitted.values();
    }
    
    function transactionsRequired() public view returns (uint256) {
        return (calculateTotalEventsToEmit() + MAX_EVENTS_PER_BATCH - 1) / MAX_EVENTS_PER_BATCH;
    }
    
    function recordERC20Holder(address holder) external whileInV1 {
        address token = msg.sender;
        
        allERC20Tokens.add(token);
        
        if (holder != address(0)) {
            erc20TokenToHolders[token].add(holder);
        }
    }
    
    function recordERC721TokenId(uint256 id) external whileInV1 {
        address token = msg.sender;
        
        allERC721Tokens.add(token);
        erc721TokenToTokenIds[token].add(id);
    }
    
    function recordPairCreation(address pair) external whileInV1 {
        address factory = msg.sender;
        
        factories.add(factory);
        factoryToPairs[factory].add(pair);
    }
    
    function calculateTotalEventsToEmit() public view returns (uint256) {
        unchecked {
            uint256 totalERC20Events = 0;
            uint256 erc20TokensLength = allERC20Tokens.length();
            for (uint256 i = 0; i < erc20TokensLength; i++) {
                address token = allERC20Tokens.at(i);
                totalERC20Events += erc20TokenToHolders[token].length();
            }
            
            uint256 totalERC721Events = 0;
            uint256 erc721TokensLength = allERC721Tokens.length();
            for (uint256 i = 0; i < erc721TokensLength; i++) {
                address token = allERC721Tokens.at(i);
                totalERC721Events += erc721TokenToTokenIds[token].length();
            }
            
            uint256 totalFactoriesEvents = 0;
            uint256 factoriesLength = factories.length();
            for (uint256 i = 0; i < factoriesLength; i++) {
                address factory = factories.at(i);
                uint256 pairCount = factoryToPairs[factory].length();
                totalFactoriesEvents += pairCount * 2;
            }
            
            return totalERC20Events + totalERC721Events + totalFactoriesEvents + storedEventsCount();
        }
    }
    
    function executeMigration() external whileInV2 returns (uint256 remainingEvents) {
        require(msg.sender == MigrationLib.SYSTEM_ADDRESS, "Only system address can call");
        require(!migrationExecuted, "Migration already executed");
        
        if (totalEventsToEmit == 0) {
            totalEventsToEmit = uint32(calculateTotalEventsToEmit());
        }
        
        currentBatchEmittedEvents = 0;
        
        processStoredEvents();
        
        processFactories();
        
        if (!batchFinished()) {
            processERC20Tokens();
        }
        if (!batchFinished()) {
            processERC721Tokens();
        }
        
        totalEmittedEvents += currentBatchEmittedEvents;
        remainingEvents = totalEventsToEmit - totalEmittedEvents;
        
        if (remainingEvents == 0) {
            migrationExecuted = true;
            
            require(calculateTotalEventsToEmit() == 0 , "Remaining events should match total events to emit");
        }
    }
    
    function batchFinished() public view returns (bool) {
        return currentBatchEmittedEvents >= MAX_EVENTS_PER_BATCH;
    }
    
    function processStoredEvents() internal whileInV2 {
        uint32 currentIndex = storedEventProcessedCount;
        uint32 endIndex = lastStoredEventIndex;
        
        unchecked {
            while (currentIndex < endIndex && !batchFinished()) {
                StoredEvent storage storedEvent = storedEvents[currentIndex];
                
                EventReplayable(storedEvent.emitter).emitStoredEvent(
                    storedEvent.eventHash,
                    storedEvent.topics,
                    storedEvent.data
                );
                delete storedEvents[currentIndex];
                
                currentIndex++;
                currentBatchEmittedEvents++;
            }
        }
        
        storedEventProcessedCount = currentIndex;
    }
    
    function processERC20Tokens() internal whileInV2 {
        unchecked {
            uint256 tokensLength = allERC20Tokens.length();
            for (uint256 i = tokensLength; i > 0; --i) {
                address token = allERC20Tokens.at(i - 1);
                
                migrateERC20(token);
                if (batchFinished()) return;
            }
        }
    }
    
    function processERC721Tokens() internal whileInV2 {
        unchecked {
            uint256 tokensLength = allERC721Tokens.length();
            for (uint256 i = tokensLength; i > 0; --i) {
                address token = allERC721Tokens.at(i - 1);
                
                migrateERC721(token);
                if (batchFinished()) return;
            }
        }
    }
    
    function processFactories() internal whileInV2 {
        unchecked {
            uint256 factoriesLength = factories.length();
            
            for (uint256 i = factoriesLength; i > 0; --i) {
                FacetSwapFactory factory = FacetSwapFactory(factories.at(i - 1));
                EnumerableSetLib.AddressSet storage pairs = factoryToPairs[address(factory)];
                
                uint256 pairsLength = pairs.length();
                for (uint256 j = pairsLength; j > 0; --j) {
                    FacetSwapPair pair = FacetSwapPair(pairs.at(j - 1));
                    address token0 = pair.token0();
                    address token1 = pair.token1();
                    
                    migrateERC20(token0);
                    if (batchFinished()) return;
                    
                    migrateERC20(token1);
                    if (batchFinished()) return;
                    
                    emitPairCreateEventIfNecessary({
                        factory: factory,
                        pair: address(pair),
                        token0: token0,
                        token1: token1,
                        pairLength: j
                    });
                    if (batchFinished()) return;
                    
                    migrateERC20(address(pair));
                    if (batchFinished()) return;
                    
                    pair.sync();
                    currentBatchEmittedEvents++;
                    
                    pairs.remove(address(pair));
                    
                    if (pairs.length() == 0) {
                        delete factoryToPairs[address(factory)];
                        factories.remove(address(factory));
                    }
                    
                    if (batchFinished()) return;
                }
            }
            
            // Empty pairCreateEventEmitted set
            uint256 emittedPairsLength = pairCreateEventEmitted.length();
            for (uint256 i = emittedPairsLength; i > 0; --i) {
                address pair = pairCreateEventEmitted.at(i - 1);
                pairCreateEventEmitted.remove(pair);
            }
        }
    }
    
    function emitPairCreateEventIfNecessary(
        FacetSwapFactory factory,
        address pair,
        address token0,
        address token1,
        uint256 pairLength
    ) internal {
        if (!pairCreateEventEmitted.contains(pair)) {
            pairCreateEventEmitted.add(pair);
            
            factory.emitPairCreated({
                token0: token0,
                token1: token1,
                pair: pair,
                pairLength: pairLength
            });
            
            currentBatchEmittedEvents++;
        }
    }
    
    function migrateERC20(address token) internal {
        unchecked {
            EnumerableSetLib.AddressSet storage holders = erc20TokenToHolders[token];
            
            uint256 holdersLength = holders.length();
            for (uint256 j = holdersLength; j > 0; --j) {
                address holder = holders.at(j - 1);
                uint256 balance = FacetERC20(token).balanceOf(holder);
                
                require(holder != address(0), "Should not happen");
                
                if (balance > 0) {
                    FacetERC20(token).emitTransferEvent({
                        to: holder,
                        amount: balance
                    });
                }
                
                currentBatchEmittedEvents++;
                holders.remove(holder);
                
                if (holders.length() == 0) {
                    delete erc20TokenToHolders[token];
                    allERC20Tokens.remove(token);
                }
                
                if (batchFinished()) return;
            }
        }
    }
    
    function migrateERC721(address token) internal {
        unchecked {
            EnumerableSetLib.Uint256Set storage tokenIds = erc721TokenToTokenIds[token];
            
            uint256 tokenIdsLength = tokenIds.length();
            for (uint256 j = tokenIdsLength; j > 0; --j) {
                uint256 tokenId = tokenIds.at(j - 1);
                address owner = FacetERC721(token).safeOwnerOf(tokenId);
                
                if (owner != address(0)) {
                    FacetERC721(token).emitTransferEvent({
                        to: owner,
                        id: tokenId
                    });
                }
                
                currentBatchEmittedEvents++;
                tokenIds.remove(tokenId);
                
                if (tokenIds.length() == 0) {
                    delete erc721TokenToTokenIds[token];
                    allERC721Tokens.remove(token);
                }
                
                if (batchFinished()) return;
            }
        }
    }
    
    modifier whileInV1() {
        require(!migrationExecuted, "Migration already executed");
        require(MigrationLib.isInV1(), "Not in V1");
        _;
    }
    
    modifier whileInV2() {
        require(MigrationLib.isInV2(), "Not in V2");
        _;
    }
}
