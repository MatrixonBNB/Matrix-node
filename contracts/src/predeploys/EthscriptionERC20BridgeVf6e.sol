// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetERC20.sol";
import "src/libraries/Upgradeable.sol";
import "solady/src/utils/Initializable.sol";

contract EthscriptionERC20BridgeVf6e is FacetERC20, Initializable, Upgradeable {
    struct EthscriptionERC20BridgeStorage {
        uint256 mintAmount;
        address trustedSmartContract;
        mapping(address => uint256) bridgedInAmount;
        mapping(bytes32 => uint256) withdrawalIdAmount;
        mapping(address => bytes32) userWithdrawalId;
        uint256 withdrawalIdNonce;
    }

    event BridgedIn(address indexed to, uint256 amount);
    event InitiateWithdrawal(address indexed from, uint256 amount, bytes32 indexed withdrawalId);
    event WithdrawalComplete(address indexed to, uint256 amount, bytes32 indexed withdrawalId);

    function s() internal pure returns (EthscriptionERC20BridgeStorage storage cs) {
        bytes32 position = keccak256("EthscriptionERC20BridgeStorage.contract.storage.v1");
        assembly {
            cs.slot := position
        }
    }

    constructor() {
      _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        uint256 mintAmount,
        address trustedSmartContract
    ) public initializer {
        require(mintAmount > 0, "Invalid mint amount");
        require(trustedSmartContract != address(0), "Invalid smart contract");
        s().mintAmount = mintAmount;
        s().trustedSmartContract = trustedSmartContract;
        _initializeERC20(name, symbol, 18);
        _initializeUpgradeAdmin(msg.sender);
    }
    
    function onUpgrade(address newTrustedSmartContract) public reinitializer(2) {
        s().trustedSmartContract = newTrustedSmartContract;
    }

    function bridgeIn(address to, uint256 amount) public {
        require(msg.sender == s().trustedSmartContract, "Only the trusted smart contract can bridge in tokens");
        s().bridgedInAmount[to] += amount;
        _mint(to, amount * s().mintAmount * 1 ether);
        emit BridgedIn(to, amount);
    }

    function bridgeOut(uint256 amount) public {
        bytes32 withdrawalId = generateWithdrawalId();
        
        require(s().userWithdrawalId[msg.sender] == bytes32(0), "Withdrawal pending");
        require(s().withdrawalIdAmount[withdrawalId] == 0, "Already bridged out");
        require(s().bridgedInAmount[msg.sender] >= amount, "Not enough bridged in");
        require(amount > 0, "Invalid amount");
        s().userWithdrawalId[msg.sender] = withdrawalId;
        s().withdrawalIdAmount[withdrawalId] = amount;
        s().bridgedInAmount[msg.sender] -= amount;
        _burn(msg.sender, amount * s().mintAmount * 1 ether);
        emit InitiateWithdrawal(msg.sender, amount, withdrawalId);
    }

    function markWithdrawalComplete(address to, bytes32 withdrawalId) public {
        require(msg.sender == s().trustedSmartContract, "Only the trusted smart contract can mark withdrawals as complete");
        require(s().userWithdrawalId[to] == withdrawalId, "Withdrawal id not found");
        uint256 amount = s().withdrawalIdAmount[withdrawalId];
        s().withdrawalIdAmount[withdrawalId] = 0;
        s().userWithdrawalId[to] = bytes32(0);
        emit WithdrawalComplete(to, amount, withdrawalId);
    }
    
    function generateWithdrawalId() internal returns (bytes32) {
        return keccak256(abi.encode(address(this), msg.sender, s().withdrawalIdNonce++));
    }
}
