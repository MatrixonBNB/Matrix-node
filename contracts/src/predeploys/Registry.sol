// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ENS} from "ens-contracts/registry/ENS.sol";
import "solady/utils/Initializable.sol";
import {EventReplayable} from "src/libraries/EventReplayable.sol";

contract Registry is ENS, Initializable, EventReplayable {
    struct Record {
        address owner;
        address resolver;
        uint64 ttl;
    }

    mapping(bytes32 node => Record record) internal _records;
    mapping(address nameHolder => mapping(address operator => bool isApproved)) internal _operators;

    error Unauthorized();

    modifier authorized(bytes32 node) {
        address owner_ = _records[node].owner;
        if (owner_ != msg.sender && !_operators[owner_][msg.sender]) revert Unauthorized();
        _;
    }

    constructor() {
        _disableInitializers();
    }
    
    function initialize(address rootOwner) public initializer {
        _records[0x0].owner = rootOwner;
    }

    function setRecord(bytes32 node, address owner_, address resolver_, uint64 ttl_) external virtual override {
        setOwner(node, owner_);
        _setResolverAndTTL(node, resolver_, ttl_);
    }

    function setSubnodeRecord(bytes32 node, bytes32 label, address owner_, address resolver_, uint64 ttl_)
        external
        virtual
        override
    {
        bytes32 subnode = setSubnodeOwner(node, label, owner_);
        _setResolverAndTTL(subnode, resolver_, ttl_);
    }

    function setOwner(bytes32 node, address owner_) public virtual override authorized(node) {
        _setOwner(node, owner_);

        recordAndEmitEvent(
            "Transfer(bytes32,address)",
            abi.encode(node),
            abi.encode(owner_)
        );
    }

    function setSubnodeOwner(bytes32 node, bytes32 label, address owner_)
        public
        virtual
        override
        authorized(node)
        returns (bytes32)
    {
        bytes32 subnode = keccak256(abi.encodePacked(node, label));
        _setOwner(subnode, owner_);
        
        recordAndEmitEvent(
            "NewOwner(bytes32,bytes32,address)",
            abi.encode(node, label),
            abi.encode(owner_)
        );
        return subnode;
    }

    function setResolver(bytes32 node, address resolver_) public virtual override authorized(node) {
        _records[node].resolver = resolver_;
        
        recordAndEmitEvent(
            "NewResolver(bytes32,address)",
            abi.encode(node),
            abi.encode(resolver_)
        );
    }

    function setTTL(bytes32 node, uint64 ttl_) public virtual override authorized(node) {
        _records[node].ttl = ttl_;
        emit NewTTL(node, ttl_);
    }

    function setApprovalForAll(address operator, bool approved) external virtual override {
        _operators[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function owner(bytes32 node) public view virtual override returns (address) {
        address addr = _records[node].owner;
        if (addr == address(this)) {
            return address(0);
        }
        return addr;
    }

    function resolver(bytes32 node) public view virtual override returns (address) {
        return _records[node].resolver;
    }

    function ttl(bytes32 node) public view virtual override returns (uint64) {
        return _records[node].ttl;
    }

    function recordExists(bytes32 node) public view virtual override returns (bool) {
        return _records[node].owner != address(0x0);
    }

    function isApprovedForAll(address owner_, address operator) external view virtual override returns (bool) {
        return _operators[owner_][operator];
    }

    function _setOwner(bytes32 node, address owner_) internal virtual {
        _records[node].owner = owner_;
    }

    function _setResolverAndTTL(bytes32 node, address resolver_, uint64 ttl_) internal {
        if (resolver_ != _records[node].resolver) {
            _records[node].resolver = resolver_;
            
            recordAndEmitEvent(
                "NewResolver(bytes32,address)",
                abi.encode(node),
                abi.encode(resolver_)
            );
        }

        if (ttl_ != _records[node].ttl) {
            _records[node].ttl = ttl_;
            emit NewTTL(node, ttl_);
        }
    }
}
