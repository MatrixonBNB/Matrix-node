//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ENS} from "ens-contracts/registry/ENS.sol";
import {NameResolver} from "ens-contracts/resolvers/profiles/NameResolver.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Sha3} from "src/facetnames/lib/Sha3.sol";
import "solady/utils/Initializable.sol";

contract ReverseRegistrar is Ownable, Initializable {
    ENS public registry;
    bytes32 public reverseNode;
    mapping(address controller => bool approved) public controllers;
    NameResolver public defaultResolver;

    error NotAuthorized(address addr, address sender);
    error NoZeroAddress();

    event FacetReverseClaimed(address indexed addr, bytes32 indexed node);
    event DefaultResolverChanged(NameResolver indexed resolver);
    event ControllerApprovalChanged(address indexed controller, bool approved);

    modifier authorized(address addr) {
        if (
            addr != msg.sender && !controllers[msg.sender] && !registry.isApprovedForAll(addr, msg.sender)
                && !_ownsContract(addr)
        ) {
            revert NotAuthorized(addr, msg.sender);
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }
    
    function initialize(ENS registry_, address owner_, bytes32 reverseNode_) public initializer {
        _initializeOwner(owner_);
        registry = registry_;
        reverseNode = reverseNode_;
    }

    function setDefaultResolver(address resolver) public onlyOwner {
        if (address(resolver) == address(0)) revert NoZeroAddress();
        defaultResolver = NameResolver(resolver);
        registry.setResolver(reverseNode, resolver);
        emit DefaultResolverChanged(defaultResolver);
    }

    function setControllerApproval(address controller, bool approved) public onlyOwner {
        if (controller == address(0)) revert NoZeroAddress();
        controllers[controller] = approved;
        emit ControllerApprovalChanged(controller, approved);
    }

    function claim(address owner) public returns (bytes32) {
        return claimForBaseAddr(msg.sender, owner, address(defaultResolver));
    }

    function claimForBaseAddr(address addr, address owner, address resolver)
        public
        authorized(addr)
        returns (bytes32)
    {
        bytes32 labelHash = Sha3.hexAddress(addr);
        bytes32 baseReverseNode = keccak256(abi.encodePacked(reverseNode, labelHash));
        emit FacetReverseClaimed(addr, baseReverseNode);
        registry.setSubnodeRecord(reverseNode, labelHash, owner, resolver, 0);
        return baseReverseNode;
    }

    function claimWithResolver(address owner, address resolver) public returns (bytes32) {
        return claimForBaseAddr(msg.sender, owner, resolver);
    }

    function setName(string memory name) public returns (bytes32) {
        return setNameForAddr(msg.sender, msg.sender, address(defaultResolver), name);
    }

    function setNameForAddr(address addr, address owner, address resolver, string memory name)
        public
        returns (bytes32)
    {
        bytes32 baseNode_ = claimForBaseAddr(addr, owner, resolver);
        NameResolver(resolver).setName(baseNode_, name);
        return baseNode_;
    }

    function node(address addr) public view returns (bytes32) {
        return keccak256(abi.encodePacked(reverseNode, Sha3.hexAddress(addr)));
    }

    function _ownsContract(address addr) internal view returns (bool) {
        if (addr.code.length == 0) {
            return false;
        }
        try Ownable(addr).owner() returns (address owner) {
            return owner == msg.sender;
        } catch {
            return false;
        }
    }
}
