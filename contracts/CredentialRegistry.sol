// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; 

/**
 * @title CredentialRegistry
 * @dev Core contract for managing professional credentials as NFTs
 * @notice This contract handles credential issuance, verification, and management
 */
contract CredentialRegistry is ERC721, Ownable, ReentrancyGuard {
    // Custom counter implementation without importing Counters
    uint256 private _currentTokenId = 0;
    
    // Structs
    struct Credential {
        uint256 id;
        address issuer;
        address holder;
        string credentialType;
        string institutionName;
        string credentialData; // IPFS hash or encrypted data
        uint256 issuedAt;
        uint256 expiresAt;
        bool isRevoked;
        bool isVerified;
        uint256 verificationCount;
    }
    
    struct Institution {
        address institutionAddress;
        string name;
        string description;
        bool isVerified;
        bool isActive;
        uint256 credentialsIssued;
        uint256 reputationScore;
    }
    
    // State variables
    mapping(uint256 => Credential) public credentials;
    mapping(address => Institution) public institutions;
    mapping(address => uint256[]) public holderCredentials;
    mapping(address => uint256[]) public issuerCredentials;
    mapping(string => bool) public credentialTypes;
    mapping(uint256 => mapping(address => bool)) public credentialVerifications;
    
    // Contract references
    address public reputationContract;
    address public rewardContract;
    address public governanceContract;
    
    // Events
    event CredentialIssued(
        uint256 indexed credentialId,
        address indexed issuer,
        address indexed holder,
        string credentialType
    );
    
    event CredentialVerified(
        uint256 indexed credentialId,
        address indexed verifier
    );
    
    event CredentialRevoked(
        uint256 indexed credentialId,
        address indexed issuer
    );
    
    event InstitutionRegistered(
        address indexed institution,
        string name
    );
    
    event InstitutionVerified(
        address indexed institution
    );
    
    // Modifiers
    modifier onlyVerifiedInstitution() {
        require(institutions[msg.sender].isVerified && institutions[msg.sender].isActive, "Not a verified institution");
        _;
    }
    
    modifier onlyCredentialHolder(uint256 credentialId) {
        require(ownerOf(credentialId) == msg.sender, "Not credential holder");
        _;
    }
    
    modifier onlyCredentialIssuer(uint256 credentialId) {
        require(credentials[credentialId].issuer == msg.sender, "Not credential issuer");
        _;
    }
    
    modifier credentialExists(uint256 credentialId) {
        require(_ownerOf(credentialId) != address(0), "Credential does not exist");
        _;
    }
    
    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) Ownable(msg.sender) {
        // Initialize default credential types
        credentialTypes["DEGREE"] = true;
        credentialTypes["CERTIFICATE"] = true;
        credentialTypes["LICENSE"] = true;
        credentialTypes["SKILL"] = true;
        credentialTypes["EXPERIENCE"] = true;
    }
    
    /**
     * @dev Set contract addresses for interoperability
     */
    function setContractAddresses(
        address _reputationContract,
        address _rewardContract,
        address _governanceContract
    ) external onlyOwner {
        reputationContract = _reputationContract;
        rewardContract = _rewardContract;
        governanceContract = _governanceContract;
    }
    
    /**
     * @dev Register a new institution
     */
    function registerInstitution(
        string memory name,
        string memory description
    ) external {
        require(bytes(name).length > 0, "Institution name required");
        require(institutions[msg.sender].institutionAddress == address(0), "Institution already registered");
        
        institutions[msg.sender] = Institution({
            institutionAddress: msg.sender,
            name: name,
            description: description,
            isVerified: false,
            isActive: true,
            credentialsIssued: 0,
            reputationScore: 100 // Starting reputation
        });
        
        emit InstitutionRegistered(msg.sender, name);
    }
    
    /**
     * @dev Verify an institution (only owner can do this initially)
     */
    function verifyInstitution(address institutionAddress) external onlyOwner {
        require(institutions[institutionAddress].institutionAddress != address(0), "Institution not registered");
        institutions[institutionAddress].isVerified = true;
        
        emit InstitutionVerified(institutionAddress);
    }
    
    /**
     * @dev Issue a new credential
     */
    function issueCredential(
        address holder,
        string memory credentialType,
        string memory institutionName,
        string memory credentialData,
        uint256 expiresAt
    ) external onlyVerifiedInstitution nonReentrant returns (uint256) {
        require(holder != address(0), "Invalid holder address");
        require(credentialTypes[credentialType], "Invalid credential type");
        require(bytes(credentialData).length > 0, "Credential data required");
        require(expiresAt > block.timestamp, "Invalid expiration date");
        
        // Increment token ID
        _currentTokenId++;
        uint256 newCredentialId = _currentTokenId;
        
        // Create credential
        credentials[newCredentialId] = Credential({
            id: newCredentialId,
            issuer: msg.sender,
            holder: holder,
            credentialType: credentialType,
            institutionName: institutionName,
            credentialData: credentialData,
            issuedAt: block.timestamp,
            expiresAt: expiresAt,
            isRevoked: false,
            isVerified: false,
            verificationCount: 0
        });
        
        // Mint NFT to holder
        _safeMint(holder, newCredentialId);
        
        // Update mappings
        holderCredentials[holder].push(newCredentialId);
        issuerCredentials[msg.sender].push(newCredentialId);
        institutions[msg.sender].credentialsIssued++;
        
        emit CredentialIssued(newCredentialId, msg.sender, holder, credentialType);
        
        // Notify reputation contract if available
        if (reputationContract != address(0)) {
            (bool success,) = reputationContract.call(
                abi.encodeWithSignature("updateReputationForCredentialIssued(address,address)", msg.sender, holder)
            );
            require(success, "Reputation update failed");
        }
        
        return newCredentialId;
    }
    
    /**
     * @dev Verify a credential by community members
     */
    function verifyCredential(uint256 credentialId) external credentialExists(credentialId) {
        require(!credentialVerifications[credentialId][msg.sender], "Already verified by this address");
        require(!credentials[credentialId].isRevoked, "Credential is revoked");
        require(credentials[credentialId].expiresAt > block.timestamp, "Credential expired");
        
        credentialVerifications[credentialId][msg.sender] = true;
        credentials[credentialId].verificationCount++;
        
        // Mark as verified if it reaches threshold (e.g., 3 verifications)
        if (credentials[credentialId].verificationCount >= 3) {
            credentials[credentialId].isVerified = true;
        }
        
        emit CredentialVerified(credentialId, msg.sender);
        
        // Notify reputation contract
        if (reputationContract != address(0)) {
            (bool success,) = reputationContract.call(
                abi.encodeWithSignature("updateReputationForVerification(address,address)", 
                msg.sender, credentials[credentialId].holder)
            );
            require(success, "Reputation update failed");
        }
        
        // Notify reward contract
        if (rewardContract != address(0)) {
            (bool success,) = rewardContract.call(
                abi.encodeWithSignature("distributeVerificationReward(address)", msg.sender)
            );
            require(success, "Reward distribution failed");
        }
    }
    
    /**
     * @dev Revoke a credential
     */
    function revokeCredential(uint256 credentialId) external credentialExists(credentialId) onlyCredentialIssuer(credentialId) {
        require(!credentials[credentialId].isRevoked, "Credential already revoked");
        
        credentials[credentialId].isRevoked = true;
        
        emit CredentialRevoked(credentialId, msg.sender);
    }
    
    /**
     * @dev Add new credential type (governance controlled)
     */
    function addCredentialType(string memory credentialType) external {
        require(msg.sender == governanceContract || msg.sender == owner(), "Not authorized");
        credentialTypes[credentialType] = true;
    }
    
    /**
     * @dev Get credential details
     */
    function getCredential(uint256 credentialId) external view credentialExists(credentialId) returns (Credential memory) {
        return credentials[credentialId];
    }
    
    /**
     * @dev Get holder's credentials
     */
    function getHolderCredentials(address holder) external view returns (uint256[] memory) {
        return holderCredentials[holder];
    }
    
    /**
     * @dev Get issuer's credentials
     */
    function getIssuerCredentials(address issuer) external view returns (uint256[] memory) {
        return issuerCredentials[issuer];
    }
    
    /**
     * @dev Get institution details
     */
    function getInstitution(address institutionAddress) external view returns (Institution memory) {
        return institutions[institutionAddress];
    }
    
    /**
     * @dev Get current token ID
     */
    function getCurrentTokenId() external view returns (uint256) {
        return _currentTokenId;
    }
    
    /**
     * @dev Check if credential is valid (not revoked and not expired)
     */
    function isCredentialValid(uint256 credentialId) external view credentialExists(credentialId) returns (bool) {
        Credential memory cred = credentials[credentialId];
        return !cred.isRevoked && cred.expiresAt > block.timestamp;
    }
    
    /**
     * @dev Override transfer functions to prevent credential trading
     */
    function transferFrom(address from, address to, uint256 tokenId) public override {
        revert("Credentials are non-transferable");
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        revert("Credentials are non-transferable");
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        revert("Credentials are non-transferable");
    }
}