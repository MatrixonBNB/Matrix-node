// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "src/libraries/MigrationLib.sol";
import "src/libraries/FacetERC20.sol";
import "src/predeploys/MigrationManager.sol";

contract TestToken is FacetERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _initializeERC20(name_, symbol_, decimals_);
    }
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract TestMigrationManager is Script, Test {
    MigrationManager public migrationManager;
    TestToken[] public tokens;
    address[] public holders;
    
    uint256 constant NUM_TOKENS = 178;
    uint256 constant NUM_HOLDERS = 777;
    
    address constant MIGRATION_MANAGER = MigrationLib.MIGRATION_MANAGER;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        vm.etch(MIGRATION_MANAGER, type(MigrationManager).runtimeCode);
        migrationManager = MigrationManager(MIGRATION_MANAGER);
        
        // Create tokens
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            TestToken token = new TestToken(
                string(abi.encodePacked("Token ", uint256(i + 1))),
                string(abi.encodePacked("TK", uint256(i + 1))),
                18
            );
            tokens.push(token);
        }

        // Create holders
        for (uint256 i = 0; i < NUM_HOLDERS; i++) {
            holders.push(address(uint160(i + 1)));
        }
    }

    function run() public {
        vm.etch(MigrationLib.DUMMY_ADDRESS, new bytes(1)); // Start migration

        // Mint and transfer tokens
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            mintAndTransfer(tokens[i]);
        }
        
        vm.etch(MigrationLib.DUMMY_ADDRESS, new bytes(0)); // End migration

        // Prepare to capture events
        vm.recordLogs();
        // vm.dumpState("start_laksdjkldfs.json");
        // Measure gas usage of executeMigration
        uint256 totalTransactionsRequired = migrationManager.transactionsRequired();
        console.log("Total transactions required:", totalTransactionsRequired);
        
        uint256 gasBeforeMigration = gasleft();
        vm.startPrank(MigrationLib.SYSTEM_ADDRESS);
        for (uint256 i = 0; i < totalTransactionsRequired; i++) {
            uint256 remainingEvents = migrationManager.executeMigration();
            console.log("Remaining events:", remainingEvents);
        }
        vm.stopPrank();
        uint256 gasAfterMigration = gasleft();
        uint256 gasUsed = gasBeforeMigration - gasAfterMigration;

        console.log("Gas used for executeMigration:", gasUsed);
        // vm.dumpState("end_laksdjkldfs.json");
        // // Verify emitted events
        verifyMigrationEvents();
        
        // // Try transfers after migration
        testTransfersAfterMigration();

        // // Verify all data is cleared
        // verifyMigrationCleared();
    }

    function mintAndTransfer(TestToken token) internal {
        for (uint256 i = 0; i < NUM_HOLDERS; i++) {
            // Generate a random amount between 1 and 1000 ether
            uint256 amount = (uint256(keccak256(abi.encodePacked(block.timestamp, token, i))) % 1000 + 1) * 1 ether;
            token.mint(holders[i], amount);
        }
        
        // Perform some random transfers
        for (uint256 i = 0; i < 10; i++) {
            uint256 fromIndex = uint256(keccak256(abi.encodePacked(block.timestamp, token, i, "from"))) % NUM_HOLDERS;
            uint256 toIndex = uint256(keccak256(abi.encodePacked(block.timestamp, token, i, "to"))) % NUM_HOLDERS;
            if (fromIndex != toIndex) {
                address from = holders[fromIndex];
                address to = holders[toIndex];
                uint256 amount = token.balanceOf(from) / 10;
                vm.prank(from);
                token.transfer(to, amount);
            }
        }
    }

    function testTransfersAfterMigration() internal {
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            TestToken token = tokens[i];
            address from = holders[i % NUM_HOLDERS];
            address to = holders[(i + 1) % NUM_HOLDERS];
            uint256 amount = token.balanceOf(from) / 10;
            
            vm.prank(from);
            require(token.transfer(to, amount), string(abi.encodePacked("Transfer failed for token ", token.symbol())));
        }

        console.log("Transfers after migration completed successfully");
    }

    function verifyMigrationEvents() internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 expectedEventCount = NUM_TOKENS * NUM_HOLDERS;
        uint256 actualEventCount = 0;

        for (uint i = 0; i < entries.length; i++) {
            Vm.Log memory entry = entries[i];

            if (entry.topics[0] == keccak256("Transfer(address,address,uint256)")) {
                address from = address(uint160(uint256(entry.topics[1])));
                address to = address(uint160(uint256(entry.topics[2])));
                uint256 value = abi.decode(entry.data, (uint256));
                address emittingContract = entry.emitter;

                require(from == address(0), "Transfer should be from zero address");

                bool foundMatch = false;
                for (uint j = 0; j < tokens.length; j++) {
                    if (emittingContract == address(tokens[j])) {
                        for (uint k = 0; k < holders.length; k++) {
                            if (to == holders[k] && value == tokens[j].balanceOf(holders[k])) {
                                foundMatch = true;
                                actualEventCount++;
                                break;
                            }
                        }
                        if (foundMatch) break;
                    }
                }

                require(foundMatch, "Unexpected Transfer event emitted");
            }
        }

        require(actualEventCount == expectedEventCount, "Incorrect number of Transfer events emitted");
        console.log("Migration events verified successfully");
    }

    // function verifyMigrationCleared() internal {
    //     bool isCleared = migrationManager.verifyCleared();
    //     require(isCleared, "Migration did not clear all data");
        
    //     // Additional checks for each mapping and array
    //     for (uint i = 0; i < NUM_TOKENS; i++) {
    //         address token = address(tokens[i]);
            
    //         // Check tokenHolderIndex
    //         for (uint j = 0; j < NUM_HOLDERS; j++) {
    //             address holder = holders[j];
    //             (bool success, bytes memory data) = address(migrationManager).staticcall(
    //                 abi.encodeWithSignature("tokenHolderIndex(address,address)", token, holder)
    //             );
    //             require(success, "Failed to call tokenHolderIndex");
    //             uint256 index = abi.decode(data, (uint256));
    //             require(index == 0, "tokenHolderIndex not cleared");
    //         }
            
    //         // Check tokenTransfers
    //         (bool success, bytes memory data) = address(migrationManager).staticcall(
    //             abi.encodeWithSignature("tokenTransfers(address,uint256)", token, 0)
    //         );
    //         require(success, "Failed to call tokenTransfers");
    //         (address to, uint96 value) = abi.decode(data, (address, uint96));
    //         require(to == address(0) && value == 0, "tokenTransfers not cleared");
    //     }
        
    //     // Check tokens array
    //     (bool success, bytes memory data) = address(migrationManager).staticcall(
    //         abi.encodeWithSignature("tokens(uint256)", 0)
    //     );
    //     require(success, "Failed to call tokens");
    //     address tokenAddress = abi.decode(data, (address));
    //     require(tokenAddress == address(0), "tokens array not cleared");
        
    //     // Check migrationExecuted
    //     bool executed = migrationManager.migrationExecuted();
    //     require(executed, "migrationExecuted not set to true");
        
    //     console.log("All migration data cleared successfully");
    // }
}
