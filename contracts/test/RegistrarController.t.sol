// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {RegistrarController} from "src/facetnames/RegistrarController.sol";
import {MockWETH} from "test/MockWETH.sol";

contract RegistrarControllerTest is Test {
    RegistrarController controller;
    MockWETH weth;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    
    function setUp() public {
        // Deploy WETH
        weth = new MockWETH();
        
        // Set up price array
        uint256 usdWeiCentsInOneEth = 200000000000000000000000;  // Original value
        
        uint256[] memory prices = new uint256[](6);
        // Convert each USD cent price to ETH: (priceInUsdCents * 1 ether) / usdWeiCentsInOneEth
        prices[0] = (31709791983764584 * 1 ether) / usdWeiCentsInOneEth;  // 1 letter
        prices[1] = (3170979198376458 * 1 ether) / usdWeiCentsInOneEth;   // 2 letter
        prices[2] = (1585489599188229 * 1 ether) / usdWeiCentsInOneEth;   // 3 letter
        prices[3] = (317097919837645 * 1 ether) / usdWeiCentsInOneEth;    // 4 letter
        prices[4] = (31709791983764 * 1 ether) / usdWeiCentsInOneEth;     // 5-9 letter
        prices[5] = (31709791983764 * 1 ether) / usdWeiCentsInOneEth;     // 10+ letter (same as 5-9)
        
        for (uint256 i = 0; i < prices.length; i++) {
            console.log("Price for %d letters: %d ETH", i + 1, prices[i]);
        }
        
        
        // Deploy controller
        controller = new RegistrarController({
            owner_: address(this),
            paymentReceiver_: address(this),
            baseDomainName_: "facet.eth",
            prices_: prices,
            premiumStart_: 500 ether,
            totalDays_: 28 days,
            wethToken_: weth
        });
        
        // Give some WETH to test accounts
        weth.transfer(alice, 100 ether);
        weth.transfer(bob, 100 ether);
        
        vm.warp(1735689600);
    }
    
    function test_RegisterNameWithPayment() public {
        vm.startPrank(alice);
        
        // Approve WETH spending
        uint256 registrationFee = controller.registerPrice("test", 365 days);
        weth.approve(address(controller), registrationFee);
        
        // Register name
        controller.registerNameWithPayment(alice, "test", 365 days);
        
        // Verify registration
        assertTrue(controller.available("test") == false, "Name should be registered");
        assertEq(controller.base().ownerOf(uint256(keccak256("test"))), alice, "Alice should own the name");
        
        // Verify reverse record was set (since it's first registration)
        assertTrue(controller.hasReverseRecord(alice), "Reverse record should be set");
        
        vm.stopPrank();
    }
    
    function test_RegisterNameForOther() public {
        vm.startPrank(alice);
        
        // Approve WETH spending
        uint256 registrationFee = controller.registerPrice("test", 365 days);
        weth.approve(address(controller), registrationFee);
        
        // Register name for Bob
        controller.registerNameWithPayment(bob, "test", 365 days);
        
        // Verify registration
        assertTrue(controller.available("test") == false, "Name should be registered");
        assertEq(controller.base().ownerOf(uint256(keccak256("test"))), bob, "Bob should own the name");
        
        // Verify no reverse record was set (since registration was for someone else)
        assertFalse(controller.hasReverseRecord(bob), "Reverse record should not be set");
        
        vm.stopPrank();
    }
    
    function test_RegisterSecondName() public {
        vm.startPrank(alice);
        
        // Register first name
        uint256 registrationFee = controller.registerPrice("test1", 365 days);
        weth.approve(address(controller), registrationFee);
        controller.registerNameWithPayment(alice, "test1", 365 days);
        
        // Register second name
        registrationFee = controller.registerPrice("test2", 365 days);
        weth.approve(address(controller), registrationFee);
        controller.registerNameWithPayment(alice, "test2", 365 days);
        
        // Verify both registrations
        assertEq(controller.base().ownerOf(uint256(keccak256("test1"))), alice, "Alice should own test1");
        assertEq(controller.base().ownerOf(uint256(keccak256("test2"))), alice, "Alice should own test2");
        
        // Verify reverse record wasn't changed (since it was set by first registration)
        assertTrue(controller.hasReverseRecord(alice), "Reverse record should still exist");
        
        vm.stopPrank();
    }
    
    function test_SetPrimaryName() public {
        vm.startPrank(alice);
        
        // Register two names for Alice
        uint256 registrationFee = controller.registerPrice("test1", 365 days);
        weth.approve(address(controller), registrationFee);
        controller.registerNameWithPayment(alice, "test1", 365 days);
        
        registrationFee = controller.registerPrice("test2", 365 days);
        weth.approve(address(controller), registrationFee);
        controller.registerNameWithPayment(alice, "test2", 365 days);
        
        // Change primary name to test2
        controller.setPrimaryName("test2");
        
        // Verify reverse record was updated
        bytes32 reverseNode = controller.reverseRegistrar().node(alice);
        string memory resolvedName = controller.resolver().name(reverseNode);
        assertEq(resolvedName, "test2.facet.eth", "Reverse record should point to test2.facet.eth");
        
        vm.stopPrank();
    }
    
    function testFail_SetPrimaryNameNotOwned() public {
        vm.startPrank(alice);
        
        // Register name for Bob
        uint256 registrationFee = controller.registerPrice("test", 365 days);
        weth.approve(address(controller), registrationFee);
        controller.registerNameWithPayment(bob, "test", 365 days);
        
        // Try to set Bob's name as Alice's primary name (should fail)
        controller.setPrimaryName("test");
        
        vm.stopPrank();
    }
    
    function test_SetPrimaryNameMultipleTimes() public {
        vm.startPrank(alice);
        
        // Register three names
        string[3] memory names = ["test1", "test2", "test3"];
        for(uint i = 0; i < names.length; i++) {
            uint256 registrationFee = controller.registerPrice(names[i], 365 days);
            weth.approve(address(controller), registrationFee);
            controller.registerNameWithPayment(alice, names[i], 365 days);
        }
        
        // Change primary name multiple times and verify each change
        for(uint i = 0; i < names.length; i++) {
            controller.setPrimaryName(names[i]);
            
            bytes32 reverseNode = controller.reverseRegistrar().node(alice);
            string memory resolvedName = controller.resolver().name(reverseNode);
            assertEq(
                resolvedName, 
                string.concat(names[i], ".facet.eth"), 
                "Reverse record should point to correct name"
            );
        }
        
        vm.stopPrank();
    }
    
    function _getV1TokenId(string memory name) internal view returns (uint256) {
        return controller.v2TokenIdToV1TokenId(uint256(keccak256(bytes(name))));
    }
    
    function test_SetCardDetails() public {
        vm.startPrank(alice);
        
        // First register a name
        uint256 registrationFee = controller.registerPrice("test", 365 days);
        weth.approve(address(controller), registrationFee);
        controller.registerNameWithPayment(alice, "test", 365 days);
        
        // Prepare card details
        string[] memory links = new string[](3);
        links[0] = "https://twitter.com/alice";
        links[1] = "https://github.com/alice";
        links[2] = "https://alice.blog";
        
        // Set card details
        uint256 v2TokenId = uint256(keccak256(bytes("test")));
        uint256 v1TokenId = controller.v2TokenIdToV1TokenId(v2TokenId);
        
        controller.setCardDetails(
            v1TokenId,
            "test",
            "Alice in Wonderland",
            "Crypto enthusiast & developer",
            "ipfs://Qm...",
            links
        );
        
        // Get the node
        bytes32 node = controller._encodeName("test.facet.eth");
        
        // Verify all text records were set correctly
        assertEq(
            controller.resolver().text(node, "alias"),
            "Alice in Wonderland",
            "Display name should be set"
        );
        assertEq(
            controller.resolver().text(node, "description"),
            "Crypto enthusiast & developer",
            "Bio should be set"
        );
        assertEq(
            controller.resolver().text(node, "avatar"),
            "ipfs://Qm...",
            "Avatar should be set"
        );
        
        // Verify links
        assertEq(
            controller.resolver().text(node, "url"),
            links[0],
            "First link should be set"
        );
        assertEq(
            controller.resolver().text(node, "url2"),
            links[1],
            "Second link should be set"
        );
        assertEq(
            controller.resolver().text(node, "url3"),
            links[2],
            "Third link should be set"
        );
        
        vm.stopPrank();
    }
    
    function testFail_SetCardDetailsNotOwned() public {
        vm.startPrank(alice);
        
        // Register name for Bob
        uint256 registrationFee = controller.registerPrice("test", 365 days);
        weth.approve(address(controller), registrationFee);
        controller.registerNameWithPayment(bob, "test", 365 days);
        
        // Try to set card details for Bob's name (should fail)
        string[] memory links = new string[](1);
        links[0] = "https://example.com";
        
        uint256 v2TokenId = uint256(keccak256(bytes("test")));
        uint256 v1TokenId = controller.v2TokenIdToV1TokenId(v2TokenId);
        
        controller.setCardDetails(
            v1TokenId,
            "test",
            "Alice",
            "Bio",
            "avatar",
            links
        );
        
        vm.stopPrank();
    }
    
    function test_UpdateCardDetails() public {
        vm.startPrank(alice);
        
        // Register name
        uint256 registrationFee = controller.registerPrice("test", 365 days);
        weth.approve(address(controller), registrationFee);
        controller.registerNameWithPayment(alice, "test", 365 days);
        
        uint256 v2TokenId = uint256(keccak256(bytes("test")));
        uint256 v1TokenId = controller.v2TokenIdToV1TokenId(v2TokenId);
        
        bytes32 node = controller._encodeName("test.facet.eth");
        
        // Set initial details
        string[] memory initialLinks = new string[](1);
        initialLinks[0] = "https://initial.com";
        controller.setCardDetails(
            v1TokenId,
            "test",
            "Initial Name",
            "Initial Bio",
            "initial-avatar",
            initialLinks
        );
        
        // Update details
        string[] memory newLinks = new string[](2);
        newLinks[0] = "https://new.com";
        newLinks[1] = "https://another.com";
        controller.setCardDetails(
            v1TokenId,
            "test",
            "Updated Name",
            "Updated Bio",
            "new-avatar",
            newLinks
        );
        
        // Verify updates
        assertEq(
            controller.resolver().text(node, "alias"),
            "Updated Name",
            "Display name should be updated"
        );
        assertEq(
            controller.resolver().text(node, "url"),
            newLinks[0],
            "First link should be updated"
        );
        assertEq(
            controller.resolver().text(node, "url2"),
            newLinks[1],
            "Second link should be added"
        );
        
        vm.stopPrank();
    }
    
    function test_ImportFromPreregistration() public {
        // Only owner can import
        vm.startPrank(address(this));  // Test contract is the owner
        
        // Prepare batch data
        string[] memory names = new string[](3);
        names[0] = "alice";
        names[1] = "bob";
        names[2] = "charlie";
        
        address[] memory owners = new address[](3);
        owners[0] = alice;
        owners[1] = bob;
        owners[2] = makeAddr("charlie");
        
        uint256[] memory durations = new uint256[](3);
        durations[0] = 365 days;
        durations[1] = 730 days;
        durations[2] = 365 days;
        
        // Import names
        controller.importFromPreregistration(names, owners, durations);
        
        // Verify registrations
        for(uint i = 0; i < names.length; i++) {
            assertEq(controller.ownerOfName(names[i]), owners[i], "Owner should be set correctly");
            assertTrue(!controller.available(names[i]), "Name should be registered");
            assertTrue(controller.hasReverseRecord(owners[i]), "Reverse record should be set");
        }
        
        vm.stopPrank();
    }
    
    function testFail_ImportAfterPreregistrationComplete() public {
        vm.startPrank(address(this));
        
        // Mark preregistration as complete
        controller.markPreregistrationComplete();
        
        // Try to import (should fail)
        string[] memory names = new string[](1);
        address[] memory owners = new address[](1);
        uint256[] memory durations = new uint256[](1);
        names[0] = "test";
        owners[0] = alice;
        durations[0] = 365 days;
        
        controller.importFromPreregistration(names, owners, durations);
        
        vm.stopPrank();
    }
    
    function testFail_ImportFromNonOwner() public {
        vm.startPrank(alice);  // Alice is not the owner
        
        string[] memory names = new string[](1);
        address[] memory owners = new address[](1);
        uint256[] memory durations = new uint256[](1);
        names[0] = "test";
        owners[0] = alice;
        durations[0] = 365 days;
        
        controller.importFromPreregistration(names, owners, durations);
        
        vm.stopPrank();
    }
    
    function testFail_ImportMismatchedArrayLengths() public {
        vm.startPrank(address(this));
        
        string[] memory names = new string[](2);
        names[0] = "test1";
        names[1] = "test2";
        
        address[] memory owners = new address[](1);
        owners[0] = alice;
        
        uint256[] memory durations = new uint256[](2);
        durations[0] = 365 days;
        durations[1] = 365 days;
        
        controller.importFromPreregistration(names, owners, durations);
        
        vm.stopPrank();
    }
    
    function test_ImportWithExistingReverseRecord() public {
        vm.startPrank(address(this));
        
        // First import for alice
        string[] memory names1 = new string[](1);
        address[] memory owners1 = new address[](1);
        uint256[] memory durations1 = new uint256[](1);
        names1[0] = "alice1";
        owners1[0] = alice;
        durations1[0] = 365 days;
        
        controller.importFromPreregistration(names1, owners1, durations1);
        assertTrue(controller.hasReverseRecord(alice), "First reverse record should be set");
        
        // Second import for alice
        string[] memory names2 = new string[](1);
        address[] memory owners2 = new address[](1);
        uint256[] memory durations2 = new uint256[](1);
        names2[0] = "alice2";
        owners2[0] = alice;
        durations2[0] = 365 days;
        
        controller.importFromPreregistration(names2, owners2, durations2);
        
        // Verify both names are registered but reverse record points to first name
        assertEq(controller.ownerOfName("alice1"), alice, "First name should be registered");
        assertEq(controller.ownerOfName("alice2"), alice, "Second name should be registered");
        
        bytes32 reverseNode = controller.reverseRegistrar().node(alice);
        string memory resolvedName = controller.resolver().name(reverseNode);
        assertEq(resolvedName, "alice1.facet.eth", "Reverse record should still point to first name");
        
        vm.stopPrank();
    }
}
