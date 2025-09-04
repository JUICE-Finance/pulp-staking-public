// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";



enum StakingPositionStatus {
    Active,
    WithdrawalInitiated,
    WithdrawalCompleted
}

struct StakingPosition {
    uint256 amount;
    uint256 nonce;
    uint256 depositTimestamp;
    StakingPositionStatus status;
    uint256 unlocksAt;
}

event Deposit(address indexed user, uint256 amount, uint256 nonce, uint256 timestamp);
event InitiateWithdraw(address indexed user, uint256 nonce, uint256 unlocksAt, uint256 timestamp);
event Withdraw(address indexed user, uint256 amount, uint256 nonce, uint256 timestamp);
event RestakeFromWithdrawalInitiated(address indexed user, uint256 nonce, uint256 amount, uint256 timestamp);


contract SageStaking is ReentrancyGuard, Ownable {

    mapping(address => mapping(uint256 => StakingPosition)) public stakingPositions;

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
        
        // Create a new staking position with the current global nonce
        stakingPositions[msg.sender][globalNonce] = StakingPosition({
            amount: amount,
            nonce: globalNonce,
            depositTimestamp: block.timestamp,
            status: StakingPositionStatus.Active,
            unlocksAt: 0 // Not applicable for deposits, only used when withdrawal is initiated
        });
        
        // Store current nonce for event 
        uint256 currentNonce = globalNonce;
        
        // Increment global nonce for next position
        globalNonce++;

        emit Deposit(msg.sender, amount, currentNonce, block.timestamp);
    }

    
    function initiateWithdraw(uint256 nonce) external {
        // Get the staking position for the given nonce
        StakingPosition storage position = stakingPositions[msg.sender][nonce];
        
        // Ensure the position exists (amount would be 0 for non-existent positions)
        require(position.amount > 0, "Staking position does not exist");
        
        // Ensure the position is currently Active
        require(position.status == StakingPositionStatus.Active, "Position must be active to initiate withdrawal");
        
        // Update the position status to WithdrawalInitiated
        position.status = StakingPositionStatus.WithdrawalInitiated;
        
        // Set the unlock time
        position.unlocksAt = block.timestamp + cooldownPeriod;
        
        // Emit the InitiateWithdraw event
        emit InitiateWithdraw(msg.sender, nonce, position.unlocksAt, block.timestamp);
    }

    function withdraw(uint256 nonce) nonReentrant() external {
        // Get the staking position for the given nonce
        StakingPosition storage position = stakingPositions[msg.sender][nonce];
        
        // Ensure the position has withdrawal initiated
        require(position.status == StakingPositionStatus.WithdrawalInitiated, "Withdrawal not initiated for this position");
        
        // Ensure the unlock time has passed
        require(position.unlocksAt <= block.timestamp, "Withdrawal not yet unlocked");
        
        // Update the position status to WithdrawalCompleted
        position.status = StakingPositionStatus.WithdrawalCompleted;
        
        // Store amount for transfer
        uint256 transferAmount = position.amount;
        
        // Transfer tokens back to user
        require(token.transfer(msg.sender, transferAmount), "Transfer failed");
        
        // Emit the Withdraw event
        emit Withdraw(msg.sender, transferAmount, nonce, block.timestamp);
    }

    function userRestakeFromWithdrawalInitiated(uint256 nonce) external {
        StakingPosition storage position = stakingPositions[msg.sender][nonce];
        require(position.status == StakingPositionStatus.WithdrawalInitiated, "Withdrawal not initiated for this position");
        
        // Reset status back to Active
        position.status = StakingPositionStatus.Active;
        
        // Clear the unlock time
        position.unlocksAt = 0;
        
        // Update deposit timestamp to current time
        position.depositTimestamp = block.timestamp;
        
        // Emit the RestakeFromWithdrawalInitiated event
        emit RestakeFromWithdrawalInitiated(msg.sender, nonce, position.amount, block.timestamp);
    }

    function adminChangeCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        require(_cooldownPeriod > 0, "Cooldown period must be greater than 0");
        cooldownPeriod = _cooldownPeriod;
    }
    
}
