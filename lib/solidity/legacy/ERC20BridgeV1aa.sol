// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./FacetERC20.sol";
import "./Upgradeable.sol";
import "solady/src/utils/Initializable.sol";

contract ERC20BridgeV1aa is FacetERC20, Upgradeable, Initializable {
    event BridgedIn(address indexed to, uint256 amount);
    event InitiateWithdrawal(address indexed from, uint256 amount, bytes32 withdrawalId);
    event WithdrawalComplete(address indexed to, uint256 amount, bytes32 withdrawalId);

    struct ERC20BridgeStorage {
        address factory;
        address tokenSmartContract;
        address trustedSmartContract;
        mapping(bytes32 => uint256) withdrawalIdAmount;
        mapping(address => bytes32) userWithdrawalId;
        uint256 withdrawalIdNonce;
    }

    function s() internal pure returns (ERC20BridgeStorage storage bs) {
        bytes32 position = keccak256("ERC20BridgeStorage.contract.storage.v1");
        assembly {
            bs.slot := position
        }
    }

    function initialize(address tokenSmartContract, address trustedSmartContract, string memory name, string memory symbol, uint8 decimals) public initializer {
        _initializeERC20(name, symbol, decimals);
        _initializeUpgradeAdmin(msg.sender);
        s().tokenSmartContract = tokenSmartContract;
        s().trustedSmartContract = trustedSmartContract;
        s().factory = msg.sender;
    }

    modifier onlyFactory() {
        require(msg.sender == s().factory, "Only the factory can call this function");
        _;
    }

    function bridgeIn(address to, uint256 amount) public onlyFactory {
        _mint(to, amount);
        emit BridgedIn(to, amount);
    }

    function generateWithdrawalId() internal returns (bytes32) {
        return keccak256(abi.encode(address(this), msg.sender, s().withdrawalIdNonce++));
    }

    function bridgeOut(address from, uint256 amount) public onlyFactory {
        bytes32 withdrawalId = generateWithdrawalId();
        require(s().userWithdrawalId[from] == bytes32(0), "Withdrawal pending");
        require(s().withdrawalIdAmount[withdrawalId] == 0, "Already bridged out");
        require(amount > 0, "Invalid amount");

        s().userWithdrawalId[from] = withdrawalId;
        s().withdrawalIdAmount[withdrawalId] = amount;
        _burn(from, amount);

        emit InitiateWithdrawal(from, amount, withdrawalId);
    }

    function markWithdrawalComplete(address to, bytes32 withdrawalId) public onlyFactory {
        require(s().userWithdrawalId[to] == withdrawalId, "Withdrawal id not found");

        uint256 amount = s().withdrawalIdAmount[withdrawalId];
        s().withdrawalIdAmount[withdrawalId] = 0;
        s().userWithdrawalId[to] = bytes32(0);

        emit WithdrawalComplete(to, amount, withdrawalId);
    }
    
    function withdrawalIdAmount(bytes32 withdrawalId) public view returns (uint256) {
        return s().withdrawalIdAmount[withdrawalId];
    }
}
