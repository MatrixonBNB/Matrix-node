// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./Upgradeable.sol";
import "./NFTCollectionVa11.sol";
import "./FacetERC721.sol";
import "./FacetERC20.sol";
import "solady/src/utils/Base64.sol";
import "solady/src/utils/LibString.sol";
import "solady/src/utils/Initializable.sol";

contract TokenUpgradeRendererV859 is Upgradeable, Initializable {
    using LibString for *;
    
    event CollectionInitialized(address indexed collection, ContractInfo contractInfo, TokenUpgradeLevel initialLevel);
    event UpgradeLevelUpdated(address indexed collection, uint256 index, string name, string imageURI, string animationURI, uint256 startTime, uint256 endTime, bool newRecord);
    event TokenUpgraded(address indexed collection, uint256 tokenId, uint256 upgradeLevel);
    event ContractInfoUpdated(address indexed collection, ContractInfo newInfo);

    struct TokenUpgradeLevel {
        string name;
        string imageURI;
        string animationURI;
        string extraAttributesJson;
        uint256 startTime;
        uint256 endTime;
    }

    struct TokenStatus {
        uint256 upgradeLevel;
        uint256 lastUpgradeTime;
    }

    struct ContractInfo {
        string name;
        string description;
        string imageURI;
    }

    struct TokenUpgradeRendererStorage {
        mapping(address => TokenUpgradeLevel[]) tokenUpgradeLevelsByCollection;
        mapping(address => mapping(uint256 => TokenStatus)) tokenStatusByCollection;
        mapping(address => ContractInfo) contractInfoByCollection;
        uint256 perUpgradeFee;
        address feeTo;
        address WETH;
        uint256 maxUpgradeLevelCount;
    }

    function s() internal pure returns (TokenUpgradeRendererStorage storage tus) {
        bytes32 position = keccak256("TokenUpgradeRendererStorage.contract.storage.v1");
        assembly {
            tus.slot := position
        }
    }

    function initialize(uint256 perUpgradeFee, address feeTo, address weth) public initializer {
        s().maxUpgradeLevelCount = 30;
        s().perUpgradeFee = perUpgradeFee;
        s().feeTo = feeTo;
        s().WETH = weth;
        _initializeUpgradeAdmin(msg.sender);
    }

    function addUpgradeLevel(address collection, TokenUpgradeLevel memory newLevel) public {
        requireSenderAdmin(collection);
        TokenUpgradeLevel memory lastLevel = s().tokenUpgradeLevelsByCollection[collection][s().tokenUpgradeLevelsByCollection[collection].length - 1];
        require(newLevel.endTime > newLevel.startTime, "End time must be after start time");
        require(newLevel.startTime > lastLevel.endTime, "Start time must be after last level end time");
        require(s().tokenUpgradeLevelsByCollection[collection].length + 1 <= s().maxUpgradeLevelCount, "Max upgrade level count reached");
        s().tokenUpgradeLevelsByCollection[collection].push(newLevel);
        emit UpgradeLevelUpdated(collection, s().tokenUpgradeLevelsByCollection[collection].length - 1, newLevel.name, newLevel.imageURI, newLevel.animationURI, newLevel.startTime, newLevel.endTime, true);
    }

    function editUpgradeLevel(address collection, uint256 index, TokenUpgradeLevel memory newLevel) public {
        requireSenderAdmin(collection);
        
        if(s().tokenUpgradeLevelsByCollection[collection].length == 0) {
            s().tokenUpgradeLevelsByCollection[collection].push(TokenUpgradeLevel("", "", "", "", 0, 0));
        }
        
        bool editingFirstLevel = index == 0;
        bool editingLastLevel = index == s().tokenUpgradeLevelsByCollection[collection].length - 1;
        if (!editingLastLevel) {
            TokenUpgradeLevel memory nextLevel = s().tokenUpgradeLevelsByCollection[collection][index + 1];
            require(newLevel.endTime < nextLevel.startTime, "End time must be before next level start time");
        }
        if (editingFirstLevel) {
            newLevel.startTime = 0;
            newLevel.endTime = 0;
        } else {
            TokenUpgradeLevel memory precedingLevel = s().tokenUpgradeLevelsByCollection[collection][index - 1];
            require(newLevel.startTime > precedingLevel.endTime, "Start time must be after preceding level end time");
            require(newLevel.endTime > newLevel.startTime, "End time must be after start time");
        }
        s().tokenUpgradeLevelsByCollection[collection][index] = newLevel;
        emit UpgradeLevelUpdated(collection, index, newLevel.name, newLevel.imageURI, newLevel.animationURI, newLevel.startTime, newLevel.endTime, false);
    }

    function activeUpgradeLevelIndex(address collection) public view returns (uint256) {
        for (uint256 i = 0; i < s().tokenUpgradeLevelsByCollection[collection].length; i++) {
            TokenUpgradeLevel memory level = s().tokenUpgradeLevelsByCollection[collection][i];
            if (level.startTime <= block.timestamp && level.endTime > block.timestamp) {
                return i;
            } else if (level.startTime > block.timestamp) {
                return 0;
            }
        }
        return 0;
    }

    function activeUpgradeLevel(address collection) public view returns (TokenUpgradeLevel memory) {
        uint256 index = activeUpgradeLevelIndex(collection);
        return index == 0 ? TokenUpgradeLevel("", "", "", "", 0, 0) : s().tokenUpgradeLevelsByCollection[collection][index];
    }

    function _upgradeToken(address collection, uint256 tokenId, TokenUpgradeLevel memory activeUpgrade) internal {
        require(FacetERC721(collection).isApprovedOrOwner(msg.sender, tokenId), string(abi.encodePacked("TokenUpgradeRenderer: msg.sender not authorized to upgrade id ", tokenId.toString())));
        TokenStatus storage tokenStatus = s().tokenStatusByCollection[collection][tokenId];
        require(tokenStatus.lastUpgradeTime < activeUpgrade.startTime, "TokenUpgradeRenderer: Token already upgraded during this period");
        uint256 targetLevelIndex = tokenStatus.upgradeLevel + 1;
        require(targetLevelIndex < s().tokenUpgradeLevelsByCollection[collection].length, "TokenUpgradeRenderer: No more upgrade levels");
        tokenStatus.upgradeLevel = targetLevelIndex;
        tokenStatus.lastUpgradeTime = block.timestamp;
        emit TokenUpgraded(collection, tokenId, tokenStatus.upgradeLevel);
    }

    function upgradeMultipleTokens(address collection, uint256[] memory tokenIds) public {
        require(tokenIds.length <= 100, "TokenUpgradeRenderer: Cannot upgrade more than 50 tokens at once");
        uint256 totalFee = s().perUpgradeFee * tokenIds.length;
        if (totalFee > 0 && s().feeTo != address(0)) {
            ERC20(s().WETH).transferFrom(msg.sender, s().feeTo, totalFee);
        }
        uint256 activeUpgradeIndex = activeUpgradeLevelIndex(collection);
        require(activeUpgradeIndex > 0, "TokenUpgradeRenderer: No active upgrade level");
        TokenUpgradeLevel memory activeUpgrade = s().tokenUpgradeLevelsByCollection[collection][activeUpgradeIndex];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _upgradeToken(collection, tokenIds[i], activeUpgrade);
        }
    }

    function setContractInfo(address collection, ContractInfo memory info) public {
        requireSenderAdmin(collection);
        s().contractInfoByCollection[collection] = info;
        emit ContractInfoUpdated(collection, info);
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address collection = msg.sender;
        TokenStatus memory status = s().tokenStatusByCollection[collection][tokenId];
        TokenUpgradeLevel memory upgradeLevel = s().tokenUpgradeLevelsByCollection[collection][status.upgradeLevel];
        string memory name_json = string(abi.encodePacked('"name": "', upgradeLevel.name.escapeJSON(), ' #', tokenId.toString(), '"'));
        string memory description_json = string(abi.encodePacked('"description": "', s().contractInfoByCollection[collection].description.escapeJSON(), '"'));
        string memory image_field = bytes(upgradeLevel.imageURI).length == 0 ? "" : string(abi.encodePacked('"image": "', upgradeLevel.imageURI.escapeJSON(), '",'));
        string memory animation_url_field = bytes(upgradeLevel.animationURI).length == 0 ? "" : string(abi.encodePacked('"animation_url": "', upgradeLevel.animationURI.escapeJSON(), '",'));
        string memory basic_attributes_json = string(abi.encodePacked('{"trait_type": "Number", "display_type": "number", "value": ', tokenId.toString(), '}, {"trait_type": "Level", "value": "', upgradeLevel.name.escapeJSON(), '"}'));
        string memory extra_attributes_json = bytes(upgradeLevel.extraAttributesJson).length != 0 ? string(abi.encodePacked(", ", upgradeLevel.extraAttributesJson)) : "";
        string memory json_data = string(abi.encodePacked('{', name_json, ',', description_json, ',', image_field, animation_url_field, '"attributes": [', basic_attributes_json, extra_attributes_json, ']}'));
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json_data))));
    }

    function initializeWithData(ContractInfo memory contractInfo, TokenUpgradeLevel memory initialLevel) external {
        setContractInfo(msg.sender, contractInfo);
        editUpgradeLevel(msg.sender, 0, initialLevel);
        emit CollectionInitialized(msg.sender, contractInfo, initialLevel);
    }

    function contractURI() external view returns (string memory) {
        address collection = msg.sender;
        ContractInfo memory contractInfo = s().contractInfoByCollection[collection];
        string memory json_data = string(abi.encodePacked('{"name": "', contractInfo.name.escapeJSON(), '", "description": "', contractInfo.description.escapeJSON(), '", "image": "', contractInfo.imageURI.escapeJSON(), '"}'));
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json_data))));
    }

    function upgradeLevelCount(address collection) public view returns (uint256) {
        return s().tokenUpgradeLevelsByCollection[collection].length;
    }

    function requireSenderAdmin(address target) internal view {
        require(target == msg.sender || INFTCollection01(target).owner() == msg.sender, "Admin access only");
    }

    function setFeeTo(address _feeTo) public {
        require(msg.sender == s().feeTo, "Only feeTo can change feeTo");
        s().feeTo = _feeTo;
    }
}
