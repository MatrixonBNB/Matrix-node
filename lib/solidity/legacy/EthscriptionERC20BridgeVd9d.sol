// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./FacetERC20.sol";
import "./Upgradeable.sol";
import "solady/src/utils/Initializable.sol";
import "solady/src/auth/Ownable.sol";

contract EthscriptionERC20BridgeVd9d is FacetERC20, Initializable, Upgradeable, Ownable {
    struct EthscriptionERC20BridgeStorage {
        uint256 mintAmount;
        address trustedSmartContract;
        mapping(address => uint256) bridgedInAmount;
        mapping(bytes32 => uint256) withdrawalIdAmount;
        mapping(address => bytes32) userWithdrawalId;
    }

    event BridgedIn(address indexed to, uint256 amount);
    event InitiateWithdrawal(address indexed from, uint256 amount, bytes32 withdrawalId);
    event WithdrawalComplete(address indexed to, uint256 amount, bytes32 withdrawalId);

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
        _initializeOwner(msg.sender);
        _initializeUpgradeAdmin(msg.sender);
    }

    function bridgeIn(address to, uint256 amount) public {
        require(msg.sender == s().trustedSmartContract, "Only the trusted smart contract can bridge in tokens");
        s().bridgedInAmount[to] += amount;
        _mint(to, amount * s().mintAmount * 1 ether);
        emit BridgedIn(to, amount);
    }

    function bridgeOut(uint256 amount) public {
        bytes32 withdrawalId = keccak256(abi.encodePacked(block.timestamp, msg.sender, amount));
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
}
