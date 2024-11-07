// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/ERC1967Proxy.sol";
import "src/libraries/AddressAliasHelper.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import "src/predeploys/FacetSwapFactoryVac5.sol";
import "src/predeploys/FacetSwapRouterV56d.sol";
import { EtherBridgeVd58 } from "src/predeploys/EtherBridgeVd58.sol";
import { FacetOptimismMintableERC20 } from "src/FacetOptimismMintableERC20.sol";
import { FoundryFacetSender } from "lib/facet-sol/src/foundry-utils/FoundryFacetSender.sol";
import { JSONParserLib } from "solady/src/utils/JSONParserLib.sol";
import { LibRLP } from "solady/src/utils/LibRLP.sol";
import "solady/src/utils/ERC1967FactoryConstants.sol";
import "solady/src/utils/ERC1967Factory.sol";
import "solady/src/utils/GasBurnerLib.sol";

contract Stresser {
    using AddressAliasHelper for address;

    constructor() {
        GasBurnerLib.burn(40_000_000);
    }
}

contract StressTest is Script, Test, FoundryFacetSender {
    using AddressAliasHelper for address;
    
    function run() public broadcast {
        for (uint256 i = 0; i < 10; i++) {
            deployContract(
                "Stresser",
                type(Stresser).creationCode,
                ""
            );
        }
    }
    
    function deployContract(string memory _name, bytes memory _creationCode, bytes memory _initData) public returns (address addr_) {
        addr_ = nextL2Address();
        console.log(string.concat("Deploying contract ", _name));
        sendFacetTransactionFoundry({
            gasLimit: 50_000_000,
            data: abi.encodePacked(_creationCode, _initData)
        });
        console.log("   at %s", addr_);
    }
    
    function deployImplementation(string memory _name, bytes memory _creationCode) public returns (address addr_) {
        addr_ = nextL2Address();
        console.log(string.concat("Deploying implementation for ", _name));
        sendFacetTransactionFoundry({
            gasLimit: 20_000_000,
            data: _creationCode
        });
        console.log("   at %s", addr_);
    }
    
    function deployERC1967Proxy(
        string memory _name,
        address implementation,
        bytes memory _data
    )
        public
        returns (address addr_)
    {
        console.log(string.concat("Deploying ERC1967 proxy for ", _name));

        addr_ = nextL2Address();

        sendFacetTransactionFoundry({
            gasLimit: 20_000_000,
            data: abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(implementation, _data)
            )
        });
        
        console.log("   at %s", addr_);
    }
}
