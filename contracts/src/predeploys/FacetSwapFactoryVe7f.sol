// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/Upgradeable.sol";
import "solady/src/utils/Initializable.sol";
import "src/predeploys/FacetSwapPairV2b2.sol";
import "src/libraries/ERC1967Proxy.sol";
import "src/libraries/MigrationLib.sol";

contract FacetSwapFactoryVe7f is Initializable, Upgradeable {
    struct FacetSwapFactoryStorage {
        address feeTo;
        address feeToSetter;
        mapping(address => mapping(address => address)) getPair;
        address[] allPairs;
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
    
    function allPairs(uint256 index) public view returns (address) {
        return s().allPairs[index];
    }

    function getAllPairs() public view returns (address[] memory) {
        return s().allPairs;
    }
    
    function getPair(address tokenA, address tokenB) public view returns (address pair) {
        return s().getPair[tokenA][tokenB];
    }
    
    function feeTo() public view returns (address) {
        return s().feeTo;
    }
    
    function feeToSetter() public view returns (address) {
        return s().feeToSetter;
    }

    function createPair(address tokenA, address tokenB) public returns (address pair) {
        require(tokenA != tokenB, "FacetSwapV1: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "FacetSwapV1: ZERO_ADDRESS");
        require(s().getPair[token0][token1] == address(0), "FacetSwapV1: PAIR_EXISTS");

        bytes32 hsh = keccak256(type(FacetSwapPairV2b2).creationCode);
        address implementationAddress = address(uint160(uint256(hsh)));
        
        bytes32 proxySalt = keccak256(abi.encodePacked(token0, token1));
        bytes memory initBytes = abi.encodeCall(FacetSwapPairV2b2.initialize, ());
        
        pair = address(new ERC1967Proxy{salt: proxySalt}(implementationAddress, initBytes));

        FacetSwapPairV2b2(pair).init(token0, token1);

        s().getPair[token0][token1] = pair;
        s().getPair[token1][token0] = pair;
        s().allPairs.push(pair);

        if (MigrationLib.isInMigration()) {
            MigrationLib.manager().recordPairCreation(pair);
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
    
    function emitPairCreated(address token0, address token1, address pair, uint256 pairLength) public {
        require(msg.sender == MigrationLib.MIGRATION_MANAGER, "Only migration manager can call");
        emit PairCreated(token0, token1, pair, pairLength);
    }
}
