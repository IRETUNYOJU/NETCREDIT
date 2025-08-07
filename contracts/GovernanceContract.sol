// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GovernanceContract
 * @dev Manages community governance and voting for platform decisions
 * @notice This contract handles proposals, voting, and execution of governance decisions
 */
contract GovernanceContract is Ownable, ReentrancyGuard {
    // Structs
    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        string proposalType; // "PARAMETER_CHANGE", "NEW_FEATURE", "PENALTY", "REWARD_POOL"
        bytes executionData;
        address targetContract;
        uint256 createdAt;
        uint256 votingStartTime;
        uint256 votingEndTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        bool cancelled;
        ProposalState state;
    }
    
    struct Vote {
        address voter;
        uint256 proposalId;
        VoteType voteType;
        uint256 votingPower;
        uint256 timestamp;
        string reason;
    }
    
    struct GovernanceParameters {
        uint256 proposalThreshold; // Minimum reputation to create proposal
        uint256 votingDelay; // Delay before voting starts
        uint256 votingPeriod; // Duration of voting period
        uint256 quorumThreshold; // Minimum participation for valid vote
        uint256 approvalThreshold; // Minimum approval percentage
        uint256 executionDelay; // Delay before execution after approval
    }
    
    // Enums
    enum ProposalState {
        Pending,
        Active,
        Succeeded,
        Defeated,
        Queued,
        Executed,
        Cancelled
    }
    
    enum VoteType {
        Against,
        For,
        Abstain
    }
    
    // State variables
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => uint256[]) public userProposals;
    mapping(address => uint256[]) public userVotes;
    
    uint256 private _proposalIdCounter = 0;
    GovernanceParameters public governanceParams;
    
    // Contract references
    address public credentialRegistry;
    address public reputationSystem;
    address public rewardContract;
    
    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        string proposalType
    );
    
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        VoteType voteType,
        uint256 votingPower,
        string reason
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId,
        bool success
    );
    
    event ProposalCancelled(
        uint256 indexed proposalId,
        address indexed canceller
    );
    
    event GovernanceParametersUpdated(
        uint256 proposalThreshold,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 quorumThreshold,
        uint256 approvalThreshold
    );
    
    // Modifiers
    modifier onlyProposer(uint256 proposalId) {
        require(proposals[proposalId].proposer == msg.sender, "Not the proposer");
        _;
    }
    
    modifier proposalExists(uint256 proposalId) {
        require(proposals[proposalId].id != 0, "Proposal does not exist");
        _;
    }
    
    modifier canVote(uint256 proposalId) {
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        require(getProposalState(proposalId) == ProposalState.Active, "Voting not active");
        require(_getVotingPower(msg.sender) > 0, "No voting power");
        _;
    }
    
    modifier canPropose() {
        require(_getVotingPower(msg.sender) >= governanceParams.proposalThreshold, "Insufficient reputation to propose");
        _;
    }
    
    constructor() Ownable(msg.sender) {
        // Initialize governance parameters
        governanceParams = GovernanceParameters({
            proposalThreshold: 100, // Minimum reputation score
            votingDelay: 1 days, // 1 day delay before voting starts
            votingPeriod: 7 days, // 7 days voting period
            quorumThreshold: 10, // 10% participation required
            approvalThreshold: 60, // 60% approval required
            executionDelay: 2 days // 2 days delay before execution
        });
    }
    
    /**
     * @dev Set contract addresses for interoperability
     */
    function setContractAddresses(
        address _credentialRegistry,
        address _reputationSystem,
        address _rewardContract
    ) external onlyOwner {
        credentialRegistry = _credentialRegistry;
        reputationSystem = _reputationSystem;
        rewardContract = _rewardContract;
    }
    
    /**
     * @dev Create a new proposal
     */
    function createProposal(
        string memory title,
        string memory description,
        string memory proposalType,
        bytes memory executionData,
        address targetContract
    ) external canPropose returns (uint256) {
        require(bytes(title).length > 0, "Title required");
        require(bytes(description).length > 0, "Description required");
        require(bytes(proposalType).length > 0, "Proposal type required");
        
        _proposalIdCounter++;
        uint256 proposalId = _proposalIdCounter;
        
        uint256 votingStartTime = block.timestamp + governanceParams.votingDelay;
        uint256 votingEndTime = votingStartTime + governanceParams.votingPeriod;
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            title: title,
            description: description,
            proposalType: proposalType,
            executionData: executionData,
            targetContract: targetContract,
            createdAt: block.timestamp,
            votingStartTime: votingStartTime,
            votingEndTime: votingEndTime,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            executed: false,
            cancelled: false,
            state: ProposalState.Pending
        });
        
        userProposals[msg.sender].push(proposalId);
        
        emit ProposalCreated(proposalId, msg.sender, title, proposalType);
        
        return proposalId;
    }
    
    /**
     * @dev Cast a vote on a proposal
     */
    function castVote(
        uint256 proposalId,
        VoteType voteType,
        string memory reason
    ) external proposalExists(proposalId) canVote(proposalId) {
        uint256 votingPower = _getVotingPower(msg.sender);
        
        Vote memory vote = Vote({
            voter: msg.sender,
            proposalId: proposalId,
            voteType: voteType,
            votingPower: votingPower,
            timestamp: block.timestamp,
            reason: reason
        });
        
        votes[proposalId][msg.sender] = vote;
        hasVoted[proposalId][msg.sender] = true;
        userVotes[msg.sender].push(proposalId);
        
        // Update vote counts
        if (voteType == VoteType.For) {
            proposals[proposalId].forVotes += votingPower;
        } else if (voteType == VoteType.Against) {
            proposals[proposalId].againstVotes += votingPower;
        } else {
            proposals[proposalId].abstainVotes += votingPower;
        }
        
        emit VoteCast(msg.sender, proposalId, voteType, votingPower, reason);
    }
    
    /**
     * @dev Execute a successful proposal
     */
    function executeProposal(uint256 proposalId) external proposalExists(proposalId) nonReentrant {
        require(getProposalState(proposalId) == ProposalState.Succeeded, "Proposal not ready for execution");
        require(!proposals[proposalId].executed, "Proposal already executed");
        require(
            block.timestamp >= proposals[proposalId].votingEndTime + governanceParams.executionDelay,
            "Execution delay not met"
        );
        
        proposals[proposalId].executed = true;
        proposals[proposalId].state = ProposalState.Executed;
        
        bool success = false;
        
        // Execute the proposal based on type
        if (keccak256(bytes(proposals[proposalId].proposalType)) == keccak256(bytes("PARAMETER_CHANGE"))) {
            success = _executeParameterChange(proposalId);
        } else if (keccak256(bytes(proposals[proposalId].proposalType)) == keccak256(bytes("NEW_FEATURE"))) {
            success = _executeNewFeature(proposalId);
        } else if (keccak256(bytes(proposals[proposalId].proposalType)) == keccak256(bytes("PENALTY"))) {
            success = _executePenalty(proposalId);
        } else if (keccak256(bytes(proposals[proposalId].proposalType)) == keccak256(bytes("REWARD_POOL"))) {
            success = _executeRewardPoolChange(proposalId);
        } else {
            // Generic execution
            success = _executeGeneric(proposalId);
        }
        
        emit ProposalExecuted(proposalId, success);
        
        // Reward participants
        _rewardGovernanceParticipation(proposalId);
    }
    
    /**
     * @dev Cancel a proposal (only proposer or owner)
     */
    function cancelProposal(uint256 proposalId) external proposalExists(proposalId) {
        require(
            msg.sender == proposals[proposalId].proposer || msg.sender == owner(),
            "Not authorized to cancel"
        );
        require(!proposals[proposalId].executed, "Cannot cancel executed proposal");
        require(getProposalState(proposalId) != ProposalState.Executed, "Cannot cancel executed proposal");
        
        proposals[proposalId].cancelled = true;
        proposals[proposalId].state = ProposalState.Cancelled;
        
        emit ProposalCancelled(proposalId, msg.sender);
    }
    
    /**
     * @dev Get proposal state
     */
    function getProposalState(uint256 proposalId) public view proposalExists(proposalId) returns (ProposalState) {
        Proposal memory proposal = proposals[proposalId];
        
        if (proposal.cancelled) {
            return ProposalState.Cancelled;
        }
        
        if (proposal.executed) {
            return ProposalState.Executed;
        }
        
        if (block.timestamp < proposal.votingStartTime) {
            return ProposalState.Pending;
        }
        
        if (block.timestamp <= proposal.votingEndTime) {
            return ProposalState.Active;
        }
        
        // Check if proposal succeeded
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 totalVotingPower = _getTotalVotingPower();
        
        // Check quorum
        if (totalVotes * 100 < totalVotingPower * governanceParams.quorumThreshold) {
            return ProposalState.Defeated;
        }
        
        // Check approval threshold
        if (proposal.forVotes * 100 >= (proposal.forVotes + proposal.againstVotes) * governanceParams.approvalThreshold) {
            return ProposalState.Succeeded;
        }
        
        return ProposalState.Defeated;
    }
    
    /**
     * @dev Get voting power for an address
     */
    function _getVotingPower(address user) internal view returns (uint256) {
        if (reputationSystem != address(0)) {
            (bool success, bytes memory data) = reputationSystem.staticcall(
                abi.encodeWithSignature("getUserScore(address)", user)
            );
            if (success && data.length > 0) {
                return abi.decode(data, (uint256));
            }
        }
        return 0;
    }
    
    /**
     * @dev Get total voting power (simplified implementation)
     */
    function _getTotalVotingPower() internal pure returns (uint256) {
        // This would need to be calculated based on all users' reputation
        // For now, returning a placeholder value
        return 10000;
    }
    
    /**
     * @dev Execute parameter change proposal
     */
    function _executeParameterChange(uint256 proposalId) internal returns (bool) {
        // Decode and execute parameter changes
        // This would contain specific logic for different parameter changes
        return true;
    }
    
    /**
     * @dev Execute new feature proposal
     */
    function _executeNewFeature(uint256 proposalId) internal returns (bool) {
        // Execute new feature addition
        return true;
    }
    
    /**
     * @dev Execute penalty proposal
     */
    function _executePenalty(uint256 proposalId) internal returns (bool) {
        // Execute penalty against a user
        if (reputationSystem != address(0)) {
            (bool success,) = reputationSystem.call(proposals[proposalId].executionData);
            return success;
        }
        return false;
    }
    
    /**
     * @dev Execute reward pool change proposal
     */
    function _executeRewardPoolChange(uint256 proposalId) internal returns (bool) {
        // Execute reward pool modifications
        if (rewardContract != address(0)) {
            (bool success,) = rewardContract.call(proposals[proposalId].executionData);
            return success;
        }
        return false;
    }
    
    /**
     * @dev Execute generic proposal
     */
    function _executeGeneric(uint256 proposalId) internal returns (bool) {
        Proposal memory proposal = proposals[proposalId];
        if (proposal.targetContract != address(0) && proposal.executionData.length > 0) {
            (bool success,) = proposal.targetContract.call(proposal.executionData);
            return success;
        }
        return true;
    }
    
    /**
     * @dev Reward governance participation
     */
    function _rewardGovernanceParticipation(uint256 proposalId) internal {
        if (rewardContract != address(0)) {
            // Reward the proposer
            (bool success,) = rewardContract.call(
                abi.encodeWithSignature("distributeGovernanceReward(address,string)", 
                proposals[proposalId].proposer, "PROPOSAL_EXECUTED")
            );
            
            // This could be extended to reward voters as well
        }
    }
    
    /**
     * @dev Update governance parameters
     */
    function updateGovernanceParameters(
        uint256 _proposalThreshold,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumThreshold,
        uint256 _approvalThreshold,
        uint256 _executionDelay
    ) external onlyOwner {
        require(_quorumThreshold <= 100, "Invalid quorum threshold");
        require(_approvalThreshold <= 100, "Invalid approval threshold");
        
        governanceParams.proposalThreshold = _proposalThreshold;
        governanceParams.votingDelay = _votingDelay;
        governanceParams.votingPeriod = _votingPeriod;
        governanceParams.quorumThreshold = _quorumThreshold;
        governanceParams.approvalThreshold = _approvalThreshold;
        governanceParams.executionDelay = _executionDelay;
        
        emit GovernanceParametersUpdated(
            _proposalThreshold,
            _votingDelay,
            _votingPeriod,
            _quorumThreshold,
            _approvalThreshold
        );
    }
    
    /**
     * @dev Get proposal details
     */
    function getProposal(uint256 proposalId) external view proposalExists(proposalId) returns (Proposal memory) {
        return proposals[proposalId];
    }
    
    /**
     * @dev Get vote details
     */
    function getVote(uint256 proposalId, address voter) external view returns (Vote memory) {
        return votes[proposalId][voter];
    }
    
    /**
     * @dev Get user's proposals
     */
    function getUserProposals(address user) external view returns (uint256[] memory) {
        return userProposals[user];
    }
    
    /**
     * @dev Get user's votes
     */
    function getUserVotes(address user) external view returns (uint256[] memory) {
        return userVotes[user];
    }
    
    /**
     * @dev Get governance parameters
     */
    function getGovernanceParameters() external view returns (GovernanceParameters memory) {
        return governanceParams;
    }
    
    /**
     * @dev Get voting power for a user
     */
    function getVotingPower(address user) external view returns (uint256) {
        return _getVotingPower(user);
    }
    
    /**
     * @dev Get current proposal ID counter
     */
    function getCurrentProposalId() external view returns (uint256) {
        return _proposalIdCounter;
    }
    
    /**
     * @dev Check if user has voted on proposal
     */
    function hasUserVoted(uint256 proposalId, address user) external view returns (bool) {
        return hasVoted[proposalId][user];
    }
    
    /**
     * @dev Get proposal vote counts
     */
    function getProposalVotes(uint256 proposalId) external view proposalExists(proposalId) returns (
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        uint256 totalVotes
    ) {
        Proposal memory proposal = proposals[proposalId];
        forVotes = proposal.forVotes;
        againstVotes = proposal.againstVotes;
        abstainVotes = proposal.abstainVotes;
        totalVotes = forVotes + againstVotes + abstainVotes;
    }
}