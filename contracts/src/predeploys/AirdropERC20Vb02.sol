// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetERC20.sol";
import "src/libraries/FacetOwnable.sol";
import "solady/utils/Initializable.sol";

contract AirdropERC20Vb02 is FacetERC20, FacetOwnable, Initializable {
    struct AirdropERC20Storage {
        uint256 maxSupply;
        uint256 perMintLimit;
        uint256 singleTxAirdropLimit;
    }
    
    function s() internal pure returns (AirdropERC20Storage storage cs) {
        bytes32 position = keccak256("AirdropERC20Storage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
  
    function initialize(
      string memory name,
      string memory symbol,
      address owner,
      uint8 decimals,
      uint256 maxSupply,
      uint256 perMintLimit
    ) public initializer {
        _initializeERC20(name, symbol, decimals);
        s().maxSupply = maxSupply;
        s().perMintLimit = perMintLimit;
        s().singleTxAirdropLimit = 10;
        _initializeOwner(owner);
    }

    function airdrop(address to, uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be positive");
        require(amount <= s().perMintLimit, "Exceeded mint limit");
        require(totalSupply() + amount <= s().maxSupply, "Exceeded max supply");
        _mint(to, amount);
    }

    function airdropMultiple(address[] memory addresses, uint256[] memory amounts) public onlyOwner {
        require(addresses.length == amounts.length, "Address and amount arrays must be the same length");
        require(addresses.length <= s().singleTxAirdropLimit, "Cannot airdrop more than 10 addresses at a time");
        for (uint256 i = 0; i < addresses.length; i++) {
            airdrop(addresses[i], amounts[i]);
        }
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}
