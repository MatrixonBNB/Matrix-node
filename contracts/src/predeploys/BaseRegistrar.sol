// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ENS} from "ens-contracts/registry/ENS.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibString} from "solady/utils/LibString.sol";

import {GRACE_PERIOD} from "../libraries/EnsConstants.sol";

import "../libraries/MigrationLib.sol";
import "src/libraries/FacetERC721.sol";
import "src/libraries/Upgradeable.sol";
import "solady/utils/Initializable.sol";
import {EventReplayable} from "src/libraries/EventReplayable.sol";

contract BaseRegistrar is FacetERC721, Ownable, Initializable, EventReplayable, Upgradeable {
    using LibString for uint256;

    struct BaseRegistrarStorage {
        mapping(uint256 => uint256) nameExpires;
        ENS registry;
        bytes32 baseNode;
        string _baseURI;
        string _collectionURI;
        mapping(address => bool) controllers;
        mapping(uint256 => uint256) v1TokenIdToV2TokenId;
        mapping(uint256 => uint256) v2TokenIdToV1TokenId;
        uint256 nextV1TokenId;
    }
    
    function nameExpires(uint256 tokenId) public view returns (uint256) {
        return s().nameExpires[tokenId];
    }
    
    function controllers(address user) public view returns (bool) {
        return s().controllers[user];
    }
    
    function registry() public view returns (ENS) {
        return s().registry;
    }
    
    function baseNode() public view returns (bytes32) {
        return s().baseNode;
    }
    
    function _baseURI() public view returns (string memory) {
        return s()._baseURI;
    }
    
    function _collectionURI() public view returns (string memory) {
        return s()._collectionURI;
    }
    
    function v1TokenIdToV2TokenId(uint256 tokenId) public view returns (uint256) {
        return s().v1TokenIdToV2TokenId[tokenId];
    }
    
    function v2TokenIdToV1TokenId(uint256 tokenId) public view returns (uint256) {
        return s().v2TokenIdToV1TokenId[tokenId];
    }
    
    function nextV1TokenId() public view returns (uint256) {
        return s().nextV1TokenId;
    }
    
    function s() internal pure returns (BaseRegistrarStorage storage bs) {
        bytes32 position = keccak256("BaseRegistrar.storage.v1");
        assembly {
            bs.slot := position
        }
    }

    bytes4 private constant RECLAIM_ID = bytes4(keccak256("reclaim(uint256,address)"));

    error Expired(uint256 tokenId);
    error NotApprovedOwner(uint256 tokenId, address sender);
    error NotAvailable(uint256 tokenId);
    error NonexistentToken(uint256 tokenId);
    error NotRegisteredOrInGrace(uint256 tokenId);
    error OnlyController();
    error RegistrarNotLive();

    event ControllerAdded(address indexed controller);
    event ControllerRemoved(address indexed controller);
    event NameRegistered(uint256 indexed id, address indexed owner, uint256 expires);
    event NameRenewed(uint256 indexed id, uint256 expires);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event ContractURIUpdated();

    modifier live() {
        if (s().registry.owner(s().baseNode) != address(this)) revert RegistrarNotLive();
        _;
    }

    modifier onlyController() {
        if (!s().controllers[msg.sender]) revert OnlyController();
        _;
    }

    modifier onlyAvailable(uint256 id) {
        if (!isAvailable(id)) revert NotAvailable(id);
        _;
    }

    modifier onlyNonExpired(uint256 id) {
        if (MigrationLib.isInMigration()) {
            uint256 v2Id = s().v1TokenIdToV2TokenId[id];
            if (s().nameExpires[v2Id] <= block.timestamp && s().nameExpires[id] <= block.timestamp) {
                revert Expired(id);
            }
        } else {
            if (s().nameExpires[id] <= block.timestamp) {
                revert Expired(id);
            }
        }
        _;
    }

    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        ENS registry_,
        address owner_,
        bytes32 baseNode_,
        string memory baseURI_,
        string memory collectionURI_
    ) public initializer {
        _initializeOwner(owner_);
        _initializeUpgradeAdmin(owner_);
        s().registry = registry_;
        s().baseNode = baseNode_;
        s()._baseURI = baseURI_;
        s()._collectionURI = collectionURI_;
        _initializeERC721(tokenName, tokenSymbol);
    }
    
    constructor() {
        _disableInitializers();
    }

    function addController(address controller) external onlyOwner {
        s().controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    function removeController(address controller) external onlyOwner {
        s().controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    function setResolver(address resolver) external onlyOwner {
        s().registry.setResolver(s().baseNode, resolver);
    }

    function register(uint256 id, address owner, uint256 duration) external returns (uint256) {
        return _register(id, owner, duration, true);
    }

    function registerOnly(uint256 id, address owner, uint256 duration) external returns (uint256) {
        return _register(id, owner, duration, false);
    }

    function registerWithRecord(uint256 id, address owner, uint256 duration, address resolver, uint64 ttl)
        external
        live
        onlyController
        onlyAvailable(id)
        returns (uint256)
    {
        uint256 expiry = _localRegister(id, owner, duration);
        s().registry.setSubnodeRecord(s().baseNode, bytes32(id), owner, resolver, ttl);
        
        recordAndEmitEvent(
            "NameRegistered(uint256,address,uint256)",
            abi.encode(id, owner),
            abi.encode(expiry)
        );
        
        return expiry;
    }

    function ownerOf(uint256 tokenId) public view override onlyNonExpired(tokenId) returns (address) {
        return super.ownerOf(tokenId);
    }
    
    function _ownerOf(uint256 tokenId) internal view virtual override returns (address) {
        address directOwner = super._ownerOf(tokenId);
        if (directOwner != address(0)) return directOwner;
        
        if (MigrationLib.isInMigration()) {
            uint256 v2TokenId = s().v1TokenIdToV2TokenId[tokenId];
            return super._ownerOf(v2TokenId);
        }
        
        return address(0);
    }

    function isAvailable(uint256 id) public view returns (bool) {
        return s().nameExpires[id] + GRACE_PERIOD < block.timestamp;
    }

    function renew(uint256 id, uint256 duration) external live onlyController returns (uint256) {
        uint256 expires = s().nameExpires[id];
        if (expires + GRACE_PERIOD < block.timestamp) revert NotRegisteredOrInGrace(id);

        expires += duration;
        s().nameExpires[id] = expires;
        emit NameRenewed(id, expires);
        return expires;
    }

    function reclaim(uint256 id, address owner) external live {
        if (!_isApprovedOrOwner(msg.sender, id)) revert NotApprovedOwner(id, owner);
        s().registry.setSubnodeOwner(s().baseNode, bytes32(id), owner);
    }

    function supportsInterface(bytes4 interfaceID) public pure override(ERC721) returns (bool) {
        return interfaceID == type(IERC165).interfaceId || interfaceID == type(IERC721).interfaceId
            || interfaceID == RECLAIM_ID;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentToken(tokenId);
        return bytes(s()._baseURI).length > 0 ? string.concat(s()._baseURI, tokenId.toString()) : "";
    }

    function contractURI() public view returns (string memory) {
        return s()._collectionURI;
    }

    function setBaseTokenURI(string memory baseURI_) public onlyOwner {
        s()._baseURI = baseURI_;
        uint256 minTokenId = 1;
        uint256 maxTokenId = type(uint256).max;
        emit BatchMetadataUpdate(minTokenId, maxTokenId);
    }

    function setContractURI(string memory collectionURI_) public onlyOwner {
        s()._collectionURI = collectionURI_;
        emit ContractURIUpdated();
    }

    function _register(uint256 id, address owner, uint256 duration, bool updateRegistry)
        internal
        live
        onlyController
        onlyAvailable(id)
        returns (uint256)
    {
        uint256 expiry = _localRegister(id, owner, duration);
        if (updateRegistry) {
            s().registry.setSubnodeOwner(s().baseNode, bytes32(id), owner);
        }
            
        recordAndEmitEvent(
            "NameRegistered(uint256,address,uint256)",
            abi.encode(id, owner),
            abi.encode(expiry)
        );
        return expiry;
    }

    function _localRegister(uint256 id, address owner, uint256 duration) internal returns (uint256 expiry) {
        s().nextV1TokenId++;
        s().v1TokenIdToV2TokenId[s().nextV1TokenId] = id;
        s().v2TokenIdToV1TokenId[id] = s().nextV1TokenId;
        
        expiry = block.timestamp + duration;
        s().nameExpires[id] = expiry;
        if (_exists(id)) {
            _burn(id);
        }
        _mint(owner, id);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        override
        onlyNonExpired(tokenId)
        returns (bool)
    {
        return super._isApprovedOrOwner(spender, tokenId);
    }

    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        super._afterTokenTransfer(from, to, tokenId);
        
        if (MigrationLib.isInMigration() && from != address(0) && to != address(0)) {
            bytes32 labelHash = bytes32(tokenId);
            bytes32 node = keccak256(abi.encodePacked(s().baseNode, labelHash));
            address currentRegistryOwner = s().registry.owner(node);
            
            if (currentRegistryOwner != to) {
                s().registry.setSubnodeOwner(s().baseNode, labelHash, to);
            }
        }
    }
}
