// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetERC20.sol";
import "src/libraries/Upgradeable.sol";
import "src/libraries/FacetOwnable.sol";
import "src/libraries/Pausable.sol";
import "solady/src/utils/Initializable.sol";

/// @title IL1Block
/// @notice Minimal interface for accessing L1 block information
interface IL1Block {
    /// @notice The latest L1 block number
    function number() external view returns (uint64);

    /// @notice The latest L1 blockhash
    function hash() external view returns (bytes32);
}

contract EthscriptionERC20BridgeV6e4 is FacetERC20, Initializable, Pausable, Upgradeable, FacetOwnable {
    IL1Block public constant l1Block = IL1Block(0x4200000000000000000000000000000000000015);
    
    struct EthscriptionERC20BridgeStorage {
        uint256 mintAmount;
        address trustedSmartContract;
        mapping(address => uint256) _bridgedInAmount;
        mapping(bytes32 => uint256) withdrawalIdAmount;
        mapping(address => bytes32) userWithdrawalId;
        uint256 withdrawalIdNonce;
        uint256 bridgeLimit;
        
        int256 totalBridgedIn;
        int256 totalWithdrawComplete;
        int256 pendingWithdrawalAmount;
        
        mapping(bytes32 => address) withdrawalIdUser;
        mapping(bytes32 => bytes32) withdrawalIdL1BlockHash;
        mapping(bytes32 => uint256) withdrawalIdL1BlockNumber;
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
    
    modifier withInvariantCheck() {
        _;
        require(_verifyInvariants(), "Invariants check failed");
    }

    constructor() {
      _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        uint256 mintAmount,
        address trustedSmartContract,
        uint256 bridgeLimit,
        bool initialPauseState
    ) public initializer {
        require(mintAmount > 0, "Invalid mint amount");
        require(trustedSmartContract != address(0), "Invalid smart contract");
        s().mintAmount = mintAmount;
        s().trustedSmartContract = trustedSmartContract;
        _initializeERC20(name, symbol, 18);
        _initializeOwner(msg.sender);
        _initializeUpgradeAdmin(msg.sender);
        _initializePausable(initialPauseState);
        s().bridgeLimit = bridgeLimit;
    }
    
    function l2TokenAmount(uint256 l1Amount) public view returns (uint256) {
        return l1Amount * s().mintAmount * 1 ether;
    }
    
    function bridgeIn(address to, uint256 amount) public withInvariantCheck {
        require(msg.sender == s().trustedSmartContract, "Only the trusted smart contract can bridge in tokens");
        
        uint256 l1TokenAmount = amount;
        uint256 l2TokenAmount = l2TokenAmount(l1TokenAmount);
        
        _mint(to, l2TokenAmount);
        s().totalBridgedIn += int256(l2TokenAmount);
        emit BridgedIn(to, l1TokenAmount);
    }
    
    function bridgeOut(uint256 amount) public whenNotPaused withInvariantCheck {
        uint256 l1TokenAmount = amount;
        require(s().bridgeLimit > 0 && l1TokenAmount <= s().bridgeLimit, "Amount is too large");
        require(l1TokenAmount > 0, "Invalid amount");
        
        uint256 l2TokenAmount = l2TokenAmount(l1TokenAmount);
        bytes32 withdrawalId = generateWithdrawalId();
        
        _createWithdrawal({
            recipient: msg.sender,
            withdrawalId: withdrawalId,
            l1TokenAmount: l1TokenAmount
        });
        
        _burn(msg.sender, l2TokenAmount);
        
        s().pendingWithdrawalAmount += int256(l2TokenAmount);
        
        emit InitiateWithdrawal(msg.sender, l1TokenAmount, withdrawalId);
    }

    function markWithdrawalComplete(address to, bytes32 withdrawalId) public withInvariantCheck {
        require(msg.sender == s().trustedSmartContract, "Only the trusted smart contract can mark withdrawals as complete");
        require(s().userWithdrawalId[to] == withdrawalId, "Withdrawal id not found");
        
        uint256 l1TokenAmount = s().withdrawalIdAmount[withdrawalId];
        uint256 l2TokenAmount = l2TokenAmount(l1TokenAmount);
        
        _deleteWithdrawal(to, withdrawalId);
        
        s().totalWithdrawComplete += int256(l2TokenAmount);
        s().pendingWithdrawalAmount -= int256(l2TokenAmount);
        
        emit WithdrawalComplete(to, l1TokenAmount, withdrawalId);
    }
    
    function onUpgrade(address owner, uint256 bridgeLimit) public onlyUpgradeAdmin reinitializer(3) {
        _setOwner(owner);
        s().bridgeLimit = bridgeLimit;
    }

    function setBridgeLimit(uint256 bridgeLimit) public onlyOwner {
        s().bridgeLimit = bridgeLimit;
    }

    function updateTrustedSmartContract(address newTrustedSmartContract) public onlyOwner {
        require(newTrustedSmartContract != address(0), "Invalid smart contract");
        s().trustedSmartContract = newTrustedSmartContract;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
    
    function getPendingWithdrawalAmount() public view returns (int256) {
        return s().pendingWithdrawalAmount;
    }
    
    function getTotalBridgedIn() public view returns (int256) {
        return s().totalBridgedIn;
    }

    function getTotalWithdrawComplete() public view returns (int256) {
        return s().totalWithdrawComplete;
    }
    
    function getMintAmount() public view returns (uint256) {
        return s().mintAmount;
    }
    
    function getBridgeLimit() public view returns (uint256) {
        return s().bridgeLimit;
    }
    
    function getTrustedSmartContract() public view returns (address) {
        return s().trustedSmartContract;
    }

    function getWithdrawalIdAmount(bytes32 withdrawalId) public view returns (uint256) {
        return s().withdrawalIdAmount[withdrawalId];
    }
    
    function getWithdrawalIdUser(bytes32 withdrawalId) public view returns (address) {
        return s().withdrawalIdUser[withdrawalId];
    }

    function getUserWithdrawalId(address user) public view returns (bytes32) {
        return s().userWithdrawalId[user];
    }
    
    function getWithdrawalIdL1BlockHash(bytes32 withdrawalId) public view returns (bytes32) {
        return s().withdrawalIdL1BlockHash[withdrawalId];
    }

    function getWithdrawalIdL1BlockNumber(bytes32 withdrawalId) public view returns (uint256) {
        return s().withdrawalIdL1BlockNumber[withdrawalId];
    }

    function getWithdrawalIdNonce() public view returns (uint256) {
        return s().withdrawalIdNonce;
    }
    
    function generateWithdrawalId() internal returns (bytes32) {
        s().withdrawalIdNonce++;
        return keccak256(abi.encode(address(this), msg.sender, s().withdrawalIdNonce));
    }
    
    function _withdrawalDoesNotExist(address user, bytes32 withdrawalId) internal view returns (bool) {
        return s().withdrawalIdAmount[withdrawalId] == 0 &&
            s().withdrawalIdUser[withdrawalId] == address(0) &&
            s().withdrawalIdL1BlockHash[withdrawalId] == bytes32(0) &&
            s().withdrawalIdL1BlockNumber[withdrawalId] == 0 &&
            s().userWithdrawalId[user] == bytes32(0);
    }
    
    function _createWithdrawal(
        address recipient,
        bytes32 withdrawalId,
        uint256 l1TokenAmount
    ) internal {
        require(_withdrawalDoesNotExist(recipient, withdrawalId), "Withdrawal already exists");
        
        s().withdrawalIdAmount[withdrawalId] = l1TokenAmount;
        s().withdrawalIdUser[withdrawalId] = recipient;
        s().withdrawalIdL1BlockHash[withdrawalId] = l1Block.hash();
        s().withdrawalIdL1BlockNumber[withdrawalId] = l1Block.number();
        s().userWithdrawalId[recipient] = withdrawalId;
    }
    
    function _deleteWithdrawal(address user, bytes32 withdrawalId) internal {
        s().withdrawalIdAmount[withdrawalId] = 0;
        s().withdrawalIdUser[withdrawalId] = address(0);
        s().withdrawalIdL1BlockHash[withdrawalId] = bytes32(0);
        s().withdrawalIdL1BlockNumber[withdrawalId] = 0;
        s().userWithdrawalId[user] = bytes32(0);
    }
    
    function consistencyCheck() public view returns (int256) {
        int256 rhs = s().totalBridgedIn - s().totalWithdrawComplete;
        int256 lhs = int256(totalSupply()) + s().pendingWithdrawalAmount;
        
        return lhs - rhs;
    }
        
    function adminResetInvariants() public onlyOwner {
        int256 diff = consistencyCheck();
        if (diff > 0) {
            s().totalBridgedIn += diff;
        } else if (diff < 0) {
            s().pendingWithdrawalAmount += diff;
        }
    }
    
    function _verifyInvariants() internal view returns (bool) {
        if (MigrationLib.isInMigration()) return true;
        
        bool c1 = int256(totalSupply()) == s().totalBridgedIn - s().totalWithdrawComplete - s().pendingWithdrawalAmount;
        bool c2 = s().totalWithdrawComplete + s().pendingWithdrawalAmount <= s().totalBridgedIn;
        return c1 && c2;
    }
}
