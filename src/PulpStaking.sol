// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


struct WithdrawalInfo {
    uint256 amount;
    uint256 unlocksAt;
    uint256 nonce;
    bool withdrawn;
}


struct BalanceInfo {
    uint256 idleDepositAmount;
    uint256 pendingWithdrawalAmount;
}

event Deposit(address indexed user, uint256 amount, uint256 timestamp);
event InitiateWithdraw(address indexed user, uint256 nonce, uint256 unlocksAt, uint256 timestamp);
event Withdraw(address indexed user, uint256 amount, uint256 nonce, uint256 timestamp);


contract Staking is ReentrancyGuard, Ownable {

    mapping(address => mapping(uint256 => WithdrawalInfo)) public withdrawalInfo;
    mapping(address => BalanceInfo) public balanceInfo;

    uint256 public cooldownPeriod;
    IERC20 public token;
    uint256 public globalNonce;
    
    constructor(uint256 _cooldownPeriod, address _tokenAddress) Ownable(msg.sender) {
        cooldownPeriod = _cooldownPeriod;
        token = IERC20(_tokenAddress);
        globalNonce = 0;
    }


    function deposit(uint256 amount) nonReentrant() external {
        require(amount > 0, "Amount must be greater than 0");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Add deposit amount to user's idle deposit balance
        balanceInfo[msg.sender].idleDepositAmount += amount;

        emit Deposit(msg.sender, amount, block.timestamp);
    }

    
    function initiateWithdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        
        // Ensure user has enough idle deposits to withdraw
        require(balanceInfo[msg.sender].idleDepositAmount >= amount, "Insufficient idle deposit balance");
        
        // Move amount from idle deposits to pending withdrawals
        balanceInfo[msg.sender].idleDepositAmount -= amount;
        balanceInfo[msg.sender].pendingWithdrawalAmount += amount;
        
        // Store withdrawal information in withdrawalInfo mapping
        withdrawalInfo[msg.sender][globalNonce] = WithdrawalInfo({
            amount: amount,
            unlocksAt: block.timestamp + cooldownPeriod,
            nonce: globalNonce,
            withdrawn: false
        });
        
        // Store current nonce for event
        uint256 currentNonce = globalNonce;
        
        // Increment global nonce for next withdrawal
        globalNonce++;
        
        // Emit the InitiateWithdraw event
        emit InitiateWithdraw(msg.sender, currentNonce, block.timestamp + cooldownPeriod, block.timestamp);
    }

    function withdraw(uint256 nonce) nonReentrant() external {
        // Get the withdrawal info for the given nonce
        WithdrawalInfo storage withdrawal = withdrawalInfo[msg.sender][nonce];
        
        // Ensure withdrawal exists (amount would be 0 for non-existent withdrawals)
        require(withdrawal.amount > 0, "Withdrawal does not exist");
        
        // Check that this withdrawal hasn't already been processed
        require(!withdrawal.withdrawn, "Withdrawal already processed");
        
        // Ensure the unlock time has passed
        require(withdrawal.unlocksAt <= block.timestamp, "Withdrawal not yet unlocked");
        
        // Subtract amount from pending withdrawals
        balanceInfo[msg.sender].pendingWithdrawalAmount -= withdrawal.amount;
        
        // Mark withdrawal as completed
        withdrawal.withdrawn = true;
        
        // Store amount for transfer
        uint256 transferAmount = withdrawal.amount;
        
        // Transfer tokens back to user
        require(token.transfer(msg.sender, transferAmount), "Transfer failed");
        
        // Emit the Withdraw event
        emit Withdraw(msg.sender, transferAmount, nonce, block.timestamp);
    }

    function adminChangeCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        require(_cooldownPeriod > 0, "Cooldown period must be greater than 0");
        cooldownPeriod = _cooldownPeriod;
    }
    
}
