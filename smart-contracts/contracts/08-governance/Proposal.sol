// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Constants.sol";

/**
 * @title Proposal
 * @dev مدیریت proposals در DAO
 */
contract Proposal is Ownable, ReentrancyGuard {

    enum ProposalState {
        Pending,        // در انتظار شروع voting
        Active,         // voting فعال
        Canceled,       // لغو شده
        Defeated,       // رد شده
        Succeeded,      // تصویب شده
        Queued,         // در صف اجرا
        Expired,        // منقضی شده
        Executed        // اجرا شده
    }

    enum ProposalType {
        Standard,       // پیشنهاد استاندارد
        Constitutional, // تغییر قانون اساسی
        Emergency,      // اضطراری
        Treasury,       // مربوط به treasury
        Technical,      // تغییرات فنی
        Partnership     // شراکت‌ها
    }

    enum VoteType {
        Against,        // مخالف
        For,           // موافق
        Abstain        // ممتنع
    }

    struct ProposalCore {
        uint256 id;                     // شناسه proposal
        address proposer;               // پیشنهاد دهنده
        string title;                   // عنوان
        string description;             // شرح
        ProposalType proposalType;      // نوع proposal
        ProposalState state;            // وضعیت
        uint256 startTime;              // شروع voting
        uint256 endTime;                // پایان voting
        uint256 executionTime;          // زمان اجرا
        uint256 quorumVotes;            // حد نصاب
        uint256 threshold;              // آستانه تصویب
    }

    struct ProposalVotes {
        uint256 forVotes;               // آرای موافق
        uint256 againstVotes;           // آرای مخالف
        uint256 abstainVotes;           // آرای ممتنع
        uint256 totalVotes;             // کل آرا
        mapping(address => VoteReceipt) receipts; // رسیدهای رای
    }

    struct VoteReceipt {
        bool hasVoted;                  // آیا رای داده
        VoteType support;               // نوع رای
        uint256 votes;                  // تعداد آرا
        uint256 weight;                 // وزن آرا
        uint256 timestamp;              // زمان رای
    }

    struct ProposalAction {
        address target;                 // آدرس مقصد
        uint256 value;                  // مقدار ETH
        bytes data;                     // داده تراکنش
        string signature;               // امضای تابع
        bool executed;                  // آیا اجرا شده
    }

    struct ProposalConfig {
        uint256 votingDelay;            // تاخیر شروع voting
        uint256 votingPeriod;           // مدت voting
        uint256 proposalThreshold;      // حد آستانه پیشنهاد
        uint256 quorumPercentage;       // درصد نصاب
        uint256 timelockDelay;          // تاخیر timelock
    }

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        ProposalType proposalType,
        uint256 startTime,
        uint256 endTime
    );

    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        VoteType support,
        uint256 weight,
        string reason
    );

    event ProposalCanceled(uint256 indexed proposalId, string reason);
    event ProposalQueued(uint256 indexed proposalId, uint256 executionTime);
    event ProposalExecuted(uint256 indexed proposalId, bool success);
    event ProposalStateChanged(uint256 indexed proposalId, ProposalState oldState, ProposalState newState);

    // State variables
    mapping(uint256 => ProposalCore) public proposals;
    mapping(uint256 => ProposalVotes) private proposalVotes;
    mapping(uint256 => ProposalAction[]) public proposalActions;
    mapping(ProposalType => ProposalConfig) public proposalConfigs;
    mapping(address => uint256) public lastProposalTime;
    mapping(address => bool) public proposalCreators;
    
    uint256 public proposalCount = 0;
    uint256 public constant MAX_ACTIONS = 10;           // حداکثر تعداد actions
    uint256 public constant MIN_PROPOSAL_INTERVAL = 7 days;  // حداقل فاصله بین proposals
    uint256 public constant MAX_DESCRIPTION_LENGTH = 5000;   // حداکثر طول توضیحات
    
    // Voting power interface
    address public votingToken;
    address public timelock;
    
    // Emergency settings
    bool public emergencyPaused = false;
    address public guardian;

    error ProposalNotFound();
    error InvalidProposalState();
    error UnauthorizedProposer();
    error ProposalIntervalNotMet();
    error VotingNotActive();
    error AlreadyVoted();
    error InsufficientVotingPower();
    error ExecutionFailed();
    error EmergencyPaused();
    error InvalidConfig();

    modifier proposalExists(uint256 proposalId) {
        if (proposalId >= proposalCount) revert ProposalNotFound();
        _;
    }

    modifier onlyActiveProposal(uint256 proposalId) {
        if (proposals[proposalId].state != ProposalState.Active) revert VotingNotActive();
        _;
    }

    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPaused();
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian || msg.sender == owner(), "Not guardian");
        _;
    }

    constructor(address _votingToken, address _timelock, address _guardian) Ownable(msg.sender) {
        votingToken = _votingToken;
        timelock = _timelock;
        guardian = _guardian;
        
        proposalCreators[msg.sender] = true;
        _initializeConfigs();
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
    function createProposal(
        string calldata title,
        string calldata description,
        ProposalType proposalType,
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas
    ) external nonReentrant notPaused returns (uint256 proposalId) {
        // بررسی مجوز
        if (!proposalCreators[msg.sender] && msg.sender != owner()) revert UnauthorizedProposer();
        
        // بررسی interval
        if (block.timestamp < lastProposalTime[msg.sender] + MIN_PROPOSAL_INTERVAL) {
            revert ProposalIntervalNotMet();
        }
        
        // بررسی طول آرایه‌ها
        require(targets.length == values.length && 
                targets.length == signatures.length && 
                targets.length == calldatas.length, "Array length mismatch");
        require(targets.length <= MAX_ACTIONS, "Too many actions");
        require(bytes(description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        
        // بررسی voting power
        uint256 proposerVotes = _getVotingPower(msg.sender);
        ProposalConfig storage config = proposalConfigs[proposalType];
        if (proposerVotes < config.proposalThreshold) revert InsufficientVotingPower();
        
        proposalId = proposalCount++;
        
        // ایجاد proposal
        uint256 startTime = block.timestamp + config.votingDelay;
        uint256 endTime = startTime + config.votingPeriod;
        
        proposals[proposalId] = ProposalCore({
            id: proposalId,
            proposer: msg.sender,
            title: title,
            description: description,
            proposalType: proposalType,
            state: ProposalState.Pending,
            startTime: startTime,
            endTime: endTime,
            executionTime: 0,
            quorumVotes: (_getTotalVotingPower() * config.quorumPercentage) / Constants.BASIS_POINTS,
            threshold: 5000 // 50% threshold
        });
        
        // ذخیره actions
        for (uint256 i = 0; i < targets.length; i++) {
            proposalActions[proposalId].push(ProposalAction({
                target: targets[i],
                value: values[i],
                data: calldatas[i],
                signature: signatures[i],
                executed: false
            }));
        }
        
        lastProposalTime[msg.sender] = block.timestamp;
        
        emit ProposalCreated(proposalId, msg.sender, title, proposalType, startTime, endTime);
    }

    /**
     * @dev رای دادن به proposal
     * @param proposalId شناسه proposal
     * @param support نوع رای
     * @param reason دلیل رای
     */
    function castVote(
        uint256 proposalId,
        VoteType support,
        string calldata reason
    ) external nonReentrant proposalExists(proposalId) notPaused {
        _castVote(msg.sender, proposalId, support, reason);
    }

    /**
     * @dev رای دادن با امضا
     * @param proposalId شناسه proposal
     * @param support نوع رای
     * @param voter آدرس رای دهنده
     * @param signature امضا
     */
    function castVoteWithSignature(
        uint256 proposalId,
        VoteType support,
        address voter,
        bytes calldata signature
    ) external nonReentrant proposalExists(proposalId) notPaused {
        // TODO: پیاده‌سازی signature verification
        _castVote(voter, proposalId, support, "");
    }

    /**
     * @dev به‌روزرسانی state proposal
     * @param proposalId شناسه proposal
     */
    function updateProposalState(uint256 proposalId) external proposalExists(proposalId) {
        ProposalCore storage proposal = proposals[proposalId];
        ProposalState oldState = proposal.state;
        ProposalState newState = _calculateState(proposalId);
        
        if (oldState != newState) {
            proposal.state = newState;
            emit ProposalStateChanged(proposalId, oldState, newState);
        }
    }

    /**
     * @dev قرار دادن proposal در صف اجرا
     * @param proposalId شناسه proposal
     */
    function queueProposal(uint256 proposalId) external proposalExists(proposalId) {
        ProposalCore storage proposal = proposals[proposalId];
        
        require(proposal.state == ProposalState.Succeeded, "Proposal not succeeded");
        
        ProposalConfig storage config = proposalConfigs[proposal.proposalType];
        proposal.executionTime = block.timestamp + config.timelockDelay;
        proposal.state = ProposalState.Queued;
        
        emit ProposalQueued(proposalId, proposal.executionTime);
    }

    /**
     * @dev اجرای proposal
     * @param proposalId شناسه proposal
     */
    function executeProposal(uint256 proposalId) external payable nonReentrant proposalExists(proposalId) {
        ProposalCore storage proposal = proposals[proposalId];
        
        require(proposal.state == ProposalState.Queued, "Proposal not queued");
        require(block.timestamp >= proposal.executionTime, "Execution time not reached");
        
        proposal.state = ProposalState.Executed;
        
        bool success = true;
        ProposalAction[] storage actions = proposalActions[proposalId];
        
        for (uint256 i = 0; i < actions.length; i++) {
            ProposalAction storage action = actions[i];
            
            if (!action.executed) {
                bytes memory callData;
                
                if (bytes(action.signature).length > 0) {
                    callData = abi.encodePacked(bytes4(keccak256(bytes(action.signature))), action.data);
                } else {
                    callData = action.data;
                }
                
                (bool actionSuccess,) = action.target.call{value: action.value}(callData);
                action.executed = actionSuccess;
                
                if (!actionSuccess) {
                    success = false;
                }
            }
        }
        
        emit ProposalExecuted(proposalId, success);
    }

    /**
     * @dev لغو proposal
     * @param proposalId شناسه proposal
     * @param reason دلیل لغو
     */
    function cancelProposal(uint256 proposalId, string calldata reason) external proposalExists(proposalId) {
        ProposalCore storage proposal = proposals[proposalId];
        
        require(msg.sender == proposal.proposer || msg.sender == owner() || msg.sender == guardian, "Not authorized");
        require(proposal.state == ProposalState.Pending || proposal.state == ProposalState.Active, "Cannot cancel");
        
        proposal.state = ProposalState.Canceled;
        
        emit ProposalCanceled(proposalId, reason);
    }

    /**
     * @dev دریافت اطلاعات proposal
     * @param proposalId شناسه proposal
     */
    function getProposal(uint256 proposalId) external view proposalExists(proposalId) returns (
        address proposer,
        string memory title,
        string memory description,
        ProposalType proposalType,
        ProposalState state,
        uint256 startTime,
        uint256 endTime,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    ) {
        ProposalCore storage proposal = proposals[proposalId];
        ProposalVotes storage votes = proposalVotes[proposalId];
        
        return (
            proposal.proposer,
            proposal.title,
            proposal.description,
            proposal.proposalType,
            proposal.state,
            proposal.startTime,
            proposal.endTime,
            votes.forVotes,
            votes.againstVotes,
            votes.abstainVotes
        );
    }

    /**
     * @dev دریافت actions proposal
     * @param proposalId شناسه proposal
     */
    function getProposalActions(uint256 proposalId) external view proposalExists(proposalId) returns (
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) {
        ProposalAction[] storage actions = proposalActions[proposalId];
        
        targets = new address[](actions.length);
        values = new uint256[](actions.length);
        signatures = new string[](actions.length);
        calldatas = new bytes[](actions.length);
        
        for (uint256 i = 0; i < actions.length; i++) {
            targets[i] = actions[i].target;
            values[i] = actions[i].value;
            signatures[i] = actions[i].signature;
            calldatas[i] = actions[i].data;
        }
    }

    /**
     * @dev دریافت رسید رای
     * @param proposalId شناسه proposal
     * @param voter آدرس رای دهنده
     */
    function getVoteReceipt(uint256 proposalId, address voter) external view proposalExists(proposalId) returns (
        bool hasVoted,
        VoteType support,
        uint256 votes,
        uint256 weight
    ) {
        VoteReceipt storage receipt = proposalVotes[proposalId].receipts[voter];
        return (receipt.hasVoted, receipt.support, receipt.votes, receipt.weight);
    }

    /**
     * @dev تنظیم config برای نوع proposal
     * @param proposalType نوع proposal
     * @param config تنظیمات جدید
     */
    function setProposalConfig(ProposalType proposalType, ProposalConfig calldata config) external onlyOwner {
        if (config.votingPeriod < 1 days || config.votingPeriod > 30 days) revert InvalidConfig();
        if (config.quorumPercentage > 5000) revert InvalidConfig(); // حداکثر 50%
        
        proposalConfigs[proposalType] = config;
    }

    /**
     * @dev اضافه کردن proposal creator
     * @param creator آدرس creator
     */
    function addProposalCreator(address creator) external onlyOwner {
        proposalCreators[creator] = true;
    }

    /**
     * @dev فعال/غیرفعال emergency pause
     * @param paused وضعیت
     */
    function setEmergencyPaused(bool paused) external onlyGuardian {
        emergencyPaused = paused;
    }

    /**
     * @dev رای دادن داخلی
     */
    function _castVote(address voter, uint256 proposalId, VoteType support, string memory reason) internal {
        ProposalCore storage proposal = proposals[proposalId];
        
        // بررسی timing
        if (block.timestamp < proposal.startTime || block.timestamp > proposal.endTime) revert VotingNotActive();
        
        // به‌روزرسانی state
        proposal.state = ProposalState.Active;
        
        ProposalVotes storage votes = proposalVotes[proposalId];
        VoteReceipt storage receipt = votes.receipts[voter];
        
        if (receipt.hasVoted) revert AlreadyVoted();
        
        uint256 weight = _getVotingPower(voter);
        if (weight == 0) revert InsufficientVotingPower();
        
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = weight;
        receipt.weight = weight;
        receipt.timestamp = block.timestamp;
        
        if (support == VoteType.For) {
            votes.forVotes += weight;
        } else if (support == VoteType.Against) {
            votes.againstVotes += weight;
        } else {
            votes.abstainVotes += weight;
        }
        
        votes.totalVotes += weight;
        
        emit VoteCast(voter, proposalId, support, weight, reason);
    }

    /**
     * @dev محاسبه state proposal
     */
    function _calculateState(uint256 proposalId) internal view returns (ProposalState) {
        ProposalCore storage proposal = proposals[proposalId];
        
        if (proposal.state == ProposalState.Canceled) return ProposalState.Canceled;
        if (proposal.state == ProposalState.Executed) return ProposalState.Executed;
        if (proposal.state == ProposalState.Queued) {
            return block.timestamp >= proposal.executionTime + 14 days ? ProposalState.Expired : ProposalState.Queued;
        }
        
        if (block.timestamp < proposal.startTime) return ProposalState.Pending;
        if (block.timestamp <= proposal.endTime) return ProposalState.Active;
        
        ProposalVotes storage votes = proposalVotes[proposalId];
        
        // بررسی quorum
        if (votes.totalVotes < proposal.quorumVotes) return ProposalState.Defeated;
        
        // بررسی threshold
        if (votes.forVotes * Constants.BASIS_POINTS > votes.totalVotes * proposal.threshold) {
            return ProposalState.Succeeded;
        }
        
        return ProposalState.Defeated;
    }

    /**
     * @dev دریافت voting power
     */
    function _getVotingPower(address account) internal view returns (uint256) {
        // TODO: پیاده‌سازی interface با VotingToken
        return 1000; // مقدار فرضی
    }

    /**
     * @dev دریافت کل voting power
     */
    function _getTotalVotingPower() internal view returns (uint256) {
        // TODO: پیاده‌سازی interface با VotingToken
        return 100000; // مقدار فرضی
    }

    /**
     * @dev مقداردهی تنظیمات پیش‌فرض
     */
    function _initializeConfigs() internal {
        // Standard proposals
        proposalConfigs[ProposalType.Standard] = ProposalConfig({
            votingDelay: 1 days,
            votingPeriod: 7 days,
            proposalThreshold: 1000,
            quorumPercentage: 1000, // 10%
            timelockDelay: 2 days
        });
        
        // Constitutional proposals
        proposalConfigs[ProposalType.Constitutional] = ProposalConfig({
            votingDelay: 3 days,
            votingPeriod: 14 days,
            proposalThreshold: 5000,
            quorumPercentage: 2000, // 20%
            timelockDelay: 7 days
        });
        
        // Emergency proposals
        proposalConfigs[ProposalType.Emergency] = ProposalConfig({
            votingDelay: 1 hours,
            votingPeriod: 3 days,
            proposalThreshold: 10000,
            quorumPercentage: 1500, // 15%
            timelockDelay: 6 hours
        });
    }
}