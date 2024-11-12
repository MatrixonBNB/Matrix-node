// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ABIResolver} from "ens-contracts/resolvers/profiles/ABIResolver.sol";
import {AddrResolver} from "ens-contracts/resolvers/profiles/AddrResolver.sol";
import {ContentHashResolver} from "ens-contracts/resolvers/profiles/ContentHashResolver.sol";
import {DNSResolver} from "ens-contracts/resolvers/profiles/DNSResolver.sol";
import {ENS} from "ens-contracts/registry/ENS.sol";
import {ExtendedResolver} from "ens-contracts/resolvers/profiles/ExtendedResolver.sol";
import {IExtendedResolver} from "ens-contracts/resolvers/profiles/IExtendedResolver.sol";
import {InterfaceResolver} from "ens-contracts/resolvers/profiles/InterfaceResolver.sol";
import {Multicallable} from "ens-contracts/resolvers/Multicallable.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {NameResolver} from "ens-contracts/resolvers/profiles/NameResolver.sol";
import {PubkeyResolver} from "ens-contracts/resolvers/profiles/PubkeyResolver.sol";
import {TextResolver} from "ens-contracts/resolvers/profiles/TextResolver.sol";
import {IReverseRegistrar} from "src/facetnames/interface/IReverseRegistrar.sol";
import "solady/utils/Initializable.sol";
import {EventReplayable} from "src/libraries/EventReplayable.sol";

contract L2Resolver is
    Multicallable,
    ABIResolver,
    AddrResolver,
    ContentHashResolver,
    DNSResolver,
    InterfaceResolver,
    NameResolver,
    PubkeyResolver,
    TextResolver,
    ExtendedResolver,
    Ownable,
    Initializable,
    EventReplayable
{
    ENS public ens;
    address public registrarController;
    address public reverseRegistrar;
    mapping(address owner => mapping(address operator => bool isApproved)) private _operatorApprovals;
    mapping(address owner => mapping(bytes32 node => mapping(address delegate => bool isApproved))) private _tokenApprovals;

    error CantSetSelfAsOperator();
    error CantSetSelfAsDelegate();

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Approved(address owner, bytes32 indexed node, address indexed delegate, bool indexed approved);
    event RegistrarControllerUpdated(address indexed newRegistrarController);
    event ReverseRegistrarUpdated(address indexed newReverseRegistrar);

    constructor() {
        _disableInitializers();
    }

    function initialize(ENS ens_, address registrarController_, address reverseRegistrar_, address owner_) public initializer {
        ens = ens_;
        registrarController = registrarController_;
        reverseRegistrar = reverseRegistrar_;
        _initializeOwner(owner_);
        IReverseRegistrar(reverseRegistrar_).claim(owner_);
    }

    function setText(bytes32 node, string calldata key, string calldata value) external virtual override authorised(node) {
        versionable_texts[recordVersions[node]][node][key] = value;
        
        recordAndEmitEvent(
            "TextChanged(bytes32,string,string,string)",
            abi.encode(node, keccak256(bytes(key))),
            abi.encode(key, value)
        );
    }
    
    uint256 private constant COIN_TYPE_ETH = 60;
    
    function setAddr(bytes32 node, uint256 coinType, bytes memory a) public virtual override authorised(node) {
        recordAndEmitEvent(
            "AddressChanged(bytes32,uint256,bytes)",
            abi.encode(node),
            abi.encode(coinType, a)
        );
        
        if (coinType == COIN_TYPE_ETH) {
            recordAndEmitEvent(
                "AddrChanged(bytes32,address)",
                abi.encode(node),
                abi.encode(bytesToAddress(a))
            );
        }
        versionable_addresses[recordVersions[node]][node][coinType] = a;
    }
    
    function setName(bytes32 node, string calldata newName) external virtual override authorised(node) {
        versionable_names[recordVersions[node]][node] = newName;
        recordAndEmitEvent(
            "NameChanged(bytes32,string)",
            abi.encode(node),
            abi.encode(newName)
        );
    }

    function setRegistrarController(address registrarController_) external onlyOwner {
        registrarController = registrarController_;
        emit RegistrarControllerUpdated(registrarController_);
    }

    function setReverseRegistrar(address reverseRegistrar_) external onlyOwner {
        reverseRegistrar = reverseRegistrar_;
        emit ReverseRegistrarUpdated(reverseRegistrar_);
    }

    function setApprovalForAll(address operator, bool approved) external {
        if (msg.sender == operator) revert CantSetSelfAsOperator();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function approve(bytes32 node, address delegate, bool approved) external {
        if (msg.sender == delegate) revert CantSetSelfAsDelegate();
        _tokenApprovals[msg.sender][node][delegate] = approved;
        emit Approved(msg.sender, node, delegate, approved);
    }

    function isApprovedFor(address owner, bytes32 node, address delegate) public view returns (bool) {
        return _tokenApprovals[owner][node][delegate];
    }

    function isAuthorised(bytes32 node) internal view override returns (bool) {
        if (msg.sender == registrarController || msg.sender == reverseRegistrar) {
            return true;
        }
        address owner = ens.owner(node);
        return owner == msg.sender || isApprovedForAll(owner, msg.sender) || isApprovedFor(owner, node, msg.sender);
    }

    function supportsInterface(bytes4 interfaceID)
        public
        view
        override(
            Multicallable,
            ABIResolver,
            AddrResolver,
            ContentHashResolver,
            DNSResolver,
            InterfaceResolver,
            NameResolver,
            PubkeyResolver,
            TextResolver
        )
        returns (bool)
    {
        return (interfaceID == type(IExtendedResolver).interfaceId || super.supportsInterface(interfaceID));
    }
}
