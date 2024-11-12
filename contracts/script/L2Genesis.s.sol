// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import "solady/utils/LibString.sol";
import { stdJson } from "forge-std/StdJson.sol";

contract L2Genesis is Script {
    using LibString for *;
    using stdJson for string;

    uint256 public constant PRECOMPILE_COUNT = 256;
    address internal deployer;
    
    struct PredeployContract {
        address addr;
        string name;
    }
    
    struct PredeployContractList {
        PredeployContract[] contracts;
    }

    PredeployContractList internal predeployContracts;
    
    function setUp() public {
        deployer = makeAddr("deployer");
        populatePredeployContracts();
    }

    function runWithoutDump() public {
        vm.startPrank(deployer);
        etchContracts();
        vm.stopPrank();
        
        // Only clear genesis deployer state, not msg.sender
        vm.deal(deployer, 0);
        vm.resetNonce(deployer);
    }

    function run() public {
        runWithoutDump();
        
        // Only do this cleanup in actual deployment, not tests
        vm.etch(msg.sender, "");
        vm.resetNonce(msg.sender);
        vm.deal(msg.sender, 0);

        console.log("Writing state dump to: genesis-test.json");
        vm.dumpState("facet-local-genesis-allocs.json");
        writePredeployContractsToJson();
    }
    
    function etchContracts() internal {
        console.log("Etching contracts");
        for (uint i = 0; i < predeployContracts.contracts.length; i++) {
            string memory name = predeployContracts.contracts[i].name;
            address addr = predeployContracts.contracts[i].addr;
            
            etchContract(name, addr);
        }
    }
    
    function isDeployedByContract(string memory contractName) internal pure returns (bool) {
        return contractName.startsWith("ERC20BridgeV") ||
               contractName.startsWith("FacetBuddyV") ||
               contractName.startsWith("FacetSwapPairV");
    }

    function etchContract(string memory contractName, address addr) internal {
        string memory artifactPath = string(abi.encodePacked("src/predeploys/", contractName, ".sol"));
        artifactPath = string(abi.encodePacked(artifactPath, ":", contractName));
        
        bytes memory bytecode = vm.getDeployedCode(artifactPath);
        vm.etch(addr, bytecode);
        
        vm.setNonce(addr, 1);
        
        if (!contractName.eq("MigrationManager") && !contractName.eq("NonExistentContractShim")) {
            disableInitializableSlot(addr);
        }
        
        console.log("Etched", contractName, "at", vm.toString(addr));
    }
    
    function disableInitializableSlot(address addr) internal {
        bytes32 slot = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132;
        uint256 maxUint64 = type(uint64).max;
        uint256 value = maxUint64 << 1;
        bytes32 valueBytes = bytes32(value);
        vm.store(addr, slot, valueBytes);
    }
    
    function populatePredeployContracts() internal {
        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = "bundle exec rails runner 'puts ({contracts: PredeployManager.predeploy_to_local_map.invert.map { |name, addr| {name: name, addr: addr} } }.to_json)' | tail -n 1";
        bytes memory result = vm.ffi(inputs);
        string memory json = string(result);
        
        // Parse the JSON and populate the struct
        bytes memory parsedJson = vm.parseJson(json);
        predeployContracts = abi.decode(parsedJson, (PredeployContractList));
        
        PredeployContract[] memory derivedContracts = new PredeployContract[](predeployContracts.contracts.length);
        uint256 derivedCount = 0;

        for (uint i = 0; i < predeployContracts.contracts.length; i++) {
            string memory name = predeployContracts.contracts[i].name;
            address addr = predeployContracts.contracts[i].addr;
            
            if (isDeployedByContract(name)) {
                console.log("Deployed by contract:", name);
                string memory artifactPath = string(abi.encodePacked("predeploys/", name, ".sol:", name));
                bytes memory creationCode = vm.getCode(artifactPath);
                bytes32 initCodeHash = keccak256(creationCode);
                address derivedAddress = address(uint160(uint256(initCodeHash)));
                derivedContracts[derivedCount] = PredeployContract({name: name, addr: derivedAddress});
                derivedCount++;
            }
        }

        // Add derived contracts to predeployContracts
        for (uint i = 0; i < derivedCount; i++) {
            predeployContracts.contracts.push(derivedContracts[i]);
        }
    }

    function writePredeployContractsToJson() internal {
        string memory jsonPath = "predeploy-contracts.json";
        string memory json = "["; // Start with an opening bracket

        for (uint i = 0; i < predeployContracts.contracts.length; i++) {
            PredeployContract memory c = predeployContracts.contracts[i];
            
            // Create a JSON object for each contract
            string memory contractJson = string(abi.encodePacked(
                '{"name":"', c.name, '","addr":"', c.addr.toHexString(), '"}'
            ));

            // Add comma if it's not the first element
            if (i > 0) {
                json = string(abi.encodePacked(json, ","));
            }

            // Append the contract object to the array
            json = string(abi.encodePacked(json, contractJson));
        }

        // Close the array
        json = string(abi.encodePacked(json, "]"));

        // Write the final JSON array to the file
        vm.writeFile(jsonPath, json);

        console.log("Wrote predeploy contracts to:", jsonPath);
    }
}
