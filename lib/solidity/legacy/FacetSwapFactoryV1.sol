// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Upgradeable.sol";
import "solady/src/utils/Initializable.sol";
import "./FacetSwapPairV1.sol";

contract FacetSwapFactoryV1 is Initializable, Upgradeable {
    struct FacetSwapV1FactoryStorage {
        address feeTo;
        address feeToSetter;
        mapping(address => mapping(address => address)) getPair;
        address[] allPairs;
    }

    function s() internal pure returns (FacetSwapV1FactoryStorage storage fs) {
        bytes32 position = keccak256("FacetSwapV1FactoryStorage.contract.storage.v1");
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

    function getAllPairs() public view returns (address[] memory) {
        return s().allPairs;
    }
    
    function getPair(address tokenA, address tokenB) public view returns (address pair) {
        return s().getPair[tokenA][tokenB];
    }

    function createPair(address tokenA, address tokenB) public returns (address pair) {
        require(tokenA != tokenB, "FacetSwapV1: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "FacetSwapV1: ZERO_ADDRESS");
        require(s().getPair[token0][token1] == address(0), "FacetSwapV1: PAIR_EXISTS");

        // bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // pair = address(new FacetSwapPairV1{salt: salt}());
        // FacetSwapPairV1(pair).initialize(token0, token1);
        
        bytes memory bytecode = type(FacetSwapPairV1).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        FacetSwapPairV1(pair).initialize(token0, token1);
        

        s().getPair[token0][token1] = pair;
        s().getPair[token1][token0] = pair;
        s().allPairs.push(pair);

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
}
