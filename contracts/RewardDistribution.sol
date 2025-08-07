// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RewardDistribution
 * @dev Manages token rewards for platform contributions
 * @notice This contract handles reward distribution for various platform activities
 */
contract RewardDistribution is Ownable, ReentrancyGuard {
    // Structs
    struct RewardPool {
        uint256 totalPool;
        uint256 distributedAmount;
        uint256 remainingAmount;
        bool isActive;
        uint256 createdAt;
        uint256 expiresAt;
    }
    
    struct UserRewards {
        address user;
        uint256 totalEarned;
        uint256 totalClaimed;
        uint256 pendingRewards;
        uint256 lastClaimTimestamp;
        uint256 verificationRewards;
        uint256 contributionRewards;
        uint256 bonusRewards;
    }
    
    struct RewardTransaction {
        uint256 transactionId;
        address user;
        uint256 amount;
        string rewardType;
        uint256 timestamp;
        bool isClaimed;
        uint256 multiplier;
    }
    
    // State variables
    IERC20 public rewardToken;
    mapping(address => UserRewards) public userRewards;
    mapping(address => RewardTransaction[]) public userTransactions;
    mapping(string => RewardPool) public rewardPools;
    mapping(address => bool) public authorizedContracts;
    
    uint256 private _transactionIdCounter = 0;
    
    // Reward amounts (in token units)
    uint256 public constant VERIFICATION_REWARD = 10 * 10**18; // 10 tokens
    uint256 public constant CREDENTIAL_ISSUE_REWARD = 5 * 10**18; // 5 tokens
    uint256 public constant CREDENTIAL_RECEIVE_REWARD = 2 * 10**18; // 2 tokens
    uint256 public constant DAILY_ACTIVITY_BONUS = 1 * 10**18; // 1 token
    uint256 public constant WEEKLY_BONUS = 10 * 10**18; // 10 tokens
    uint256 public constant MONTHLY_BONUS = 50 * 10**18; // 50 tokens
    
    // Timing constants
    uint256 public constant CLAIM_COOLDOWN = 24 hours;
    uint256 public constant BONUS_CLAIM_WINDOW = 7 days;
    
    // Contract references
    address public credentialRegistry;
    address public reputationSystem;
    address public governanceContract;
    
    // Events
    event RewardEarned(
        address indexed user,
        uint256 amount,
        string rewardType,
        uint256 multiplier
    );
    
    event RewardClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    
    event RewardPoolCreated(
        string indexed poolName,
        uint256 amount,
        uint256 expiresAt
    );
    
    event BonusDistributed(
        address indexed user,
        uint256 amount,
        string bonusType
    );
    
    // Modifiers
    modifier onlyAuthorizedContract() {
        require(authorizedContracts[msg.sender] || msg.sender == owner(), "Not authorized contract");
        _;
    }
    
    modifier canClaim(address user) {
        require(
            block.timestamp >= userRewards[user].lastClaimTimestamp + CLAIM_COOLDOWN,
            "Claim cooldown not met"
        );
        _;
    }
    
    modifier hasRewardToken() {
        require(address(rewardToken) != address(0), "Reward token not set");
        _;
    }
    
    constructor() Ownable(msg.sender) {
        // Initialize reward pools
        _createRewardPool("VERIFICATION_POOL", 1000000 * 10**18, block.timestamp + 365 days);
        _createRewardPool("CONTRIBUTION_POOL", 500000 * 10**18, block.timestamp + 365 days);
        _createRewardPool("BONUS_POOL", 200000 * 10**18, block.timestamp + 365 days);
    }
    
    /**
     * @dev Set the reward token contract
     */
    function setRewardToken(address _rewardToken) external onlyOwner {
        require(_rewardToken != address(0), "Invalid token address");
        rewardToken = IERC20(_rewardToken);
    }
    
    /**
     * @dev Set contract addresses for interoperability
     */
    function setContractAddresses(
        address _credentialRegistry,
        address _reputationSystem,
        address _governanceContract
    ) external onlyOwner {
        credentialRegistry = _credentialRegistry;
        reputationSystem = _reputationSystem;
        governanceContract = _governanceContract;
        
        // Authorize these contracts to distribute rewards
        authorizedContracts[_credentialRegistry] = true;
        authorizedContracts[_reputationSystem] = true;
        authorizedContracts[_governanceContract] = true;
    }
    
    /**
     * @dev Authorize a contract to distribute rewards
     */
    function authorizeContract(address contractAddress) external onlyOwner {
        authorizedContracts[contractAddress] = true;
    }
    
    /**
     * @dev Create a new reward pool
     */
    function _createRewardPool(string memory poolName, uint256 amount, uint256 expiresAt) internal {
        rewardPools[poolName] = RewardPool({
            totalPool: amount,
            distributedAmount: 0,
            remainingAmount: amount,
            isActive: true,
            createdAt: block.timestamp,
            expiresAt: expiresAt
        });
        
        emit RewardPoolCreated(poolName, amount, expiresAt);
    }
    
    /**
     * @dev Initialize user rewards
     */
    function initializeUser(address user) public {
        if (userRewards[user].user == address(0)) {
            userRewards[user] = UserRewards({
                user: user,
                totalEarned: 0,
                totalClaimed: 0,
                pendingRewards: 0,
                lastClaimTimestamp: 0,
                verificationRewards: 0,
                contributionRewards: 0,
                bonusRewards: 0
            });
        }
    }
    
    /**
     * @dev Distribute verification reward
     */
    function distributeVerificationReward(address user) external onlyAuthorizedContract {
        initializeUser(user);
        
        uint256 baseReward = VERIFICATION_REWARD;
        uint256 multiplier = _getReputationMultiplier(user);
        uint256 finalReward = (baseReward * multiplier) / 100;
        
        _distributeReward(user, finalReward, "VERIFICATION", "VERIFICATION_POOL", multiplier);
        userRewards[user].verificationRewards += finalReward;
    }
    
    /**
     * @dev Distribute credential issuance reward
     */
    function distributeCredentialIssueReward(address user) external onlyAuthorizedContract {
        initializeUser(user);
        
        uint256 baseReward = CREDENTIAL_ISSUE_REWARD;
        uint256 multiplier = _getReputationMultiplier(user);
        uint256 finalReward = (baseReward * multiplier) / 100;
        
        _distributeReward(user, finalReward, "CREDENTIAL_ISSUE", "CONTRIBUTION_POOL", multiplier);
        userRewards[user].contributionRewards += finalReward;
    }
    
    /**
     * @dev Distribute credential receive reward
     */
    function distributeCredentialReceiveReward(address user) external onlyAuthorizedContract {
        initializeUser(user);
        
        uint256 baseReward = CREDENTIAL_RECEIVE_REWARD;
        uint256 multiplier = _getReputationMultiplier(user);
        uint256 finalReward = (baseReward * multiplier) / 100;
        
        _distributeReward(user, finalReward, "CREDENTIAL_RECEIVE", "CONTRIBUTION_POOL", multiplier);
        userRewards[user].contributionRewards += finalReward;
    }
    
    /**
     * @dev Distribute daily activity bonus
     */
    function distributeDailyBonus(address user) external onlyAuthorizedContract {
        initializeUser(user);
        
        // Check if user already claimed daily bonus today
        require(
            block.timestamp >= userRewards[user].lastClaimTimestamp + 1 days,
            "Daily bonus already claimed"
        );
        
        uint256 bonusAmount = DAILY_ACTIVITY_BONUS;
        _distributeReward(user, bonusAmount, "DAILY_BONUS", "BONUS_POOL", 100);
        userRewards[user].bonusRewards += bonusAmount;
        
        emit BonusDistributed(user, bonusAmount, "DAILY_BONUS");
    }
    
    /**
     * @dev Internal function to distribute rewards
     */
    function _distributeReward(
        address user,
        uint256 amount,
        string memory rewardType,
        string memory poolName,
        uint256 multiplier
    ) internal {
        require(rewardPools[poolName].isActive, "Reward pool not active");
        require(rewardPools[poolName].remainingAmount >= amount, "Insufficient pool balance");
        
        // Update pool
        rewardPools[poolName].distributedAmount += amount;
        rewardPools[poolName].remainingAmount -= amount;
        
        // Update user rewards
        userRewards[user].totalEarned += amount;
        userRewards[user].pendingRewards += amount;
        
        // Record transaction
        _recordTransaction(user, amount, rewardType, multiplier);
        
        emit RewardEarned(user, amount, rewardType, multiplier);
    }
    
    /**
     * @dev Record reward transaction
     */
    function _recordTransaction(address user, uint256 amount, string memory rewardType, uint256 multiplier) internal {
        _transactionIdCounter++;
        
        RewardTransaction memory transaction = RewardTransaction({
            transactionId: _transactionIdCounter,
            user: user,
            amount: amount,
            rewardType: rewardType,
            timestamp: block.timestamp,
            isClaimed: false,
            multiplier: multiplier
        });
        
        userTransactions[user].push(transaction);
    }
    
    /**
     * @dev Get reputation multiplier from reputation system
     */
    function _getReputationMultiplier(address user) internal view returns (uint256) {
        if (reputationSystem != address(0)) {
            (bool success, bytes memory data) = reputationSystem.staticcall(
                abi.encodeWithSignature("getReputationMultiplier(address)", user)
            );
            if (success && data.length > 0) {
                return abi.decode(data, (uint256));
            }
        }
        return 100; // Default 1x multiplier
    }
    
    /**
     * @dev Claim pending rewards
     */
    function claimRewards() external nonReentrant hasRewardToken canClaim(msg.sender) {
        UserRewards storage user = userRewards[msg.sender];
        require(user.pendingRewards > 0, "No pending rewards");
        
        uint256 claimAmount = user.pendingRewards;
        require(rewardToken.balanceOf(address(this)) >= claimAmount, "Insufficient contract balance");
        
        // Update user state
        user.pendingRewards = 0;
        user.totalClaimed += claimAmount;
        user.lastClaimTimestamp = block.timestamp;
        
        // Mark transactions as claimed
        RewardTransaction[] storage transactions = userTransactions[msg.sender];
        for (uint256 i = 0; i < transactions.length; i++) {
            if (!transactions[i].isClaimed) {
                transactions[i].isClaimed = true;
            }
        }
        
        // Transfer tokens
        require(rewardToken.transfer(msg.sender, claimAmount), "Token transfer failed");
        
        emit RewardClaimed(msg.sender, claimAmount, block.timestamp);
    }
    
    /**
     * @dev Get user reward details
     */
    function getUserRewards(address user) external view returns (UserRewards memory) {
        return userRewards[user];
    }
    
    /**
     * @dev Get user transactions
     */
    function getUserTransactions(address user) external view returns (RewardTransaction[] memory) {
        return userTransactions[user];
    }
    
    /**
     * @dev Get reward pool details
     */
    function getRewardPool(string memory poolName) external view returns (RewardPool memory) {
        return rewardPools[poolName];
    }
    
    /**
     * @dev Check if user can claim rewards
     */
    function canUserClaim(address user) external view returns (bool) {
        return block.timestamp >= userRewards[user].lastClaimTimestamp + CLAIM_COOLDOWN &&
               userRewards[user].pendingRewards > 0;
    }
    
    /**
     * @dev Get pending rewards for user
     */
    function getPendingRewards(address user) external view returns (uint256) {
        return userRewards[user].pendingRewards;
    }
    
    /**
     * @dev Emergency withdraw (owner only)
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(owner(), amount), "Transfer failed");
    }
    
    /**
     * @dev Add funds to reward pool
     */
    function addToRewardPool(string memory poolName, uint256 amount) external onlyOwner hasRewardToken {
        require(rewardPools[poolName].totalPool > 0, "Pool does not exist");
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        rewardPools[poolName].totalPool += amount;
        rewardPools[poolName].remainingAmount += amount;
    }
    
    /**
     * @dev Batch distribute rewards
     */
    function batchDistributeRewards(
        address[] memory users,
        uint256[] memory amounts,
        string[] memory rewardTypes
    ) external onlyAuthorizedContract {
        require(users.length == amounts.length && amounts.length == rewardTypes.length, "Array length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            initializeUser(users[i]);
            uint256 multiplier = _getReputationMultiplier(users[i]);
            uint256 finalAmount = (amounts[i] * multiplier) / 100;
            _distributeReward(users[i], finalAmount, rewardTypes[i], "CONTRIBUTION_POOL", multiplier);
        }
    }
}