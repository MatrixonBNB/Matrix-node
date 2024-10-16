// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/tokens/ERC20.sol";
import "./FacetBuddyLib.sol";
import "src/libraries/PublicImplementationAddress.sol";
import "solady/src/utils/LibString.sol";
import "solady/src/utils/EnumerableSetLib.sol";
import "./MigrationLib.sol";

abstract contract FacetERC20 is ERC20, PublicImplementationAddress {
    using LibString for *;
    using FacetBuddyLib for address;
    using EnumerableSetLib for *;
    
    struct FacetERC20Storage {
        string name;
        string symbol;
        uint8 decimals;
        EnumerableSetLib.AddressSet balanceHoldersToInit;
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
    
    function _beforeTokenTransfer(address, address to, uint256) internal virtual override {
        if (MigrationLib.isInMigration()) {
            _FacetERC20Storage().balanceHoldersToInit.add(to);
        } else {
            require(allBalancesInitialized(), "Balances not initialized");
        }
    }
    
    function allBalancesInitialized() public view returns (bool) {
        return _FacetERC20Storage().balanceHoldersToInit.length() == 0;
    }
    
    function initAllBalances() public {
        require(MigrationLib.isNotInMigration(), "Migration in progress");
        
        FacetERC20Storage storage fs = _FacetERC20Storage();
        
        for (uint256 i = 0; i < fs.balanceHoldersToInit.length(); i++) {
            address holder = fs.balanceHoldersToInit.at(i);
            uint256 balance = balanceOf(holder);
            
            if (balance > 0) {
                emit Transfer(address(0), holder, balance);
            }
            
            fs.balanceHoldersToInit.remove(holder);
        }
    }
}
