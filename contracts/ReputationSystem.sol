// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ReputationSystem
 * @dev Manages user reputation scores and trust metrics
 * @notice This contract tracks and calculates reputation based on various activities
 */
contract ReputationSystem is Ownable, ReentrancyGuard {
    // Structs
    struct UserReputation {
        address user;
        uint256 totalScore;
        uint256 credentialsIssued;
        uint256 credentialsVerified;
        uint256 credentialsReceived;
        uint256 verificationsMade;
        uint256 lastActivityTimestamp;
        bool isActive;
        uint256 trustLevel; // 1-5 scale
    }
    
    struct ReputationAction {
        uint256 actionId;
        address user;
        string actionType;
        uint256 scoreChange;
        uint256 timestamp;
        address relatedUser;
    }
    
    // State variables
    mapping(address => UserReputation) public userReputations;
    mapping(address => ReputationAction[]) public userActions;
    mapping(address => bool) public authorizedContracts;
    
    uint256 private _actionIdCounter = 0;
    
    // Reputation scoring constants
    uint256 public constant CREDENTIAL_ISSUED_SCORE = 10;
    uint256 public constant CREDENTIAL_VERIFIED_SCORE = 5;
    uint256 public constant VERIFICATION_MADE_SCORE = 3;
    uint256 public constant CREDENTIAL_RECEIVED_SCORE = 2;
    uint256 public constant PENALTY_SCORE = 20;
    
    // Trust level thresholds
    uint256 public constant TRUST_LEVEL_1_THRESHOLD = 0;
    uint256 public constant TRUST_LEVEL_2_THRESHOLD = 50;
    uint256 public constant TRUST_LEVEL_3_THRESHOLD = 150;
    uint256 public constant TRUST_LEVEL_4_THRESHOLD = 300;
    uint256 public constant TRUST_LEVEL_5_THRESHOLD = 500;
    
    // Contract references
    address public credentialRegistry;
    address public rewardContract;
    address public governanceContract;
    
    // Events
    event ReputationUpdated(
        address indexed user,
        uint256 oldScore,
        uint256 newScore,
        string actionType
    );
    
    event TrustLevelChanged(
        address indexed user,
        uint256 oldLevel,
        uint256 newLevel
    );
    
    event UserPenalized(
        address indexed user,
        uint256 penaltyAmount,
        string reason
    );
    
    // Modifiers
    modifier onlyAuthorizedContract() {
        require(authorizedContracts[msg.sender] || msg.sender == owner(), "Not authorized contract");
        _;
    }
    
    modifier userExists(address user) {
        require(userReputations[user].user != address(0), "User not found");
        _;
    }
    
    constructor() Ownable(msg.sender) {
        // Initialize with default values
    }
    
    /**
     * @dev Set contract addresses for interoperability
     */
    function setContractAddresses(
        address _credentialRegistry,
        address _rewardContract,
        address _governanceContract
    ) external onlyOwner {
        credentialRegistry = _credentialRegistry;
        rewardContract = _rewardContract;
        governanceContract = _governanceContract;
        
        // Authorize these contracts to update reputation
        authorizedContracts[_credentialRegistry] = true;
        authorizedContracts[_rewardContract] = true;
        authorizedContracts[_governanceContract] = true;
    }
    
    /**
     * @dev Authorize a contract to update reputation
     */
    function authorizeContract(address contractAddress) external onlyOwner {
        authorizedContracts[contractAddress] = true;
    }
    
    /**
     * @dev Revoke contract authorization
     */
    function revokeContractAuthorization(address contractAddress) external onlyOwner {
        authorizedContracts[contractAddress] = false;
    }
    
    /**
     * @dev Initialize user reputation (called when user first interacts)
     */
    function initializeUser(address user) public {
        require(userReputations[user].user == address(0), "User already initialized");
        
        userReputations[user] = UserReputation({
            user: user,
            totalScore: 100, // Starting score
            credentialsIssued: 0,
            credentialsVerified: 0,
            credentialsReceived: 0,
            verificationsMade: 0,
            lastActivityTimestamp: block.timestamp,
            isActive: true,
            trustLevel: 1
        });
    }
    
    /**
     * @dev Get user trust level
     */
    function getUserTrustLevel(address user) public view returns (uint256) {
        if (userReputations[user].user == address(0)) {
            return 1; // Default trust level for new users
        }
        return userReputations[user].trustLevel;
    }
    
    /**
     * @dev Update user trust level based on score
     */
    function _updateTrustLevel(address user) internal {
        uint256 score = userReputations[user].totalScore;
        
        if (score >= TRUST_LEVEL_5_THRESHOLD) {
            userReputations[user].trustLevel = 5;
        } else if (score >= TRUST_LEVEL_4_THRESHOLD) {
            userReputations[user].trustLevel = 4;
        } else if (score >= TRUST_LEVEL_3_THRESHOLD) {
            userReputations[user].trustLevel = 3;
        } else if (score >= TRUST_LEVEL_2_THRESHOLD) {
            userReputations[user].trustLevel = 2;
        } else {
            userReputations[user].trustLevel = 1;
        }
    }
    
    /**
     * @dev Record reputation action
     */
    function _recordAction(address user, string memory actionType, uint256 scoreChange, address relatedUser) internal {
        _actionIdCounter++;
        
        ReputationAction memory action = ReputationAction({
            actionId: _actionIdCounter,
            user: user,
            actionType: actionType,
            scoreChange: scoreChange,
            timestamp: block.timestamp,
            relatedUser: relatedUser
        });
        
        userActions[user].push(action);
    }
    
    /**
     * @dev Internal function to update user score
     */
    function _updateUserScore(address user, uint256 scoreChange, string memory actionType, address relatedUser) internal {
        uint256 oldScore = userReputations[user].totalScore;
        userReputations[user].totalScore += scoreChange;
        userReputations[user].lastActivityTimestamp = block.timestamp;
        
        uint256 oldTrustLevel = userReputations[user].trustLevel;
        _updateTrustLevel(user);
        
        _recordAction(user, actionType, scoreChange, relatedUser);
        
        emit ReputationUpdated(user, oldScore, userReputations[user].totalScore, actionType);
        
        if (oldTrustLevel != userReputations[user].trustLevel) {
            emit TrustLevelChanged(user, oldTrustLevel, userReputations[user].trustLevel);
        }
    }
    
    /**
     * @dev Update reputation when credential is issued
     */
    function updateReputationForCredentialIssued(address issuer, address holder) external onlyAuthorizedContract {
        // Initialize users if they don't exist
        if (userReputations[issuer].user == address(0)) {
            initializeUser(issuer);
        }
        if (userReputations[holder].user == address(0)) {
            initializeUser(holder);
        }
        
        // Update issuer reputation
        _updateUserScore(issuer, CREDENTIAL_ISSUED_SCORE, "CREDENTIAL_ISSUED", holder);
        userReputations[issuer].credentialsIssued++;
        
        // Update holder reputation
        _updateUserScore(holder, CREDENTIAL_RECEIVED_SCORE, "CREDENTIAL_RECEIVED", issuer);
        userReputations[holder].credentialsReceived++;
    }
    
    /**
     * @dev Update reputation when credential is verified
     */
    function updateReputationForVerification(address verifier, address holder) external onlyAuthorizedContract {
        // Initialize users if they don't exist
        if (userReputations[verifier].user == address(0)) {
            initializeUser(verifier);
        }
        if (userReputations[holder].user == address(0)) {
            initializeUser(holder);
        }
        
        // Update verifier reputation
        _updateUserScore(verifier, VERIFICATION_MADE_SCORE, "VERIFICATION_MADE", holder);
        userReputations[verifier].verificationsMade++;
        
        // Update holder reputation
        _updateUserScore(holder, CREDENTIAL_VERIFIED_SCORE, "CREDENTIAL_VERIFIED", verifier);
        userReputations[holder].credentialsVerified++;
    }
    
    /**
     * @dev Penalize user for malicious behavior
     */
    function penalizeUser(address user, string memory reason) external onlyAuthorizedContract userExists(user) {
        uint256 oldScore = userReputations[user].totalScore;
        
        if (userReputations[user].totalScore >= PENALTY_SCORE) {
            userReputations[user].totalScore -= PENALTY_SCORE;
        } else {
            userReputations[user].totalScore = 0;
        }
        
        _updateTrustLevel(user);
        _recordAction(user, "PENALTY", PENALTY_SCORE, address(0));
        
        emit UserPenalized(user, PENALTY_SCORE, reason);
        emit ReputationUpdated(user, oldScore, userReputations[user].totalScore, "PENALTY");
    }
    
    /**
     * @dev Get user reputation details
     */
    function getUserReputation(address user) external view returns (UserReputation memory) {
        return userReputations[user];
    }
    
    /**
     * @dev Get user actions history
     */
    function getUserActions(address user) external view returns (ReputationAction[] memory) {
        return userActions[user];
    }
    
    /**
     * @dev Check if user can perform high-trust actions
     */
    function canPerformHighTrustActions(address user) external view returns (bool) {
        return getUserTrustLevel(user) >= 3;
    }
    
    /**
     * @dev Get user score
     */
    function getUserScore(address user) external view returns (uint256) {
        return userReputations[user].totalScore;
    }
    
    /**
     * @dev Calculate reputation multiplier for rewards
     */
    function getReputationMultiplier(address user) external view returns (uint256) {
        uint256 trustLevel = getUserTrustLevel(user);
        
        if (trustLevel == 5) return 200; // 2x multiplier
        if (trustLevel == 4) return 150; // 1.5x multiplier
        if (trustLevel == 3) return 125; // 1.25x multiplier
        if (trustLevel == 2) return 110; // 1.1x multiplier
        return 100; // 1x multiplier (base)
    }
    
    /**
     * @dev Batch update reputation for multiple users
     */
    function batchUpdateReputation(
        address[] memory users,
        uint256[] memory scores,
        string[] memory actionTypes
    ) external onlyAuthorizedContract {
        require(users.length == scores.length && scores.length == actionTypes.length, "Array length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            if (userReputations[users[i]].user == address(0)) {
                initializeUser(users[i]);
            }
            _updateUserScore(users[i], scores[i], actionTypes[i], address(0));
        }
    }
    
    /**
     * @dev Get top users by reputation
     */
    function getTopUsersByReputation(uint256 limit) external view returns (address[] memory, uint256[] memory) {
        // Note: This is a simplified implementation
        // In production, you might want to maintain a sorted list or use a more efficient approach
        address[] memory topUsers = new address[](limit);
        uint256[] memory topScores = new uint256[](limit);
        
        // This would need to be implemented with proper sorting logic
        // For now, returning empty arrays as placeholder
        return (topUsers, topScores);
    }
}