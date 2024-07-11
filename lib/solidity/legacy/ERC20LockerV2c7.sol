// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./FacetOwnable.sol";
import "./Upgradeable.sol";
import "./Pausable.sol";
import "./FacetERC20.sol";
import "solady/src/utils/Initializable.sol";
import "solady/src/utils/SafeTransferLib.sol";

contract ERC20LockerV2c7 is FacetOwnable, Upgradeable, Pausable, Initializable {
    using SafeTransferLib for address;
    
    event Deposit(address indexed token, uint256 amount, uint256 lockDate, uint256 unlockDate, address indexed withdrawer, uint256 lockId);
    event Relock(address indexed token, uint256 lockId, uint256 unlockDate);
    event Withdraw(address indexed token, uint256 amount, address indexed withdrawer, uint256 lockId);

    struct TokenLock {
        uint256 lockId;
        address token;
        address owner;
        uint256 amount;
        uint256 lockDate;
        uint256 unlockDate;
    }

    struct ERC20LockerStorage {
        uint256 nextLockId;
        mapping(uint256 => TokenLock) tokenLocks;
    }

    function s() internal pure returns (ERC20LockerStorage storage ls) {
        bytes32 position = keccak256("ERC20LockerStorage.contract.storage.v1");
        assembly {
            ls.slot := position
        }
    }

    function initialize() public initializer {
        s().nextLockId = 1;
        _initializeUpgradeAdmin(msg.sender);
        _initializeOwner(msg.sender);
    }

    function lockToken(address token, uint256 amount, uint256 unlockDate, address withdrawer) public whenNotPaused {
        require(unlockDate < 10000000000, "Timestamp is in seconds");
        require(unlockDate > block.timestamp, "Unlock time must be in the future");
        require(amount > 0, "Amount must be greater than 0");
        require(withdrawer != address(0), "Invalid withdrawer");
        token.safeTransferFrom(msg.sender, address(this), amount);

        TokenLock memory tokenLock = TokenLock({
            lockId: s().nextLockId,
            token: token,
            owner: withdrawer,
            amount: amount,
            lockDate: block.timestamp,
            unlockDate: unlockDate
        });

        require(s().tokenLocks[tokenLock.lockId].lockId == 0, "Lock already exists");

        s().tokenLocks[tokenLock.lockId] = tokenLock;
        s().nextLockId += 1;

        emit Deposit(tokenLock.token, tokenLock.amount, tokenLock.lockDate, tokenLock.unlockDate, tokenLock.owner, tokenLock.lockId);
    }

    function relock(uint256 lockId, uint256 unlockDate) public {
        TokenLock storage tokenLock = s().tokenLocks[lockId];
        require(tokenLock.owner == msg.sender, "Only owner");
        require(unlockDate < 10000000000, "Timestamp is in seconds");
        require(unlockDate > block.timestamp, "Unlock time must be in the future");
        require(unlockDate > tokenLock.unlockDate, "Unlock date must be after current unlock date");

        tokenLock.unlockDate = unlockDate;
        emit Relock(tokenLock.token, lockId, unlockDate);
    }

    function withdraw(uint256 lockId, uint256 amount) public {
        TokenLock storage tokenLock = s().tokenLocks[lockId];
        require(tokenLock.owner == msg.sender, "Only owner");
        require(amount > 0, "Amount must be greater than 0");
        require(tokenLock.lockId != 0, "Lock does not exist");
        require(block.timestamp > tokenLock.unlockDate, "Tokens are still locked");
        require(tokenLock.amount >= amount, "Insufficient balance");

        tokenLock.amount -= amount;
        address token = tokenLock.token;

        if (tokenLock.amount == 0) {
            delete s().tokenLocks[lockId];
        }

        token.safeTransfer(msg.sender, amount);
        emit Withdraw(token, amount, msg.sender, lockId);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
