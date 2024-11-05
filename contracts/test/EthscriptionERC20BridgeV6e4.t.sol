// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/predeploys/EthscriptionERC20BridgeV6e4.sol";
import "src/libraries/ERC1967Proxy.sol";
import {console2} from "forge-std/console2.sol";

contract MockL1Block {
    uint64 private number_;
    bytes32 private hash_;
    
    function setNumber(uint64 _number) external {
        number_ = _number;
    }
    
    function setHash(bytes32 _hash) external {
        hash_ = _hash;
    }
    
    function number() external view returns (uint64) {
        return number_;
    }
    
    function hash() external view returns (bytes32) {
        return hash_;
    }
}

contract EthscriptionERC20BridgeV6e4Test is Test {
    MockL1Block public constant l1Block = MockL1Block(0x4200000000000000000000000000000000000015);
  
    EthscriptionERC20BridgeV6e4 public bridge;
    MockL1Block public mockL1Block;
    address public trustedSmartContract;
    address public user1;
    address public user2;
    
    event BridgedIn(address indexed to, uint256 amount);
    event InitiateWithdrawal(address indexed from, uint256 amount, bytes32 indexed withdrawalId);
    event WithdrawalComplete(address indexed to, uint256 amount, bytes32 indexed withdrawalId);
    
    function setUp() public {
        mockL1Block = MockL1Block(0x4200000000000000000000000000000000000015);
        trustedSmartContract = makeAddr("trustedSmartContract");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy bridge with mock L1Block address
        vm.etch(address(mockL1Block), address(new MockL1Block()).code);
        vm.etch(MigrationLib.DUMMY_ADDRESS, new bytes(0));
        
        address bridgeImplementation = address(new EthscriptionERC20BridgeV6e4());
        bytes memory initData = abi.encodeCall(
            EthscriptionERC20BridgeV6e4.initialize,
            ("Test Token", "TEST", 1000, trustedSmartContract, 1000, false)
        );
        
        bridge = EthscriptionERC20BridgeV6e4(
            address(new ERC1967Proxy(bridgeImplementation, initData))
        );
    }
    
    function test_BridgeIn() public {
        uint256 amount = 10;
        vm.prank(trustedSmartContract);
        
        vm.expectEmit(true, false, false, true);
        emit BridgedIn(user1, amount);
        
        bridge.bridgeIn(user1, amount);
        
        uint256 l2TokenAmount = bridge.l2TokenAmount(amount);
        
        assertEq(bridge.totalSupply(), l2TokenAmount);
        assertEq(bridge.balanceOf(user1), l2TokenAmount);
        assertEq(bridge.getTotalBridgedIn(), l2TokenAmount);
    }
    
    function test_BridgeOut() public {
        // First bridge in some tokens
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, 10);
        
        // Set L1Block values
        mockL1Block.setNumber(123);
        mockL1Block.setHash(bytes32(uint256(1)));
        
        // Now bridge out
        vm.prank(user1);
        bridge.bridgeOut(5);
        
        bytes32 withdrawalId = bridge.getUserWithdrawalId(user1);
        assertEq(bridge.getWithdrawalIdAmount(withdrawalId), 5);
        assertEq(bridge.getWithdrawalIdL1BlockNumber(withdrawalId), 123);
        assertEq(bridge.getWithdrawalIdL1BlockHash(withdrawalId), bytes32(uint256(1)));
    }
    
    function test_MarkWithdrawalComplete() public {
        // Setup: Bridge in and out
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, 10);
        
        mockL1Block.setNumber(123);
        mockL1Block.setHash(bytes32(uint256(1)));
        
        vm.prank(user1);
        uint256 withdrawAmount = 5;
        bridge.bridgeOut(withdrawAmount);
        bytes32 withdrawalId = bridge.getUserWithdrawalId(user1);
        
        console2.logBytes32(withdrawalId);
        
        // Mark withdrawal complete
        vm.prank(trustedSmartContract);
        bridge.markWithdrawalComplete(user1, withdrawalId);
        
        uint256 l2TokenAmount = bridge.l2TokenAmount(withdrawAmount);
        
        // Verify withdrawal was completed
        assertEq(bridge.getUserWithdrawalId(user1), bytes32(0));
        assertEq(bridge.getWithdrawalIdAmount(withdrawalId), 0);
        assertEq(bridge.getWithdrawalIdL1BlockNumber(withdrawalId), 0);
        assertEq(bridge.getWithdrawalIdL1BlockHash(withdrawalId), bytes32(0));
        assertEq(bridge.getTotalWithdrawComplete(), l2TokenAmount);
    }
    
    function testFail_BridgeOutOverLimit() public {
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, 2000);
        
        vm.prank(user1);
        bridge.bridgeOut(1001); // Over bridge limit
    }
    
    function test_AdminResetInvariants() public {
        uint256 l1BridgeInAmount = 100;
        uint256 l2BridgeInAmount = bridge.l2TokenAmount(l1BridgeInAmount);
        uint256 l2InconsistentAmount = 1 ether;

        // Create an inconsistency by directly manipulating storage
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, l1BridgeInAmount);
        
        assertEq(bridge.getTotalBridgedIn(), l2BridgeInAmount);
        
        // Force an inconsistency by directly setting totalBridgedIn
        uint256 slot = uint256(keccak256("EthscriptionERC20BridgeStorage.contract.storage.v1")) + 7; // totalBridgedIn slot
        vm.store(address(bridge), bytes32(slot), bytes32(l2InconsistentAmount)); // Set to small amount
        
        // Verify inconsistency exists
        // (int256 balanceDiff, bool bridgeBalanceValid) = bridge.consistencyCheck();
        int256 balanceDiff = bridge.consistencyCheck();
        assertTrue(balanceDiff != 0, "No inconsistency created");
        assertEq(bridge.getTotalBridgedIn(), l2InconsistentAmount);
        
        vm.expectRevert();
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, 3);
        
        // Fix it
        vm.prank(bridge.owner());
        bridge.adminResetInvariants();
        
        // Verify fixed
        balanceDiff = bridge.consistencyCheck();
        assertEq(balanceDiff, 0, "Balance difference not fixed");
        
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, 3);
        
        vm.store(address(bridge), bytes32(slot + 1), bytes32(uint256(2 ether))); // Set to small amount
        vm.store(address(bridge), bytes32(slot + 2), bytes32(uint256(4 ether))); // Set to small amount
        
        vm.expectRevert();
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, 3);
        
        vm.prank(bridge.owner());
        bridge.adminResetInvariants();
        
        balanceDiff = bridge.consistencyCheck();
        assertEq(balanceDiff, 0, "Balance difference not fixed");
        
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, 3);
    }
    
    function test_CompleteWithdrawalFlow() public {
        // Bridge in
        vm.prank(trustedSmartContract);
        uint256 bridgeAmount = 100;
        bridge.bridgeIn(user1, bridgeAmount);
        uint256 l2Amount = bridge.l2TokenAmount(bridgeAmount);
        
        // Set L1Block values
        mockL1Block.setNumber(123);
        mockL1Block.setHash(bytes32(uint256(1)));
        
        // Bridge out half
        vm.prank(user1);
        uint256 withdrawAmount = bridgeAmount / 2;
        
        // Capture the withdrawal event to get the correct withdrawalId
        vm.recordLogs();
        bridge.bridgeOut(withdrawAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 withdrawalId = entries[1].topics[2];
        
        // Complete withdrawal
        vm.prank(trustedSmartContract);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalComplete(user1, withdrawAmount, withdrawalId);
        bridge.markWithdrawalComplete(user1, withdrawalId);
        
        // Verify final state
        assertEq(bridge.balanceOf(user1), l2Amount / 2, "Incorrect final balance");
        assertEq(bridge.getTotalBridgedIn(), l2Amount, "Incorrect total bridged in");
        assertEq(bridge.getTotalWithdrawComplete(), l2Amount / 2, "Incorrect total withdrawn");
        assertEq(bridge.getPendingWithdrawalAmount(), 0, "Should have no pending withdrawals");
    }
    
    function test_Pause() public {
        vm.prank(bridge.owner());
        bridge.pause();
        
        vm.prank(trustedSmartContract);
        bridge.bridgeIn(user1, 100);
        
        vm.expectRevert();
        vm.prank(user1);
        bridge.bridgeOut(50);
        
        vm.prank(bridge.owner());
        bridge.unpause();
        
        vm.prank(user1);
        bridge.bridgeOut(50); // Should work now
    }
}
