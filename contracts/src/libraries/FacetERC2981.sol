// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/tokens/ERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

abstract contract FacetERC2981 is ERC2981 {
    event DefaultRoyaltyUpdated(address indexed receiver, uint96 feeNumerator);
    event TokenRoyaltyUpdated(uint256 indexed tokenId, address indexed receiver, uint96 feeNumerator);

    function _setDefaultRoyalty(address receiver, uint96 feeNumerator) internal virtual override {
        super._setDefaultRoyalty(receiver, feeNumerator);
        emit DefaultRoyaltyUpdated(receiver, feeNumerator);
    }

    function _deleteDefaultRoyalty() internal virtual override {
        super._deleteDefaultRoyalty();
        emit DefaultRoyaltyUpdated(address(0), 0);
    }

    function _setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) internal virtual override {
        super._setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit TokenRoyaltyUpdated(tokenId, receiver, feeNumerator);
    }

    function _deleteTokenRoyalty(uint256 tokenId) internal virtual {
        _resetTokenRoyalty(tokenId);
        emit TokenRoyaltyUpdated(tokenId, address(0), 0);
    }
}
