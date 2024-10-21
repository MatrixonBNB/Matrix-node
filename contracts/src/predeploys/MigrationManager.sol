// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetERC20.sol";
import "src/libraries/FacetERC721.sol";
import "lib/solady/src/utils/EnumerableSetLib.sol";
import "lib/solady/src/utils/LibString.sol";
import "src/libraries/MigrationLib.sol";

interface FacetSwapFactory {
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
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;
    
    bool migrationExecuted;
    EnumerableSetLib.AddressSet factories;
    EnumerableSetLib.AddressSet allERC20Tokens;
    mapping(address => EnumerableSetLib.AddressSet) erc20TokenToHolders;
    
    EnumerableSetLib.AddressSet allERC721Tokens;
    mapping(address => EnumerableSetLib.Uint256Set) erc721TokenToTokenIds;
    
    function registerFactory(address factory) external whileInV1 {
        factories.add(factory);
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
    
    function executeMigration() external whileInV2 {
        require(msg.sender == MigrationLib.SYSTEM_ADDRESS, "Only system address can call");
        require(!migrationExecuted, "Migration already executed");
        migrationExecuted = true;
        
        processFactories();    
        processERC20Tokens();
        processERC721Tokens();
    }
    
    function processERC20Tokens() internal whileInV2 {
        uint256 tokensLength = allERC20Tokens.length();
        for (uint256 i = tokensLength; i > 0; --i) {
            address token = allERC20Tokens.at(i - 1);
            migrateERC20(token);
        }
    }
    
    function processERC721Tokens() internal whileInV2 {
        uint256 tokensLength = allERC721Tokens.length();
        for (uint256 i = tokensLength; i > 0; --i) {
            address token = allERC721Tokens.at(i - 1);
            migrateERC721(token);
        }
    }
    
    function processFactories() internal whileInV2 {
        uint256 factoriesLength = factories.length();
        
        for (uint256 i = factoriesLength; i > 0; --i) {
            FacetSwapFactory factory = FacetSwapFactory(factories.at(i - 1));
            
            uint256 allPairsLength = factory.allPairsLength();
            for (uint256 j = 0; j < allPairsLength; j++) {
                FacetSwapPair pair = FacetSwapPair(factory.allPairs(j));
                address token0 = pair.token0();
                address token1 = pair.token1();
                
                migrateERC20(token0);
                migrateERC20(token1);
                
                factory.emitPairCreated(address(pair), token0, token1, j + 1);
                
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
            
            if (balance > 0 && holder != address(0)) {
                FacetERC20(token).emitTransferEvent(holder, balance);
            }
            
            holders.remove(holder);
        }
        
        delete erc20TokenToHolders[token];
        allERC20Tokens.remove(token);
    }
    
    function migrateERC721(address token) internal {
        EnumerableSetLib.Uint256Set storage tokenIds = erc721TokenToTokenIds[token];
        
        uint256 tokenIdsLength = tokenIds.length();
        for (uint256 j = tokenIdsLength; j > 0; --j) {
            uint256 tokenId = tokenIds.at(j - 1);
            address owner = FacetERC721(token).safeOwnerOf(tokenId);
            
            if (owner != address(0)) {
                FacetERC721(token).emitTransferEvent(owner, tokenId);
            }
            
            tokenIds.remove(tokenId);
        }
        
        delete erc721TokenToTokenIds[token];
        allERC721Tokens.remove(token);
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
