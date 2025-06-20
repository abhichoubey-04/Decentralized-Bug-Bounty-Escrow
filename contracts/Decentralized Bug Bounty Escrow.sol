// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Bug Bounty Escrow
 * @dev A simplified smart contract for managing bug bounty programs with automated escrow
 * @author Decentralized Bug Bounty Team
 */
contract Project {
    
    // Enums for status tracking
    enum BountyStatus { Active, Completed, Cancelled }
    enum ReportStatus { Submitted, Approved, Rejected }
    
    // Core data structures
    struct Bounty {
        uint256 id;
        address creator;
        string description;
        uint256 reward;
        uint256 deadline;
        BountyStatus status;
        uint256 validationsRequired;
    }
    
    struct BugReport {
        uint256 id;
        uint256 bountyId;
        address reporter;
        string vulnerability;
        string proofOfConcept;
        ReportStatus status;
        uint256 validationCount;
    }
    
    // State variables
    uint256 public nextBountyId = 1;
    uint256 public nextReportId = 1;
    uint256 public platformFeePercent = 250; // 2.5%
    address public owner;
    
    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => BugReport) public bugReports;
    mapping(address => bool) public authorizedValidators;
    mapping(uint256 => mapping(address => bool)) public hasValidated;
    
    // Events
    event BountyCreated(uint256 indexed bountyId, address indexed creator, uint256 reward);
    event ReportSubmitted(uint256 indexed reportId, uint256 indexed bountyId, address indexed reporter);
    event ReportValidated(uint256 indexed reportId, address indexed validator, bool approved);
    event RewardPaid(uint256 indexed reportId, address indexed reporter, uint256 amount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not contract owner");
        _;
    }
    
    modifier onlyValidator() {
        require(authorizedValidators[msg.sender], "Not authorized validator");
        _;
    }
    
    modifier bountyExists(uint256 _bountyId) {
        require(_bountyId < nextBountyId && _bountyId > 0, "Bounty does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        authorizedValidators[msg.sender] = true;
    }
    
    /**
     * @dev Core Function 1: Create a new bug bounty with escrow funds
     * @param _description Description of the bounty and vulnerability scope
     * @param _deadline Timestamp when the bounty expires
     * @param _validationsRequired Number of validator approvals needed
     */
    function createBounty(
        string memory _description,
        uint256 _deadline,
        uint256 _validationsRequired
    ) external payable {
        require(msg.value > 0, "Must deposit reward funds");
        require(_deadline > block.timestamp, "Deadline must be in future");
        require(_validationsRequired > 0, "Must require at least 1 validation");
        
        uint256 bountyId = nextBountyId++;
        
        bounties[bountyId] = Bounty({
            id: bountyId,
            creator: msg.sender,
            description: _description,
            reward: msg.value,
            deadline: _deadline,
            status: BountyStatus.Active,
            validationsRequired: _validationsRequired
        });
        
        emit BountyCreated(bountyId, msg.sender, msg.value);
    }
    
    /**
     * @dev Core Function 2: Submit a bug report for validation
     * @param _bountyId ID of the bounty this report is for
     * @param _vulnerability Description of the discovered vulnerability
     * @param _proofOfConcept Proof of concept or reproduction steps
     */
    function submitReport(
        uint256 _bountyId,
        string memory _vulnerability,
        string memory _proofOfConcept
    ) external bountyExists(_bountyId) {
        Bounty storage bounty = bounties[_bountyId];
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        require(block.timestamp < bounty.deadline, "Bounty expired");
        
        uint256 reportId = nextReportId++;
        
        bugReports[reportId] = BugReport({
            id: reportId,
            bountyId: _bountyId,
            reporter: msg.sender,
            vulnerability: _vulnerability,
            proofOfConcept: _proofOfConcept,
            status: ReportStatus.Submitted,
            validationCount: 0
        });
        
        emit ReportSubmitted(reportId, _bountyId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Validate a submitted bug report
     * @param _reportId ID of the report to validate
     * @param _approved Whether to approve or reject the report
     */
    function validateReport(uint256 _reportId, bool _approved) external onlyValidator {
        require(_reportId < nextReportId && _reportId > 0, "Report does not exist");
        
        BugReport storage report = bugReports[_reportId];
        Bounty storage bounty = bounties[report.bountyId];
        
        require(report.status == ReportStatus.Submitted, "Report already processed");
        require(!hasValidated[_reportId][msg.sender], "Already validated this report");
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        
        hasValidated[_reportId][msg.sender] = true;
        
        if (_approved) {
            report.validationCount++;
            
            // Check if enough validations received
            if (report.validationCount >= bounty.validationsRequired) {
                report.status = ReportStatus.Approved;
                bounty.status = BountyStatus.Completed;
                
                // Calculate and transfer rewards
                uint256 platformFee = (bounty.reward * platformFeePercent) / 10000;
                uint256 reporterReward = bounty.reward - platformFee;
                
                // Transfer reward to reporter
                payable(report.reporter).transfer(reporterReward);
                
                // Transfer platform fee to owner
                if (platformFee > 0) {
                    payable(owner).transfer(platformFee);
                }
                
                emit RewardPaid(_reportId, report.reporter, reporterReward);
            }
        } else {
            report.status = ReportStatus.Rejected;
        }
        
        emit ReportValidated(_reportId, msg.sender, _approved);
    }
    
    // Administrative functions
    function addValidator(address _validator) external onlyOwner {
        authorizedValidators[_validator] = true;
    }
    
    function removeValidator(address _validator) external onlyOwner {
        authorizedValidators[_validator] = false;
    }
    
    function withdrawExpiredBounty(uint256 _bountyId) external bountyExists(_bountyId) {
        Bounty storage bounty = bounties[_bountyId];
        require(msg.sender == bounty.creator, "Not bounty creator");
        require(block.timestamp > bounty.deadline, "Bounty not expired");
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        
        bounty.status = BountyStatus.Cancelled;
        payable(bounty.creator).transfer(bounty.reward);
    }
    
    // View functions
    function getBountyDetails(uint256 _bountyId) external view returns (
        address creator,
        string memory description,
        uint256 reward,
        uint256 deadline,
        BountyStatus status
    ) {
        Bounty storage bounty = bounties[_bountyId];
        return (bounty.creator, bounty.description, bounty.reward, bounty.deadline, bounty.status);
    }
    
    function getReportDetails(uint256 _reportId) external view returns (
        uint256 bountyId,
        address reporter,
        string memory vulnerability,
        ReportStatus status,
        uint256 validationCount
    ) {
        BugReport storage report = bugReports[_reportId];
        return (report.bountyId, report.reporter, report.vulnerability, report.status, report.validationCount);
    }
}


contract Detail: 0x4ADB15840c84361A54D92Afd3f36Fa2F367C1885
