// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/Upgradeable.sol";
import "solady/utils/Initializable.sol";
import "solady/utils/Base64.sol";
import "src/libraries/FacetERC20.sol";
import "src/libraries/FacetOwnable.sol";
import "./FacetBuddyFactoryVef8.sol";
import "src/libraries/MigrationLib.sol";
import "src/libraries/Pausable.sol";

contract EtherBridgeVae4 is FacetERC20, Initializable, Upgradeable, FacetOwnable, Pausable {
    struct BridgeStorage {
        address trustedSmartContract;
        mapping(bytes32 => uint256) withdrawalIdAmount;
        mapping(address => bytes32) userWithdrawalId;
        uint256 withdrawalIdNonce;
        address _bridgeAndCallHelper;
        address facetBuddyFactory;
    }
    
    function s() internal pure returns (BridgeStorage storage cs) {
        bytes32 position = keccak256("BridgeStorage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
    
    event BridgedIn(address indexed to, uint256 amount);
    event InitiateWithdrawal(address indexed from, uint256 amount, bytes32 indexed withdrawalId);
    event WithdrawalComplete(address indexed to, uint256 amount, bytes32 indexed withdrawalId);

    constructor() {
      _disableInitializers();
    }
    
    function initialize(
        string memory name,
        string memory symbol,
        address trustedSmartContract
    ) public initializer {
        require(trustedSmartContract != address(0), "Invalid smart contract");
        s().trustedSmartContract = trustedSmartContract;
        _initializeUpgradeAdmin(msg.sender);
        _initializeERC20(name, symbol, 18);
        _initializeOwner(msg.sender);
    }
    
    function setTrustedSmartContract(address trustedSmartContract) public onlyOwner {
        s().trustedSmartContract = trustedSmartContract;
    }
    
    function setFacetBuddyFactory(address facetBuddyFactory) public onlyOwner {
        s().facetBuddyFactory = facetBuddyFactory;
    }

    function bridgeIn(address to, uint256 amount) public {
        require(msg.sender == s().trustedSmartContract, "Only the trusted smart contract can bridge in tokens");
        _mint(to, amount);
        emit BridgedIn(to, amount);
    }
    
    function bridgeAndCall(
        address to,
        uint256 amount,
        address addressToCall,
        string memory base64Calldata
    ) public {
        if (MigrationLib.isNotInMigration() || s().facetBuddyFactory == address(0)) {
            bridgeIn(to, amount);
            return;
        }

        address buddy = FacetBuddyFactoryVef8(s().facetBuddyFactory).findOrCreateBuddy(to);
        bridgeIn(buddy, amount);
        FacetBuddyVe5c(buddy).callFromBridge(addressToCall, Base64.decode(base64Calldata));
    }

    function predictBuddyAddress(address forUser) public view returns (address) {
        return FacetBuddyFactoryVef8(s().facetBuddyFactory).predictBuddyAddress(forUser);
    }

    function bridgeOut(uint256 amount) public whenNotPaused {
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
    
    function getTrustedSmartContract() public view returns (address) {
        return s().trustedSmartContract;
    }

    function getWithdrawalIdAmount(bytes32 withdrawalId) public view returns (uint256) {
        return s().withdrawalIdAmount[withdrawalId];
    }

    function getUserWithdrawalId(address user) public view returns (bytes32) {
        return s().userWithdrawalId[user];
    }

    function getWithdrawalIdNonce() public view returns (uint256) {
        return s().withdrawalIdNonce;
    }

    function getBridgeAndCallHelper() public view returns (address) {
        return s()._bridgeAndCallHelper;
    }

    function getFacetBuddyFactory() public view returns (address) {
        return s().facetBuddyFactory;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
