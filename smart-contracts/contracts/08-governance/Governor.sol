// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./VotingToken.sol";
import "./Proposal.sol";
import "./Timelock.sol";
import "./Treasury.sol";
import "../libraries/Constants.sol";

/**
 * @title Governor
 * @dev قرارداد حاکمیت اصلی DAO
 */
contract Governor is Ownable, ReentrancyGuard {

    struct GovernanceStats {
        uint256 totalProposals;           // کل proposals
        uint256 activeProposals;          // proposals فعال
        uint256 executedProposals;        // proposals اجرا شده
        uint256 totalVotes;               // کل آرا
        uint256 totalVoters;              // کل رای دهندگان
        uint256 treasuryValue;            // ارزش treasury
        uint256 lastActivity;             // آخرین فعالیت
    }

    struct VoterStats {
        uint256 proposalsVoted;           // تعداد proposals رای داده
        uint256 proposalsCreated;         // تعداد proposals ایجاد شده
        uint256 totalVotingPower;         // کل قدرت رای
        uint256 lastVoteTime;             // آخرین رای
        uint256 reputationScore;          // امتیاز reputation
        bool isDelegate;                  // آیا delegate است
    }

    struct DelegationInfo {
        address delegate;                 // آدرس delegate
        uint256 delegatedPower;           // قدرت تفویض شده
        uint256 delegationTime;           // زمان تفویض
        bool active;                      // فعال/غیرفعال
    }

    // Events
    event ProposalSubmitted(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        Proposal.ProposalType proposalType
    );

    event VoteSubmitted(
        uint256 indexed proposalId,
        address indexed voter,
        Proposal.VoteType support,
        uint256 weight
    );

    event ProposalExecuted(
        uint256 indexed proposalId,
        bool success
    );

    event DelegationChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate,
        uint256 power
    );

    event GovernanceParameterChanged(
        string indexed parameter,
        uint256 oldValue,
        uint256 newValue
    );

    event EmergencyActionTaken(
        address indexed guardian,
        string action,
        bytes data
    );

    // State variables
    VotingToken public votingToken;
    Proposal public proposalContract;
    Timelock public timelock;
    Treasury public treasury;
    
    mapping(address => VoterStats) public voterStats;
    mapping(address => DelegationInfo) public delegations;
    mapping(address => address[]) public delegators; // delegate => delegators list
    mapping(uint256 => bool) public proposalExecuted;
    mapping(address => uint256) public lastProposalBlock;
    
    GovernanceStats public governanceStats;
    
    // Governance parameters (can be changed via governance)
    uint256 public proposalThreshold = 10000 * 10**18;      // 10,000 tokens to propose
    uint256 public quorumPercentage = 1000;                 // 10% quorum
    uint256 public votingDelay = 1 days;                    // 1 day delay
    uint256 public votingPeriod = 7 days;                  // 7 day voting period
    uint256 public timelockDelay = 2 days;                 // 2 day timelock
    uint256 public maxActionsPerProposal = 10;             // Max 10 actions per proposal
    
    // Reputation system
    uint256 public constant REPUTATION_PROPOSAL_BONUS = 100;
    uint256 public constant REPUTATION_VOTE_BONUS = 10;
    uint256 public constant REPUTATION_EXECUTION_BONUS = 50;
    uint256 public constant REPUTATION_DECAY_RATE = 5;      // 5% decay per month
    
    // Emergency powers
    address public guardian;
    bool public emergencyPaused = false;
    uint256 public emergencyDelay = 6 hours;
    mapping(bytes32 => uint256) public emergencyProposals;
    
    // Anti-spam measures
    uint256 public constant MIN_PROPOSAL_INTERVAL = 7 days;
    uint256 public constant MAX_PROPOSALS_PER_USER = 5;
    mapping(address => uint256) public userProposalCount;
    mapping(address => uint256[]) public userProposals;

    error InsufficientVotingPower();
    error ProposalIntervalNotMet();
    error TooManyProposals();
    error ProposalNotFound();
    error EmergencyPaused();
    error UnauthorizedGuardian();
    error InvalidParameter();
    error AlreadyDelegated();

    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPaused();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian && msg.sender != owner()) revert UnauthorizedGuardian();
        _;
    }

    modifier hasVotingPower(address account, uint256 requiredPower) {
        if (_getVotingPower(account) < requiredPower) revert InsufficientVotingPower();
        _;
    }

    constructor(
        address _votingToken,
        address _treasury,
        address _guardian
    ) Ownable(msg.sender) {
        votingToken = VotingToken(_votingToken);
        treasury = Treasury(_treasury);
        guardian = _guardian;
        
        // Deploy Proposal and Timelock contracts
        proposalContract = new Proposal(_votingToken, address(0), _guardian);
        timelock = new Timelock(timelockDelay, address(this), _guardian);
        
        // Initialize governance stats
        governanceStats.lastActivity = block.timestamp;
    }

    /**
     * @dev ایجاد proposal جدید
     * @param title عنوان
     * @param description شرح
     * @param proposalType نوع proposal
     * @param targets آرایه آدرس‌های مقصد
     * @param values آرایه مقادیر ETH
     * @param signatures آرایه امضاهای تابع
     * @param calldatas آرایه داده‌های تراکنش
     */
    function propose(
        string calldata title,
        string calldata description,
        Proposal.ProposalType proposalType,
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas
    ) external nonReentrant notPaused hasVotingPower(msg.sender, proposalThreshold) returns (uint256 proposalId) {
        // Anti-spam checks
        if (block.number < lastProposalBlock[msg.sender] + (MIN_PROPOSAL_INTERVAL / 12)) { // ~12 sec per block
            revert ProposalIntervalNotMet();
        }
        
        if (userProposalCount[msg.sender] >= MAX_PROPOSALS_PER_USER) {
            revert TooManyProposals();
        }
        
        // Create proposal
        proposalId = proposalContract.createProposal(
            title,
            description,
            proposalType,
            targets,
            values,
            signatures,
            calldatas
        );
        
        // Update stats
        userProposalCount[msg.sender]++;
        userProposals[msg.sender].push(proposalId);
        lastProposalBlock[msg.sender] = block.number;
        
        voterStats[msg.sender].proposalsCreated++;
        voterStats[msg.sender].reputationScore += REPUTATION_PROPOSAL_BONUS;
        
        governanceStats.totalProposals++;
        governanceStats.activeProposals++;
        governanceStats.lastActivity = block.timestamp;
        
        emit ProposalSubmitted(proposalId, msg.sender, title, proposalType);
    }

    /**
     * @dev رای دادن به proposal
     * @param proposalId شناسه proposal
     * @param support نوع رای
     * @param reason دلیل رای
     */
    function castVote(
        uint256 proposalId,
        Proposal.VoteType support,
        string calldata reason
    ) external nonReentrant notPaused {
        uint256 weight = _getVotingPower(msg.sender);
        if (weight == 0) revert InsufficientVotingPower();
        
        // Cast vote in proposal contract
        proposalContract.castVote(proposalId, support, reason);
        
        // Update stats
        voterStats[msg.sender].proposalsVoted++;
        voterStats[msg.sender].totalVotingPower = weight;
        voterStats[msg.sender].lastVoteTime = block.timestamp;
        voterStats[msg.sender].reputationScore += REPUTATION_VOTE_BONUS;
        
        governanceStats.totalVotes++;
        governanceStats.lastActivity = block.timestamp;
        
        emit VoteSubmitted(proposalId, msg.sender, support, weight);
    }

    /**
     * @dev اجرای proposal
     * @param proposalId شناسه proposal
     */
    function executeProposal(uint256 proposalId) external nonReentrant notPaused {
        // Update proposal state first
        proposalContract.updateProposalState(proposalId);
        
        // Queue in timelock if succeeded
        proposalContract.queueProposal(proposalId);
        
        // Execute from timelock
        proposalContract.executeProposal(proposalId);
        
        // Update stats
        proposalExecuted[proposalId] = true;
        governanceStats.executedProposals++;
        governanceStats.activeProposals--;
        governanceStats.lastActivity = block.timestamp;
        
        // Reward executor
        voterStats[msg.sender].reputationScore += REPUTATION_EXECUTION_BONUS;
        
        emit ProposalExecuted(proposalId, true);
    }

    /**
     * @dev تفویض قدرت رای
     * @param delegate آدرس delegate
     */
    function delegate(address delegate) external nonReentrant {
        address currentDelegate = delegations[msg.sender].delegate;
        if (currentDelegate == delegate) revert AlreadyDelegated();
        
        uint256 delegatorPower = votingToken.getVotingPower(msg.sender);
        
        // Remove old delegation
        if (currentDelegate != address(0)) {
            _removeDelegation(msg.sender, currentDelegate);
        }
        
        // Add new delegation
        if (delegate != address(0)) {
            delegations[msg.sender] = DelegationInfo({
                delegate: delegate,
                delegatedPower: delegatorPower,
                delegationTime: block.timestamp,
                active: true
            });
            
            delegators[delegate].push(msg.sender);
            voterStats[delegate].isDelegate = true;
        } else {
            // Self-delegation (remove delegation)
            delegations[msg.sender].active = false;
        }
        
        emit DelegationChanged(msg.sender, currentDelegate, delegate, delegatorPower);
    }

    /**
     * @dev ایجاد emergency proposal
     * @param title عنوان
     * @param description شرح
     * @param targets آرایه آدرس‌های مقصد
     * @param values آرایه مقادیر ETH
     * @param signatures آرایه امضاهای تابع
     * @param calldatas آرایه داده‌های تراکنش
     */
    function createEmergencyProposal(
        string calldata title,
        string calldata description,
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas
    ) external onlyGuardian returns (uint256 proposalId) {
        proposalId = proposalContract.createProposal(
            title,
            description,
            Proposal.ProposalType.Emergency,
            targets,
            values,
            signatures,
            calldatas
        );
        
        bytes32 proposalHash = keccak256(abi.encode(proposalId, block.timestamp));
        emergencyProposals[proposalHash] = block.timestamp + emergencyDelay;
        
        governanceStats.totalProposals++;
        governanceStats.activeProposals++;
        
        emit ProposalSubmitted(proposalId, msg.sender, title, Proposal.ProposalType.Emergency);
    }

    /**
     * @dev تنظیم پارامترهای governance
     * @param parameter نام پارامتر
     * @param value مقدار جدید
     */
    function setGovernanceParameter(
        string calldata parameter,
        uint256 value
    ) external {
        // این تابع باید فقط از طریق governance قابل فراخوانی باشد
        require(msg.sender == address(this), "Only governance can set parameters");
        
        bytes32 paramHash = keccak256(abi.encodePacked(parameter));
        uint256 oldValue;
        
        if (paramHash == keccak256(abi.encodePacked("proposalThreshold"))) {
            oldValue = proposalThreshold;
            if (value < 1000 * 10**18 || value > 100000 * 10**18) revert InvalidParameter();
            proposalThreshold = value;
        } else if (paramHash == keccak256(abi.encodePacked("quorumPercentage"))) {
            oldValue = quorumPercentage;
            if (value < 500 || value > 3000) revert InvalidParameter(); // 5%-30%
            quorumPercentage = value;
        } else if (paramHash == keccak256(abi.encodePacked("votingDelay"))) {
            oldValue = votingDelay;
            if (value < 1 hours || value > 7 days) revert InvalidParameter();
            votingDelay = value;
        } else if (paramHash == keccak256(abi.encodePacked("votingPeriod"))) {
            oldValue = votingPeriod;
            if (value < 1 days || value > 30 days) revert InvalidParameter();
            votingPeriod = value;
        } else if (paramHash == keccak256(abi.encodePacked("timelockDelay"))) {
            oldValue = timelockDelay;
            if (value < 1 hours || value > 30 days) revert InvalidParameter();
            timelockDelay = value;
        } else {
            revert InvalidParameter();
        }
        
        emit GovernanceParameterChanged(parameter, oldValue, value);
    }

    /**
     * @dev فعال/غیرفعال emergency pause
     * @param paused وضعیت
     */
    function setEmergencyPaused(bool paused) external onlyGuardian {
        emergencyPaused = paused;
        
        emit EmergencyActionTaken(msg.sender, "setEmergencyPaused", abi.encodePacked(paused));
    }

    /**
     * @dev تنظیم guardian جدید
     * @param newGuardian guardian جدید
     */
    function setGuardian(address newGuardian) external {
        require(msg.sender == address(this), "Only governance can set guardian");
        guardian = newGuardian;
    }

    /**
     * @dev به‌روزرسانی reputation scores
     */
    function updateReputationScores() external {
        // کاهش امتیاز reputation بر اساس زمان (decay)
        uint256 monthsSinceLastActivity = (block.timestamp - governanceStats.lastActivity) / 30 days;
        
        if (monthsSinceLastActivity > 0) {
            // این تابع باید برای همه کاربران اجرا شود
            // فعلاً ساده‌سازی شده است
            governanceStats.lastActivity = block.timestamp;
        }
    }

    /**
     * @dev دریافت قدرت رای کاربر
     * @param account آدرس کاربر
     * @return power قدرت رای
     */
    function getVotingPower(address account) external view returns (uint256 power) {
        return _getVotingPower(account);
    }

    /**
     * @dev دریافت آمار کاربر
     * @param account آدرس کاربر
     */
    function getVoterStats(address account) external view returns (
        uint256 proposalsVoted,
        uint256 proposalsCreated,
        uint256 totalVotingPower,
        uint256 lastVoteTime,
        uint256 reputationScore,
        bool isDelegate
    ) {
        VoterStats storage stats = voterStats[account];
        return (
            stats.proposalsVoted,
            stats.proposalsCreated,
            stats.totalVotingPower,
            stats.lastVoteTime,
            stats.reputationScore,
            stats.isDelegate
        );
    }

    /**
     * @dev دریافت اطلاعات تفویض
     * @param account آدرس کاربر
     */
    function getDelegationInfo(address account) external view returns (
        address delegate,
        uint256 delegatedPower,
        uint256 delegationTime,
        bool active
    ) {
        DelegationInfo storage info = delegations[account];
        return (info.delegate, info.delegatedPower, info.delegationTime, info.active);
    }

    /**
     * @dev دریافت لیست delegators
     * @param delegate آدرس delegate
     * @return delegatorsList لیست delegators
     */
    function getDelegators(address delegate) external view returns (address[] memory delegatorsList) {
        return delegators[delegate];
    }

    /**
     * @dev دریافت proposals کاربر
     * @param account آدرس کاربر
     * @return proposalsList لیست proposal IDs
     */
    function getUserProposals(address account) external view returns (uint256[] memory proposalsList) {
        return userProposals[account];
    }

    /**
     * @dev محاسبه قدرت رای داخلی
     */
    function _getVotingPower(address account) internal view returns (uint256 power) {
        // قدرت رای شخصی
        power = votingToken.getVotingPower(account);
        
        // اضافه کردن قدرت تفویض شده
        address[] memory accountDelegators = delegators[account];
        for (uint256 i = 0; i < accountDelegators.length; i++) {
            if (delegations[accountDelegators[i]].active) {
                power += delegations[accountDelegators[i]].delegatedPower;
            }
        }
    }

    /**
     * @dev حذف تفویض
     */
    function _removeDelegation(address delegator, address delegate) internal {
        delegations[delegator].active = false;
        
        // Remove from delegators list
        address[] storage delegatorsList = delegators[delegate];
        for (uint256 i = 0; i < delegatorsList.length; i++) {
            if (delegatorsList[i] == delegator) {
                delegatorsList[i] = delegatorsList[delegatorsList.length - 1];
                delegatorsList.pop();
                break;
            }
        }
        
        // Check if delegate still has delegators
        if (delegatorsList.length == 0) {
            voterStats[delegate].isDelegate = false;
        }
    }

    /**
     * @dev محاسبه سلامت governance
     * @return healthScore امتیاز سلامت (0-100)
     */
    function getGovernanceHealth() external view returns (uint256 healthScore) {
        uint256 participationRate = governanceStats.totalVoters * 100 / votingToken.totalSupply();
        uint256 activityScore = governanceStats.totalProposals > 0 ? 
            (governanceStats.executedProposals * 100 / governanceStats.totalProposals) : 0;
        
        healthScore = (participationRate + activityScore) / 2;
        if (healthScore > 100) healthScore = 100;
    }
}