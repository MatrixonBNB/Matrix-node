// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/tokens/ERC20.sol";
import "./FacetBuddyLib.sol";
import "src/libraries/PublicImplementationAddress.sol";
import "solady/src/utils/LibString.sol";
import "./MigrationLib.sol";

abstract contract FacetERC20 is ERC20, PublicImplementationAddress {
    using LibString for *;
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
    
    error NotMigrationManager();
    function emitTransferEvent(address to, uint256 amount) external {
        address manager = MigrationLib.MIGRATION_MANAGER;
        assembly {
            if xor(caller(), manager) {
                mstore(0x00, 0x2fb9930a) // 0x3cc50b45 is the 4-byte selector of "NotMigrationManager()"
                revert(0x1C, 0x04) // returns the stored 4-byte selector from above
            }
        }
        
        emit Transfer({
            from: address(0),
            to: to,
            amount: amount
        });
    }
    
    function _afterTokenTransfer(address, address to, uint256) internal virtual override {
        if (MigrationLib.isInMigration()) {
            MigrationLib.manager().recordERC20Holder(to);
        }
    }
}
