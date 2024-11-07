// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/Upgradeable.sol";
import "solady/utils/Initializable.sol";
import "src/libraries/FacetERC20.sol";
import "solady/utils/Base64.sol";
import "solady/utils/LibString.sol";

interface INFTCollection01 {
  function owner() external view returns (address);
}

contract EditionMetadataRendererV3f8 is Upgradeable, Initializable {
    using LibString for *;
  
    struct TokenEditionInfo {
        string name;
        string description;
        string imageURI;
        string animationURI;
    }

    struct EditionMetadataRendererStorage {
        mapping(address => TokenEditionInfo) tokenInfos;
    }

    function s() internal pure returns (EditionMetadataRendererStorage storage es) {
        bytes32 position = keccak256("EditionMetadataRendererV101.contract.storage.v1");
        assembly {
            es.slot := position
        }
    }

    event MediaURIsUpdated(address indexed target, address indexed sender, string imageURI, string animationURI);
    event EditionInitialized(address indexed target, string description, string imageURI, string animationURI, string name);
    event DescriptionUpdated(address indexed target, address indexed sender, string newDescription);

    function initialize() public initializer {
        _initializeUpgradeAdmin(msg.sender);
    }

    function requireSenderAdmin(address target) internal view {
        require(target == msg.sender || INFTCollection01(target).owner() == msg.sender, "Admin access only");
    }

    function updateMediaURIs(address target, string memory imageURI, string memory animationURI) external {
        requireSenderAdmin(target);
        s().tokenInfos[target].imageURI = imageURI;
        s().tokenInfos[target].animationURI = animationURI;
        emit MediaURIsUpdated(target, msg.sender, imageURI, animationURI);
    }

    function updateDescription(address target, string memory newDescription) external {
        requireSenderAdmin(target);
        s().tokenInfos[target].description = newDescription;
        emit DescriptionUpdated(target, msg.sender, newDescription);
    }

    function initializeWithData(TokenEditionInfo memory info) external {
        s().tokenInfos[msg.sender] = info;
        emit EditionInitialized(msg.sender, info.description, info.imageURI, info.animationURI, info.name);
    }

    function contractURI() external view returns (string memory) {
        address target = msg.sender;
        TokenEditionInfo storage editionInfo = s().tokenInfos[target];
        return encodeContractURIJSON(editionInfo.name, editionInfo.description, editionInfo.imageURI, editionInfo.animationURI);
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address target = msg.sender;
        TokenEditionInfo storage info = s().tokenInfos[target];
        return createMetadataEdition(info.name, info.description, info.imageURI, info.animationURI, tokenId);
    }

    function createMetadataEdition(string memory name, string memory description, string memory imageURI, string memory animationURI, uint256 tokenOfEdition) internal pure returns (string memory) {
        string memory _tokenMediaData = tokenMediaData(imageURI, animationURI);
        string memory json = createMetadataJSON(name, description, _tokenMediaData, tokenOfEdition);
        return encodeMetadataJSON(json);
    }

    function encodeContractURIJSON(string memory name, string memory description, string memory imageURI, string memory animationURI) internal pure returns (string memory) {
        string memory imageSpace = bytes(imageURI).length > 0 ? string(abi.encodePacked('", "image": "', imageURI)) : "";
        string memory animationSpace = bytes(animationURI).length > 0 ? string(abi.encodePacked('", "animation_url": "', animationURI)) : "";
        return encodeMetadataJSON(string(abi.encodePacked('{"name": "', name, '", "description": "', description, imageSpace, animationSpace, '"}')));
    }

    function createMetadataJSON(string memory name, string memory description, string memory mediaData, uint256 tokenOfEdition) internal pure returns (string memory) {
        return string(abi.encodePacked('{"name": "', name, ' ', tokenOfEdition.toString(), '", "description": "', description, '", "', mediaData, 'properties": {"number": ', tokenOfEdition.toString(), ', "name": "', name, '"}}'));
    }

    function encodeMetadataJSON(string memory json) internal pure returns (string memory) {
        return string(abi.encodePacked('data:application/json;base64,', Base64.encode(bytes(json))));
    }

    function tokenMediaData(string memory imageUrl, string memory animationUrl) internal pure returns (string memory) {
        bool hasImage = bytes(imageUrl).length > 0;
        bool hasAnimation = bytes(animationUrl).length > 0;

        if (hasImage && hasAnimation) {
            return string(abi.encodePacked('image": "', imageUrl, '", "animation_url": "', animationUrl, '", "'));
        } else if (hasImage) {
            return string(abi.encodePacked('image": "', imageUrl, '", "'));
        } else if (hasAnimation) {
            return string(abi.encodePacked('animation_url": "', animationUrl, '", "'));
        }
        return "";
    }
}
