// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Staking} from "../src/SageStaking.sol";

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
    Staking public staking;
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
        staking = new Staking(COOLDOWN_PERIOD, address(token));
        
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
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        // Check user's balance info
        (uint256 idleDeposits, uint256 pendingWithdrawals) = staking.balanceInfo(user1);
        assertEq(idleDeposits, depositAmount);
        assertEq(pendingWithdrawals, 0);
        
        // Check token balances
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount);
        assertEq(token.balanceOf(address(staking)), depositAmount);
    }
    
    function test_DepositMultiple() public {
        uint256 firstDeposit = 50 * 10**18;
        uint256 secondDeposit = 75 * 10**18;
        
        vm.startPrank(user1);
        staking.deposit(firstDeposit);
        staking.deposit(secondDeposit);
        vm.stopPrank();
        
        (uint256 idleDeposits,) = staking.balanceInfo(user1);
        assertEq(idleDeposits, firstDeposit + secondDeposit);
        assertEq(token.balanceOf(address(staking)), firstDeposit + secondDeposit);
    }
    
    function test_DepositZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be greater than 0");
        staking.deposit(0);
    }
    
    function test_InitiateWithdraw() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 withdrawAmount = 60 * 10**18;
        
        // First deposit
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        // Get nonce before withdrawal
        uint256 nonceBefore = staking.globalNonce();
        
        // Initiate withdraw
        vm.prank(user1);
        staking.initiateWithdraw(withdrawAmount);
        
        // Check balance info
        (uint256 idleDeposits, uint256 pendingWithdrawals) = staking.balanceInfo(user1);
        assertEq(idleDeposits, depositAmount - withdrawAmount);
        assertEq(pendingWithdrawals, withdrawAmount);
        
        // Check withdrawal info
        (uint256 amount, uint256 unlocksAt, uint256 nonce, bool withdrawn) = staking.withdrawalInfo(user1, nonceBefore);
        assertEq(amount, withdrawAmount);
        assertEq(unlocksAt, block.timestamp + COOLDOWN_PERIOD);
        assertEq(nonce, nonceBefore);
        assertEq(withdrawn, false);
        
        // Check nonce was incremented
        assertEq(staking.globalNonce(), nonceBefore + 1);
    }
    
    function test_InitiateWithdrawInsufficientBalance() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 withdrawAmount = 150 * 10**18;
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        vm.prank(user1);
        vm.expectRevert("Insufficient idle deposit balance");
        staking.initiateWithdraw(withdrawAmount);
    }
    
    function test_InitiateMultipleWithdrawals() public {
        uint256 depositAmount = 200 * 10**18;
        uint256 firstWithdraw = 50 * 10**18;
        uint256 secondWithdraw = 30 * 10**18;
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        // Initiate first withdrawal
        vm.prank(user1);
        staking.initiateWithdraw(firstWithdraw);
        uint256 firstNonce = staking.globalNonce() - 1;
        
        // Initiate second withdrawal
        vm.prank(user1);
        staking.initiateWithdraw(secondWithdraw);
        uint256 secondNonce = staking.globalNonce() - 1;
        
        // Check balance info
        (uint256 idleDeposits, uint256 pendingWithdrawals) = staking.balanceInfo(user1);
        assertEq(idleDeposits, depositAmount - firstWithdraw - secondWithdraw);
        assertEq(pendingWithdrawals, firstWithdraw + secondWithdraw);
        
        // Check both withdrawals are tracked separately
        (uint256 amount1,,,) = staking.withdrawalInfo(user1, firstNonce);
        (uint256 amount2,,,) = staking.withdrawalInfo(user1, secondNonce);
        assertEq(amount1, firstWithdraw);
        assertEq(amount2, secondWithdraw);
    }
    
    function test_WithdrawAfterCooldown() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 withdrawAmount = 60 * 10**18;
        
        // Deposit and initiate withdraw
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        vm.prank(user1);
        staking.initiateWithdraw(withdrawAmount);
        uint256 withdrawNonce = staking.globalNonce() - 1;
        
        // Fast forward time past cooldown period
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // Record balances before withdraw
        uint256 userBalanceBefore = token.balanceOf(user1);
        uint256 contractBalanceBefore = token.balanceOf(address(staking));
        
        // Execute withdraw
        vm.prank(user1);
        staking.withdraw(withdrawNonce);
        
        // Check balances after withdraw
        assertEq(token.balanceOf(user1), userBalanceBefore + withdrawAmount);
        assertEq(token.balanceOf(address(staking)), contractBalanceBefore - withdrawAmount);
        
        // Check balance info is updated
        (uint256 idleDeposits, uint256 pendingWithdrawals) = staking.balanceInfo(user1);
        assertEq(idleDeposits, depositAmount - withdrawAmount);
        assertEq(pendingWithdrawals, 0);
        
        // Check withdrawal is marked as withdrawn
        (,, , bool withdrawn) = staking.withdrawalInfo(user1, withdrawNonce);
        assertEq(withdrawn, true);
    }
    
    function test_CannotWithdrawBeforeCooldown() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 withdrawAmount = 60 * 10**18;
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        vm.prank(user1);
        staking.initiateWithdraw(withdrawAmount);
        uint256 withdrawNonce = staking.globalNonce() - 1;
        
        // Try to withdraw before cooldown (should fail)
        vm.prank(user1);
        vm.expectRevert("Withdrawal not yet unlocked");
        staking.withdraw(withdrawNonce);
        
        // Fast forward but not enough
        vm.warp(block.timestamp + COOLDOWN_PERIOD - 1);
        
        vm.prank(user1);
        vm.expectRevert("Withdrawal not yet unlocked");
        staking.withdraw(withdrawNonce);
    }
    
    function test_CannotWithdrawTwice() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 withdrawAmount = 60 * 10**18;
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        vm.prank(user1);
        staking.initiateWithdraw(withdrawAmount);
        uint256 withdrawNonce = staking.globalNonce() - 1;
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // First withdrawal should succeed
        vm.prank(user1);
        staking.withdraw(withdrawNonce);
        
        // Second withdrawal should fail
        vm.prank(user1);
        vm.expectRevert("Withdrawal already processed");
        staking.withdraw(withdrawNonce);
    }
    
    function test_CannotWithdrawNonExistentNonce() public {
        vm.prank(user1);
        vm.expectRevert("Withdrawal does not exist");
        staking.withdraw(999);
    }
    
    function test_MultipleWithdrawalsWithDifferentTimings() public {
        uint256 depositAmount = 300 * 10**18;
        uint256 withdraw1 = 100 * 10**18;
        uint256 withdraw2 = 50 * 10**18;
        uint256 withdraw3 = 75 * 10**18;
        
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        // Initiate withdrawals at different times
        vm.prank(user1);
        staking.initiateWithdraw(withdraw1);
        uint256 nonce1 = staking.globalNonce() - 1;
        
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        staking.initiateWithdraw(withdraw2);
        uint256 nonce2 = staking.globalNonce() - 1;
        
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        staking.initiateWithdraw(withdraw3);
        uint256 nonce3 = staking.globalNonce() - 1;
        
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
        
        // Check final balances
        (uint256 idleDeposits, uint256 pendingWithdrawals) = staking.balanceInfo(user1);
        assertEq(idleDeposits, depositAmount - withdraw1 - withdraw2 - withdraw3);
        assertEq(pendingWithdrawals, 0);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - idleDeposits);
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
        
        vm.prank(user2);
        staking.deposit(amount2);
        
        (uint256 idleDeposits1,) = staking.balanceInfo(user1);
        (uint256 idleDeposits2,) = staking.balanceInfo(user2);
        
        assertEq(idleDeposits1, amount1);
        assertEq(idleDeposits2, amount2);
        assertEq(token.balanceOf(address(staking)), amount1 + amount2);
    }
    
    function test_UsersHaveSeparateWithdrawals() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 withdrawAmount = 50 * 10**18;
        
        // Both users deposit
        vm.prank(user1);
        staking.deposit(depositAmount);
        
        vm.prank(user2);
        staking.deposit(depositAmount);
        
        // Both initiate withdrawals
        vm.prank(user1);
        staking.initiateWithdraw(withdrawAmount);
        uint256 nonce1 = staking.globalNonce() - 1;
        
        vm.prank(user2);
        staking.initiateWithdraw(withdrawAmount);
        uint256 nonce2 = staking.globalNonce() - 1;
        
        // Nonces should be different
        assertFalse(nonce1 == nonce2);
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // User1 withdraws their funds
        vm.prank(user1);
        staking.withdraw(nonce1);
        
        // User2 cannot withdraw user1's funds
        vm.prank(user2);
        vm.expectRevert("Withdrawal does not exist");
        staking.withdraw(nonce1);
        
        // User2 can withdraw their own funds
        vm.prank(user2);
        staking.withdraw(nonce2);
        
        // Check both users got their funds back
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount + withdrawAmount);
        assertEq(token.balanceOf(user2), INITIAL_BALANCE - depositAmount + withdrawAmount);
    }
    
    function testFuzz_DepositAndWithdraw(uint256 amount) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1 * 10**18, INITIAL_BALANCE);
        
        vm.prank(user1);
        staking.deposit(amount);
        
        vm.prank(user1);
        staking.initiateWithdraw(amount);
        uint256 withdrawNonce = staking.globalNonce() - 1;
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        uint256 balanceBefore = token.balanceOf(user1);
        
        vm.prank(user1);
        staking.withdraw(withdrawNonce);
        
        assertEq(token.balanceOf(user1), balanceBefore + amount);
        
        // Check all pending withdrawals were processed
        (, uint256 pendingWithdrawals) = staking.balanceInfo(user1);
        assertEq(pendingWithdrawals, 0);
    }
    
    function testFuzz_MultipleWithdrawals(uint256 deposit, uint256 withdraw1, uint256 withdraw2) public {
        // Ensure reasonable bounds
        deposit = bound(deposit, 10 * 10**18, INITIAL_BALANCE);
        withdraw1 = bound(withdraw1, 1 * 10**18, deposit / 3);
        withdraw2 = bound(withdraw2, 1 * 10**18, deposit / 3);
        
        vm.prank(user1);
        staking.deposit(deposit);
        
        // Initiate two withdrawals
        vm.prank(user1);
        staking.initiateWithdraw(withdraw1);
        uint256 nonce1 = staking.globalNonce() - 1;
        
        vm.prank(user1);
        staking.initiateWithdraw(withdraw2);
        uint256 nonce2 = staking.globalNonce() - 1;
        
        // Fast forward and withdraw both
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        vm.prank(user1);
        staking.withdraw(nonce1);
        
        vm.prank(user1);
        staking.withdraw(nonce2);
        
        // Verify final state
        (uint256 idleDeposits, uint256 pendingWithdrawals) = staking.balanceInfo(user1);
        assertEq(idleDeposits, deposit - withdraw1 - withdraw2);
        assertEq(pendingWithdrawals, 0);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - idleDeposits);
    }
}