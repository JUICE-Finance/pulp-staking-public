// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SageStaking, StakingPositionStatus} from "../src/SageStaking.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        // Mint 1 million tokens to deployer
        _mint(msg.sender, 1_000_000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StakingTest is Test {
    SageStaking public staking;
    MockToken public token;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public owner = address(this);
    
    uint256 public constant COOLDOWN_PERIOD = 2 weeks;
    uint256 public constant INITIAL_BALANCE = 1000 * 10**18; // 1000 tokens
    
    function setUp() public {
        // Deploy mock token
        token = new MockToken();
        
        // Deploy staking contract
        staking = new SageStaking(COOLDOWN_PERIOD, address(token));
        
        // Mint tokens to test users
        token.mint(user1, INITIAL_BALANCE);
        token.mint(user2, INITIAL_BALANCE);
        
        // Approve staking contract to spend user tokens
        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);
        
        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
    }
    
    function test_InitialState() public view {
        assertEq(staking.cooldownPeriod(), COOLDOWN_PERIOD);
        assertEq(address(staking.token()), address(token));
        assertEq(staking.globalNonce(), 0);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE);
        assertEq(token.balanceOf(user2), INITIAL_BALANCE);
    }
    
    function test_Deposit() public {
        uint256 depositAmount = 100 * 10**18; // 100 tokens
        
        // Get nonce before deposit
        uint256 nonceBefore = staking.globalNonce();
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        // Check staking position was created
        (uint256 amount, uint256 nonce, uint256 depositTimestamp, StakingPositionStatus status, uint256 unlocksAt) = staking.stakingPositions(user1, nonceBefore);
        assertEq(amount, depositAmount);
        assertEq(nonce, nonceBefore);
        assertEq(depositTimestamp, block.timestamp);
        assertTrue(status == StakingPositionStatus.Active);
        assertEq(unlocksAt, 0);
        
        // Check token balances
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount);
        assertEq(token.balanceOf(address(staking)), depositAmount);
        
        // Check nonce was incremented
        assertEq(staking.globalNonce(), nonceBefore + 1);
    }
    
    function test_DepositMultiple() public {
        uint256 firstDeposit = 50 * 10**18;
        uint256 secondDeposit = 75 * 10**18;
        
        vm.startPrank(user1);
        staking.deposit(firstDeposit);
        uint256 firstNonce = staking.globalNonce() - 1;
        
        staking.deposit(secondDeposit);
        uint256 secondNonce = staking.globalNonce() - 1;
        vm.stopPrank();
        
        // Check both positions were created correctly
        (uint256 amount1,, , StakingPositionStatus status1,) = staking.stakingPositions(user1, firstNonce);
        assertEq(amount1, firstDeposit);
        assertTrue(status1 == StakingPositionStatus.Active);
        
        (uint256 amount2,, , StakingPositionStatus status2,) = staking.stakingPositions(user1, secondNonce);
        assertEq(amount2, secondDeposit);
        assertTrue(status2 == StakingPositionStatus.Active);
        
        assertEq(token.balanceOf(address(staking)), firstDeposit + secondDeposit);
    }
    
    function test_DepositZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be greater than 0");
        staking.deposit(0);
    }
    
    function test_InitiateWithdraw() public {
        uint256 depositAmount = 100 * 10**18;
        
        // First deposit
        vm.prank(user1);
        staking.deposit(depositAmount);
        uint256 depositNonce = staking.globalNonce() - 1;
        
        // Initiate withdraw on the deposited position
        vm.prank(user1);
        staking.initiateWithdraw(depositNonce);
        
        // Check position was updated to WithdrawalInitiated
        (uint256 amount, uint256 nonce, , StakingPositionStatus status, uint256 unlocksAt) = staking.stakingPositions(user1, depositNonce);
        assertEq(amount, depositAmount);
        assertTrue(status == StakingPositionStatus.WithdrawalInitiated);
        assertEq(unlocksAt, block.timestamp + COOLDOWN_PERIOD);
        assertEq(nonce, depositNonce);
    }
    
    function test_InitiateWithdrawInvalidPosition() public {
        // Try to initiate withdrawal on non-existent position
        vm.prank(user1);
        vm.expectRevert("Staking position does not exist");
        staking.initiateWithdraw(999);
    }
    
    function test_InitiateMultipleWithdrawals() public {
        uint256 firstDeposit = 50 * 10**18;
        uint256 secondDeposit = 30 * 10**18;
        
        // Make two deposits
        vm.startPrank(user1);
        staking.deposit(firstDeposit);
        uint256 firstNonce = staking.globalNonce() - 1;
        
        staking.deposit(secondDeposit);
        uint256 secondNonce = staking.globalNonce() - 1;
        
        // Initiate withdrawal on both positions
        staking.initiateWithdraw(firstNonce);
        staking.initiateWithdraw(secondNonce);
        vm.stopPrank();
        
        // Check both positions have withdrawal initiated
        (uint256 amount1,, , StakingPositionStatus status1,) = staking.stakingPositions(user1, firstNonce);
        assertTrue(status1 == StakingPositionStatus.WithdrawalInitiated);
        assertEq(amount1, firstDeposit);
        
        (uint256 amount2,, , StakingPositionStatus status2,) = staking.stakingPositions(user1, secondNonce);
        assertTrue(status2 == StakingPositionStatus.WithdrawalInitiated);
        assertEq(amount2, secondDeposit);
    }
    
    function test_WithdrawAfterCooldown() public {
        uint256 depositAmount = 100 * 10**18;
        
        // Deposit and initiate withdraw
        vm.prank(user1);
        staking.deposit(depositAmount);
        uint256 depositNonce = staking.globalNonce() - 1;
        
        vm.prank(user1);
        staking.initiateWithdraw(depositNonce);
        
        // Fast forward time past cooldown period
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // Record balances before withdraw
        uint256 userBalanceBefore = token.balanceOf(user1);
        uint256 contractBalanceBefore = token.balanceOf(address(staking));
        
        // Execute withdraw
        vm.prank(user1);
        staking.withdraw(depositNonce);
        
        // Check balances after withdraw
        assertEq(token.balanceOf(user1), userBalanceBefore + depositAmount);
        assertEq(token.balanceOf(address(staking)), contractBalanceBefore - depositAmount);
        
        // Check position is marked as WithdrawalCompleted
        (uint256 amount,, , StakingPositionStatus status,) = staking.stakingPositions(user1, depositNonce);
        assertTrue(status == StakingPositionStatus.WithdrawalCompleted);
        assertEq(amount, depositAmount);
    }
    
    function test_CannotWithdrawBeforeCooldown() public {
        uint256 depositAmount = 100 * 10**18;
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        uint256 depositNonce = staking.globalNonce() - 1;
        
        vm.prank(user1);
        staking.initiateWithdraw(depositNonce);
        
        // Try to withdraw before cooldown (should fail)
        vm.prank(user1);
        vm.expectRevert("Withdrawal not yet unlocked");
        staking.withdraw(depositNonce);
        
        // Fast forward but not enough
        vm.warp(block.timestamp + COOLDOWN_PERIOD - 1);
        
        vm.prank(user1);
        vm.expectRevert("Withdrawal not yet unlocked");
        staking.withdraw(depositNonce);
    }
    
    function test_CannotWithdrawTwice() public {
        uint256 depositAmount = 100 * 10**18;
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        uint256 depositNonce = staking.globalNonce() - 1;
        
        vm.prank(user1);
        staking.initiateWithdraw(depositNonce);
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // First withdrawal should succeed
        vm.prank(user1);
        staking.withdraw(depositNonce);
        
        // Second withdrawal should fail (status is now WithdrawalCompleted)
        vm.prank(user1);
        vm.expectRevert("Withdrawal not initiated for this position");
        staking.withdraw(depositNonce);
    }
    
    function test_CannotWithdrawNonExistentNonce() public {
        vm.prank(user1);
        vm.expectRevert("Withdrawal not initiated for this position");
        staking.withdraw(999);
    }
    
    function test_MultipleWithdrawalsWithDifferentTimings() public {
        uint256 deposit1 = 100 * 10**18;
        uint256 deposit2 = 50 * 10**18;
        uint256 deposit3 = 75 * 10**18;
        
        // Make three deposits
        vm.startPrank(user1);
        staking.deposit(deposit1);
        uint256 nonce1 = staking.globalNonce() - 1;
        
        staking.deposit(deposit2);
        uint256 nonce2 = staking.globalNonce() - 1;
        
        staking.deposit(deposit3);
        uint256 nonce3 = staking.globalNonce() - 1;
        
        // Initiate withdrawals at different times
        staking.initiateWithdraw(nonce1);
        
        vm.warp(block.timestamp + 1 days);
        staking.initiateWithdraw(nonce2);
        
        vm.warp(block.timestamp + 1 days);
        staking.initiateWithdraw(nonce3);
        vm.stopPrank();
        
        // Fast forward so first two are ready but third is not
        vm.warp(block.timestamp + COOLDOWN_PERIOD - 1 days);
        
        // First two should be withdrawable
        vm.prank(user1);
        staking.withdraw(nonce1);
        
        vm.prank(user1);
        staking.withdraw(nonce2);
        
        // Third should not be withdrawable yet
        vm.prank(user1);
        vm.expectRevert("Withdrawal not yet unlocked");
        staking.withdraw(nonce3);
        
        // Fast forward and withdraw third
        vm.warp(block.timestamp + 2 days);
        vm.prank(user1);
        staking.withdraw(nonce3);
        
        // Check all positions are withdrawn
        (,, , StakingPositionStatus status1,) = staking.stakingPositions(user1, nonce1);
        assertTrue(status1 == StakingPositionStatus.WithdrawalCompleted);
        
        (,, , StakingPositionStatus status2,) = staking.stakingPositions(user1, nonce2);
        assertTrue(status2 == StakingPositionStatus.WithdrawalCompleted);
        
        (,, , StakingPositionStatus status3,) = staking.stakingPositions(user1, nonce3);
        assertTrue(status3 == StakingPositionStatus.WithdrawalCompleted);
        
        assertEq(token.balanceOf(user1), INITIAL_BALANCE);
    }
    
    function test_AdminChangeCooldownPeriod() public {
        uint256 newCooldown = 1 weeks;
        
        staking.adminChangeCooldownPeriod(newCooldown);
        assertEq(staking.cooldownPeriod(), newCooldown);
    }
    
    function test_OnlyOwnerCanChangeCooldown() public {
        uint256 newCooldown = 1 weeks;
        
        vm.prank(user1);
        vm.expectRevert();
        staking.adminChangeCooldownPeriod(newCooldown);
    }
    
    function test_CannotSetZeroCooldown() public {
        vm.expectRevert("Cooldown period must be greater than 0");
        staking.adminChangeCooldownPeriod(0);
    }
    
    function test_MultipleUsersCanStake() public {
        uint256 amount1 = 100 * 10**18;
        uint256 amount2 = 200 * 10**18;
        
        vm.prank(user1);
        staking.deposit(amount1);
        uint256 nonce1 = staking.globalNonce() - 1;
        
        vm.prank(user2);
        staking.deposit(amount2);
        uint256 nonce2 = staking.globalNonce() - 1;
        
        // Check each user's position
        (uint256 posAmount1,, , StakingPositionStatus status1,) = staking.stakingPositions(user1, nonce1);
        assertEq(posAmount1, amount1);
        assertTrue(status1 == StakingPositionStatus.Active);
        
        (uint256 posAmount2,, , StakingPositionStatus status2,) = staking.stakingPositions(user2, nonce2);
        assertEq(posAmount2, amount2);
        assertTrue(status2 == StakingPositionStatus.Active);
        
        assertEq(token.balanceOf(address(staking)), amount1 + amount2);
    }
    
    function test_UsersHaveSeparateWithdrawals() public {
        uint256 depositAmount = 100 * 10**18;
        
        // Both users deposit
        vm.prank(user1);
        staking.deposit(depositAmount);
        uint256 nonce1 = staking.globalNonce() - 1;
        
        vm.prank(user2);
        staking.deposit(depositAmount);
        uint256 nonce2 = staking.globalNonce() - 1;
        
        // Both initiate withdrawals
        vm.prank(user1);
        staking.initiateWithdraw(nonce1);
        
        vm.prank(user2);
        staking.initiateWithdraw(nonce2);
        
        // Nonces should be different
        assertFalse(nonce1 == nonce2);
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // User1 withdraws their funds
        vm.prank(user1);
        staking.withdraw(nonce1);
        
        // User2 cannot withdraw user1's funds
        vm.prank(user2);
        vm.expectRevert("Withdrawal not initiated for this position");
        staking.withdraw(nonce1);
        
        // User2 can withdraw their own funds
        vm.prank(user2);
        staking.withdraw(nonce2);
        
        // Check both users got their funds back
        assertEq(token.balanceOf(user1), INITIAL_BALANCE);
        assertEq(token.balanceOf(user2), INITIAL_BALANCE);
    }
    
    function testFuzz_DepositAndWithdraw(uint256 amount) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1 * 10**18, INITIAL_BALANCE);
        
        vm.prank(user1);
        staking.deposit(amount);
        uint256 depositNonce = staking.globalNonce() - 1;
        
        vm.prank(user1);
        staking.initiateWithdraw(depositNonce);
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        uint256 balanceBefore = token.balanceOf(user1);
        
        vm.prank(user1);
        staking.withdraw(depositNonce);
        
        assertEq(token.balanceOf(user1), balanceBefore + amount);
        
        // Check position is withdrawn
        (,, , StakingPositionStatus status,) = staking.stakingPositions(user1, depositNonce);
        assertTrue(status == StakingPositionStatus.WithdrawalCompleted);
    }
    
    function testFuzz_MultiplePositions(uint256 deposit1, uint256 deposit2) public {
        // Ensure reasonable bounds
        deposit1 = bound(deposit1, 1 * 10**18, INITIAL_BALANCE / 2);
        deposit2 = bound(deposit2, 1 * 10**18, INITIAL_BALANCE / 2);
        
        // Create two deposits
        vm.startPrank(user1);
        staking.deposit(deposit1);
        uint256 nonce1 = staking.globalNonce() - 1;
        
        staking.deposit(deposit2);
        uint256 nonce2 = staking.globalNonce() - 1;
        
        // Initiate withdrawals
        staking.initiateWithdraw(nonce1);
        staking.initiateWithdraw(nonce2);
        vm.stopPrank();
        
        // Fast forward and withdraw both
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        vm.prank(user1);
        staking.withdraw(nonce1);
        
        vm.prank(user1);
        staking.withdraw(nonce2);
        
        // Verify both positions are withdrawn
        (,, , StakingPositionStatus status1,) = staking.stakingPositions(user1, nonce1);
        assertTrue(status1 == StakingPositionStatus.WithdrawalCompleted);
        
        (,, , StakingPositionStatus status2,) = staking.stakingPositions(user1, nonce2);
        assertTrue(status2 == StakingPositionStatus.WithdrawalCompleted);
        
        assertEq(token.balanceOf(user1), INITIAL_BALANCE);
    }
    
    function test_UserRestakeFromWithdrawalInitiated() public {
        uint256 depositAmount = 100 * 10**18;
        
        // Deposit and initiate withdrawal
        vm.prank(user1);
        staking.deposit(depositAmount);
        uint256 depositNonce = staking.globalNonce() - 1;
        
        vm.prank(user1);
        staking.initiateWithdraw(depositNonce);
        
        // Check position is in WithdrawalInitiated state
        (,, , StakingPositionStatus statusBefore, uint256 unlocksAtBefore) = staking.stakingPositions(user1, depositNonce);
        assertTrue(statusBefore == StakingPositionStatus.WithdrawalInitiated);
        assertTrue(unlocksAtBefore > 0);
        
        // Record timestamp before restaking
        uint256 timestampBefore = block.timestamp;
        vm.warp(block.timestamp + 1 days);
        
        // Restake the position
        vm.prank(user1);
        staking.userRestakeFromWithdrawalInitiated(depositNonce);
        
        // Check position is back to Active state
        (uint256 amountAfter, uint256 nonceAfter, uint256 depositTimestampAfter, StakingPositionStatus statusAfter, uint256 unlocksAtAfter) = staking.stakingPositions(user1, depositNonce);
        assertTrue(statusAfter == StakingPositionStatus.Active);
        assertEq(unlocksAtAfter, 0);
        assertEq(amountAfter, depositAmount);
        assertEq(nonceAfter, depositNonce); // Nonce should remain the same
        assertGt(depositTimestampAfter, timestampBefore); // Deposit timestamp should be updated
    }
    
    function test_CannotRestakeNonWithdrawalInitiated() public {
        uint256 depositAmount = 100 * 10**18;
        
        // Deposit (position will be Active)
        vm.prank(user1);
        staking.deposit(depositAmount);
        uint256 depositNonce = staking.globalNonce() - 1;
        
        // Try to restake an Active position (should fail)
        vm.prank(user1);
        vm.expectRevert("Withdrawal not initiated for this position");
        staking.userRestakeFromWithdrawalInitiated(depositNonce);
    }
}