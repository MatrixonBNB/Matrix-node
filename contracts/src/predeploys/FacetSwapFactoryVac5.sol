// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/Upgradeable.sol";
import "solady/src/utils/Initializable.sol";
import "solady/src/utils/LibString.sol";
import "src/libraries/LimitedLibMappedAddressSet.sol";
import "./FacetSwapPairVdfd.sol";
import "src/libraries/ERC1967Proxy.sol";
import "src/libraries/MigrationLib.sol";

contract FacetSwapFactoryVac5 is Initializable, Upgradeable {
    using LibString for *;
    using LimitedLibMappedAddressSet for LimitedLibMappedAddressSet.MappedSet;
    
    struct FacetSwapFactoryStorage {
        address feeTo;
        address feeToSetter;
        mapping(address => mapping(address => address)) getPair;
        address[] allPairs;
        LimitedLibMappedAddressSet.MappedSet pairsToMigrate;
        uint256 lpFeeBPS;
    }
    
    function s() internal pure returns (FacetSwapFactoryStorage storage fs) {
        bytes32 position = keccak256("FacetSwapFactoryStorage.contract.storage.v1");
        assembly {
            fs.slot := position
        }
    }

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairLength);

    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _feeToSetter) public initializer {
        s().feeToSetter = _feeToSetter;
        _initializeUpgradeAdmin(msg.sender);
    }

    function allPairsLength() public view returns (uint256) {
        return s().allPairs.length;
    }
    
    function getPair(address tokenA, address tokenB) public view returns (address pair) {
        return s().getPair[tokenA][tokenB];
    }
    
    function getAllPairs() public view returns (address[] memory) {
        return s().allPairs;
    }
    
    function feeTo() public view returns (address) {
        return s().feeTo;
    }

    function createPair(address tokenA, address tokenB) public returns (address pair) {
        require(tokenA != tokenB, "FacetSwapV1: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "FacetSwapV1: ZERO_ADDRESS");
        require(s().getPair[token0][token1] == address(0), "FacetSwapV1: PAIR_EXISTS");

        bytes32 hsh = keccak256(type(FacetSwapPairVdfd).creationCode);
        address implementationAddress = address(uint160(uint256(hsh)));
        
        bytes32 proxySalt = keccak256(abi.encodePacked(token0, token1));
        bytes memory initBytes = abi.encodeCall(FacetSwapPairVdfd.initialize, ());
        
        pair = address(new ERC1967Proxy{salt: proxySalt}(implementationAddress, initBytes));
        
        FacetSwapPairVdfd(pair).init(token0, token1);

        s().getPair[token0][token1] = pair;
        s().getPair[token1][token0] = pair;
        s().allPairs.push(pair);

        if (MigrationLib.isInMigration()) {
            s().pairsToMigrate.add(pair);
        } else {
            require(allPairsInitialized(), "Migrated pairs not initialized");
        }

        emit PairCreated(token0, token1, pair, s().allPairs.length);
    }

    function setFeeTo(address _feeTo) public {
        require(msg.sender == s().feeToSetter, "FacetSwapV1: FORBIDDEN");
        s().feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) public {
        require(msg.sender == s().feeToSetter, "FacetSwapV1: FORBIDDEN");
        s().feeToSetter = _feeToSetter;
    }
    
    function lpFeeBPS() public view returns (uint256) {
        return s().lpFeeBPS;
    }
    
    function setLpFeeBPS(uint256 lpFeeBPS) public {
        require(msg.sender == s().feeToSetter, "FacetSwapV1: FORBIDDEN");
        require(lpFeeBPS <= 10000, "Fees cannot exceed 100%");
        s().lpFeeBPS = lpFeeBPS;
    }
    
    function upgradePairs(address[] calldata pairs, bytes32 newHash, string calldata newSource) public {
        require(msg.sender == upgradeAdmin(), "NOT_AUTHORIZED");
        require(pairs.length <= 10, "Too many pairs to upgrade at once");
        
        for (uint256 i = 0; i < pairs.length; i++) {
            address pair = pairs[i];
            upgradePair(pair, newHash, "");
        }
    }

    function upgradePair(address pair, bytes32 newHash, string memory newSource) public {
        require(msg.sender == upgradeAdmin(), "NOT_AUTHORIZED");
        Upgradeable(pair).upgrade(newHash, newSource);
    }
    
    function allPairsInitialized() public view returns (bool) {
        return s().pairsToMigrate.length() == 0;
    }
    
    function initAllPairsFromMigration() external {
        require(MigrationLib.isNotInMigration(), "Still migrating");
        
        FacetSwapFactoryStorage storage fs = s();
        
        for (uint256 i = 0; i < fs.pairsToMigrate.length(); i++) {
            address pair = fs.pairsToMigrate.at(i);
            FacetERC20 token0 = FacetERC20(FacetSwapPairVdfd(pair).getToken0());
            FacetERC20 token1 = FacetERC20(FacetSwapPairVdfd(pair).getToken1());
            
            token0.initAllBalances();
            token1.initAllBalances();
            
            emit PairCreated(address(token0), address(token1), pair, i + 1);
            
            FacetERC20(pair).initAllBalances();
            FacetSwapPairVdfd(pair).sync();
            
            fs.pairsToMigrate.removeFromMapping(pair);
        }
        
        fs.pairsToMigrate.clearArray();
    }
}
