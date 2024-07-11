// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Upgradeable.sol";
import "solady/src/utils/Initializable.sol";
import "./FacetERC20.sol";
import "./FacetOwnable.sol";
import "./BridgeAndCallHelperVc14.sol";

contract EtherBridgeV0ee is FacetERC20, Initializable, Upgradeable, FacetOwnable {
    struct BridgeStorage {
        address trustedSmartContract;
        mapping(bytes32 => uint256) withdrawalIdAmount;
        mapping(address => bytes32) userWithdrawalId;
        uint256 withdrawalIdNonce;
        address bridgeAndCallHelper;
    }
    
    function s() internal pure returns (BridgeStorage storage cs) {
        bytes32 position = keccak256("BridgeStorage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
    
    event BridgedIn(address indexed to, uint256 amount);
    event InitiateWithdrawal(address indexed from, uint256 amount, bytes32 withdrawalId);
    event WithdrawalComplete(address indexed to, uint256 amount, bytes32 withdrawalId);

    constructor() {
      _disableInitializers();
    }
    
    function initialize(
        string memory name,
        string memory symbol,
        address trustedSmartContract,
        address bridgeAndCallHelper
    ) public initializer {
        require(trustedSmartContract != address(0), "Invalid smart contract");
        s().trustedSmartContract = trustedSmartContract;
        s().bridgeAndCallHelper = bridgeAndCallHelper;
        _initializeUpgradeAdmin(msg.sender);
        _initializeERC20(name, symbol, 18);
        _initializeOwner(msg.sender);
    }
    
    function onUpgrade(address owner, address bridgeAndCallHelper) public {
        require(msg.sender == address(this), "Only the contract itself can upgrade");
        _setOwner(owner);
        s().bridgeAndCallHelper = bridgeAndCallHelper;
    }

    function setBridgeAndCallHelper(address bridgeAndCallHelper) public onlyOwner {
        s().bridgeAndCallHelper = bridgeAndCallHelper;
    }

    function bridgeIn(address to, uint256 amount) public {
        require(msg.sender == s().trustedSmartContract, "Only the trusted smart contract can bridge in tokens");
        _mint(to, amount);
        emit BridgedIn(to, amount);
    }
    
    function bridgeAndCall(address to, uint256 amount, address addressToCall, string memory base64Calldata) public {
        if (s().bridgeAndCallHelper == address(0)) {
            bridgeIn(to, amount);
            return;
        }
        bridgeIn(s().bridgeAndCallHelper, amount);
        BridgeAndCallHelperVc14(s().bridgeAndCallHelper).callFromBridge(to, addressToCall, base64Calldata);
    }

    function bridgeOut(uint256 amount) public {
        bytes32 withdrawalId = generateWithdrawalId();
        
        require(s().userWithdrawalId[msg.sender] == bytes32(0), "Withdrawal pending");
        require(s().withdrawalIdAmount[withdrawalId] == 0, "Already bridged out");
        require(amount > 0, "Invalid amount");

        s().userWithdrawalId[msg.sender] = withdrawalId;
        s().withdrawalIdAmount[withdrawalId] = amount;
        _burn(msg.sender, amount);
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
