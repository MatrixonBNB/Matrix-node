// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./FacetERC20.sol";
import "./PublicImplementationAddress.sol";
import "solady/src/utils/LibString.sol";
import "solady/src/utils/Initializable.sol";

contract ERC20BatchTransferV4c9 is Initializable, PublicImplementationAddress {
    using LibString for uint256;

    event BatchTransfer(address indexed tokenAddress, address[] recipients, uint256[] amounts);
    event WithdrawStuckTokens(address indexed tokenAddress, address to, uint256 amount);

    struct ERC20BatchTransferStorage {
      uint256 singleTxAirdropLimit;
    }
    
    function s() internal pure returns (ERC20BatchTransferStorage storage ns) {
        bytes32 position = keccak256("ERC20BatchTransferStorage.contract.storage.v1");
        assembly {
            ns.slot := position
        }
    }

    function initialize() public initializer {
        s().singleTxAirdropLimit = 50;
    }

    function batchTransfer(address tokenAddress, address[] calldata recipients, uint256[] calldata amounts) external {
        require(recipients.length > 0, "Must import at least one address");
        require(recipients.length == amounts.length, "Address and amount arrays must be the same length");
        require(recipients.length <= s().singleTxAirdropLimit, string(abi.encodePacked("Cannot import more than ", s().singleTxAirdropLimit.toString(), " addresses at a time")));

        for (uint256 i = 0; i < recipients.length; i++) {
            address to = recipients[i];
            uint256 amount = amounts[i];
            ERC20(tokenAddress).transferFrom(msg.sender, to, amount);
        }

        emit BatchTransfer(tokenAddress, recipients, amounts);
    }

    function withdrawStuckTokens(address tokenAddress, address to, uint256 amount) external {
        ERC20(tokenAddress).transfer(to, amount);
        emit WithdrawStuckTokens(tokenAddress, to, amount);
    }
}
