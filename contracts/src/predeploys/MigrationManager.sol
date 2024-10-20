// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetERC20.sol";
import "lib/solady/src/utils/EnumerableSetLib.sol";
import "src/libraries/MigrationLib.sol";

interface FacetSwapFactory {
    function getPair(address token0, address token1) external view returns (address pair);
    function allPairs(uint256 index) external view returns (address);
    function allPairsLength() external view returns (uint256);
    function emitPairCreated(address pair, address token0, address token1, uint256 pairLength) external;
}

interface FacetSwapPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function sync() external;
}

contract MigrationManager {
    using EnumerableSetLib for EnumerableSetLib.AddressSet;
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    
    bool migrationExecuted;
    EnumerableSetLib.AddressSet factories;
    EnumerableSetLib.AddressSet allERC20Tokens;
    
    mapping(address => EnumerableSetLib.AddressSet) erc20TokenToHolders;
    
    function registerFactory(address factory) external whileInV1 {
        factories.add(factory);
    }
    
    function recordTransfer(address to, uint96 currentBalance) external whileInV1 {
        address token = msg.sender;
        
        allERC20Tokens.add(token);
        
        if (currentBalance > 0) {
            erc20TokenToHolders[token].add(to);
        } else {
            erc20TokenToHolders[token].remove(to);
        }
    }
    
    function executeMigration() external whileInV2 {
        require(msg.sender == MigrationLib.MIGRATOR_ADDRESS, "Only migrator can call");
        require(!migrationExecuted, "Migration already executed");
        migrationExecuted = true;
        
        processFactories();    
        processERC20Tokens();
    }
    
    function processERC20Tokens() internal whileInV2 {
        uint256 tokensLength = allERC20Tokens.length();
        for (uint256 i = tokensLength; i > 0; --i) {
            address token = allERC20Tokens.at(i - 1);
            migrateERC20(token);
        }
    }
    
    function processFactories() internal whileInV2 {
        uint256 factoriesLength = factories.length();
        
        for (uint256 i = factoriesLength; i > 0; --i) {
            FacetSwapFactory factory = FacetSwapFactory(factories.at(i - 1));
            
            uint256 allPairsLength = factory.allPairsLength();
            for (uint256 j = 0; j < allPairsLength; j++) {
                FacetSwapPair pair = FacetSwapPair(factory.allPairs(j));
                FacetERC20 token0 = FacetERC20(pair.token0());
                FacetERC20 token1 = FacetERC20(pair.token1());
                
                migrateERC20(address(token0));
                migrateERC20(address(token1));
                
                factory.emitPairCreated(address(pair), address(token0), address(token1), j + 1);
                
                migrateERC20(address(pair));
                pair.sync();
            }
            
            factories.remove(address(factory));
        }
    }
    
    function migrateERC20(address token) internal {
        EnumerableSetLib.AddressSet storage holders = erc20TokenToHolders[token];
        
        uint256 holdersLength = holders.length();
        for (uint256 j = holdersLength; j > 0; --j) {
            address holder = holders.at(j - 1);
            uint256 balance = FacetERC20(token).balanceOf(holder);
            
            if (balance > 0) {
                FacetERC20(token).emitTransferEvent(holder, uint96(balance));
            }
            
            holders.remove(holder);
        }
        
        delete erc20TokenToHolders[token];
        allERC20Tokens.remove(token);
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
