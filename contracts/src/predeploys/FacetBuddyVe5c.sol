// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/tokens/ERC20.sol";
import "solady/src/utils/Initializable.sol";
import "src/libraries/PublicImplementationAddress.sol";
import "src/libraries/MigrationLib.sol";

contract FacetBuddyVe5c is Initializable, PublicImplementationAddress {
    event CallOnBehalfOfUser(
        address indexed onBehalfOf,
        address indexed addressToCall,
        bytes userCalldata,
        uint256 initialAmount,
        uint256 finalAmount,
        bool resultSuccess,
        string resultData
    );
    
    struct FacetBuddyStorage {
      address factory;
      address erc20Bridge;
      address forUser;
      bool locked;
    }
    
    function s() internal pure returns (FacetBuddyStorage storage ns) {
        bytes32 position = keccak256("FacetBuddyStorage.contract.storage.v1");
        assembly {
            ns.slot := position
        }
    }
    
    function initialize(address erc20Bridge, address forUser) public initializer {
        s().factory = msg.sender;
        s().erc20Bridge = erc20Bridge;
        s().forUser = forUser;
    }
    
    function _makeCall(address addressToCall, bytes calldata userCalldata, bool revertOnFailure) internal {
        require(addressToCall != address(this), "Cannot call self");
        require(!s().locked, "No reentrancy allowed");
        s().locked = true;

        uint256 initialBalance = _balance();
        
        if (initialBalance > 0) {
            _approve(addressToCall, initialBalance);
        }

        (bool success, bytes memory data) = addressToCall.call(userCalldata);
        require(success || !revertOnFailure, "_makeCall failed");

        _approve(addressToCall, 0);
        uint256 finalBalance = _balance();

        if (finalBalance > 0) {
            _transfer(s().forUser, finalBalance);
        }

        s().locked = false;

        emit CallOnBehalfOfUser(s().forUser, addressToCall, userCalldata, initialBalance, finalBalance, success, string(data));
    }

    function callForUser(uint256 amountToSpend, address addressToCall, bytes calldata userCalldata) public {
        require(msg.sender == s().forUser || msg.sender == s().factory, "Only the user or factory can callForUser");
        
        if (amountToSpend > 0) {
            ERC20(s().erc20Bridge).transferFrom(s().forUser, address(this), amountToSpend);
        }
        
        _makeCall(addressToCall, userCalldata, true);
    }

    function callFromBridge(address addressToCall, bytes calldata userCalldata) public {
        require(MigrationLib.isInMigration(), "Only during migration");
        require(msg.sender == s().erc20Bridge, "Only the bridge can callFromBridge");
        _makeCall(addressToCall, userCalldata, false);
    }

    function _balance() internal view returns (uint256) {
        return ERC20(s().erc20Bridge).balanceOf(address(this));
    }

    function _approve(address spender, uint256 amount) internal returns (bool) {
        return ERC20(s().erc20Bridge).approve(spender, amount);
    }

    function _transfer(address to, uint256 amount) internal returns (bool) {
        return ERC20(s().erc20Bridge).transfer(to, amount);
    }
}
