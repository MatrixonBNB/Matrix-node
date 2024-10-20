// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/tokens/ERC20.sol";
import "./FacetBuddyLib.sol";
import "src/libraries/PublicImplementationAddress.sol";
import "solady/src/utils/LibString.sol";
import "solady/src/utils/SafeCastLib.sol";
import "./MigrationLib.sol";
import "src/predeploys/MigrationManager.sol";

abstract contract FacetERC20 is ERC20, PublicImplementationAddress {
    using LibString for *;
    using SafeCastLib for *;
    using FacetBuddyLib for address;
    
    struct FacetERC20Storage {
        string name;
        string symbol;
        uint8 decimals;
    }
    
    function _FacetERC20Storage() internal pure returns (FacetERC20Storage storage cs) {
        bytes32 position = keccak256("FacetERC20Storage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
    
    function _initializeERC20(string memory name, string memory symbol, uint8 decimals) internal {
        _FacetERC20Storage().name = name;
        _FacetERC20Storage().symbol = symbol;
        _FacetERC20Storage().decimals = decimals;
    }
    
    function name() public view virtual override returns (string memory) {
        return _FacetERC20Storage().name;
    }
    
    function symbol() public view virtual override returns (string memory) {
        return _FacetERC20Storage().symbol;
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _FacetERC20Storage().decimals;
    }
    
    function transferFrom(address from, address to, uint amount) public override returns (bool) {
        if (msg.sender.isBuddyOfUser(from)) {
            super._approve(from, msg.sender, type(uint256).max);
        }
        
        return super.transferFrom(from, to, amount);
    }
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        if (spender.isBuddyOfUser(owner)) {
            return type(uint256).max;
        }
        
        return super.allowance(owner, spender);
    }
    
    function emitTransferEvent(address to, uint96 value) external {
        require(msg.sender == MigrationLib.MIGRATION_MANAGER, "Only migration manager can call");
        emit Transfer(address(0), to, value);
    }
    
    function _afterTokenTransfer(address from, address to, uint256) internal virtual override {
        if (MigrationLib.isInMigration()) {
            if (from != address(0)) {  // Skip for minting operations
                uint96 fromBalance = balanceOf(from).toUint96();
                MigrationManager(MigrationLib.MIGRATION_MANAGER).recordTransfer(from, fromBalance);
            }
            if (to != address(0)) {  // Skip for burning operations
                uint96 toBalance = balanceOf(to).toUint96();
                MigrationManager(MigrationLib.MIGRATION_MANAGER).recordTransfer(to, toBalance);
            }
        }
    }
}
