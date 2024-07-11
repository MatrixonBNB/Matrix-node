// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./Upgradeable.sol";
import "./FacetOwnable.sol";
import "solady/src/utils/Initializable.sol";
import "./FacetERC20.sol";
import "solady/src/utils/Base64.sol";

contract BridgeAndCallHelperVc14 is Upgradeable, FacetOwnable, Initializable {
    struct BridgeAndCallHelperStorage {
        address bridge;
        uint256 fee;
        bool locked;
    }

    function s() internal pure returns (BridgeAndCallHelperStorage storage bs) {
        bytes32 position = keccak256("BridgeAndCallHelperV1.contract.storage.v1");
        assembly {
            bs.slot := position
        }
    }

    event CallFromBridge(
        address indexed bridgingUser,
        address indexed addressToCall,
        bytes outsideCalldata,
        uint256 initialAmount,
        uint256 finalAmount,
        uint256 feeAmount,
        bool resultStatus,
        bytes resultData
    );

    event BridgeUpdated(address newBridge);
    event FeeUpdated(uint256 newFee);

    function initialize(address bridge, uint256 fee, address owner) public initializer {
        _initializeOwner(owner);
        _initializeUpgradeAdmin(owner);
        s().bridge = bridge;
        s().fee = fee;
    }

    function setBridge(address newBridge) public onlyOwner {
        s().bridge = newBridge;
        emit BridgeUpdated(newBridge);
    }

    function setFee(uint256 newFee) public onlyOwner {
        s().fee = newFee;
        emit FeeUpdated(newFee);
    }

    function callFromBridge(address bridgingUser, address addressToCall, string memory base64Calldata) public {
        require(msg.sender == s().bridge, "Only the bridge can callFromBridge");
        require(addressToCall != address(this), "Cannot call self");
        require(!s().locked, "No reentrancy allowed");

        s().locked = true;
        bytes memory outsideCalldata = Base64.decode(base64Calldata);
        uint256 initialBalance = _balance();
        uint256 calculatedFee = initialBalance < s().fee ? initialBalance : s().fee;

        if (calculatedFee > 0) {
            _transfer(owner(), calculatedFee);
        }

        _approve(addressToCall, initialBalance - calculatedFee);
        (bool success, bytes memory data) = addressToCall.call(outsideCalldata);
        _approve(addressToCall, 0);

        uint256 finalBalance = _balance();

        if (finalBalance > 0) {
            _transfer(bridgingUser, finalBalance);
        }

        s().locked = false;
        emit CallFromBridge(bridgingUser, addressToCall, outsideCalldata, initialBalance, finalBalance, calculatedFee, success, data);
    }

    function _balance() internal view returns (uint256) {
        return ERC20(s().bridge).balanceOf(address(this));
    }

    function _approve(address spender, uint256 amount) internal returns (bool) {
        return ERC20(s().bridge).approve(spender, amount);
    }

    function _transfer(address to, uint256 amount) internal returns (bool) {
        return ERC20(s().bridge).transfer(to, amount);
    }
}
