// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/tokens/ERC20.sol";
import "./FacetBuddyLib.sol";
import "src/libraries/PublicImplementationAddress.sol";
import "solady/src/utils/LibString.sol";

abstract contract FacetERC20 is ERC20, PublicImplementationAddress {
    using LibString for *;
    using FacetBuddyLib for address;
    
    struct FacetERC20Storage {
        string name;
        string symbol;
        uint8 decimals;
        mapping(address => bool) balanceInitialized;
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
    
    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
        initBalanceIfNeeded(from);
        initBalanceIfNeeded(to);
    }
    
    function isInMigration() internal view returns(bool) {
        address dummy = 0x11110000000000000000000000000000000000C5;
        return dummy.code.length > 0;
    }
    
    function initBalanceIfNeeded(address account) public {
        FacetERC20Storage storage fs = _FacetERC20Storage();
        uint256 balance = balanceOf(account);
        
        if (account == address(0)) return;
        if (isInMigration()) return;
        
        if (!fs.balanceInitialized[account]) {
            if (balance > 0) {
                emit Transfer(address(0), account, balance);
            }
            
            fs.balanceInitialized[account] = true;
        }
    }
}
