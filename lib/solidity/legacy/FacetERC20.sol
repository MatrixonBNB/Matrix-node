// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "solady/src/tokens/ERC20.sol";
import "./FacetBuddyLib.sol";
import "solady/src/utils/LibString.sol";

abstract contract FacetERC20 is ERC20 {
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
    
    function transfer(address to, uint amount) public override returns (bool) {
        uint256 currentBalance = balanceOf(msg.sender);
        require(currentBalance >= amount, 
        string.concat("ERC20: transfer amount exceeds balance. Balance: ", currentBalance.toString(), " Amount: ", amount.toString())
        );
        return super.transfer(to, amount);
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
    
    function _burn(address from, uint amount) internal override {
        uint256 currentBalance = balanceOf(from);
        require(currentBalance >= amount,
        string.concat("ERC20: burn amount exceeds balance. Balance: ", currentBalance.toString(), " Amount: ", amount.toString())
        );
        return super._burn(from, amount);
    }
}
