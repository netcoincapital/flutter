// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Constants.sol";

/**
 * @title Treasury
 * @dev خزانه مرکزی DAO
 */
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Allocation {
        uint256 amount;             // مقدار تخصیص یافته
        uint256 spent;              // مقدار خرج شده
        uint256 deadline;           // deadline برای استفاده
        string purpose;             // هدف تخصیص
        bool active;                // فعال/غیرفعال
        address allocatedTo;        // تخصیص یافته به کی
    }

    struct Budget {
        uint256 totalBudget;        // کل بودجه
        uint256 spentAmount;        // مقدار خرج شده
        uint256 period;             // دوره بودجه (ثانیه)
        uint256 startTime;          // شروع دوره
        mapping(string => uint256) categoryBudgets; // بودجه هر دسته
        mapping(string => uint256) categorySpent;   // خرج شده هر دسته
    }

    struct Investment {
        address asset;              // آدرس asset
        uint256 amount;             // مقدار سرمایه‌گذاری
        uint256 investmentTime;     // زمان سرمایه‌گذاری
        uint256 expectedReturn;     // بازده مورد انتظار
        string strategy;            // استراتژی سرمایه‌گذاری
        bool active;                // فعال/غیرفعال
    }

    // Events
    event FundsReceived(address indexed from, address indexed token, uint256 amount, string source);
    event FundsAllocated(address indexed to, address indexed token, uint256 amount, string purpose);
    event FundsSpent(address indexed by, address indexed token, uint256 amount, string purpose);
    event BudgetSet(string indexed category, uint256 amount, uint256 period);
    event InvestmentMade(address indexed asset, uint256 amount, string strategy);
    event InvestmentReturned(address indexed asset, uint256 amount, uint256 profit);
    event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed to);

    // State variables
    mapping(address => uint256) public tokenBalances;           // موجودی هر token
    mapping(uint256 => Allocation) public allocations;          // تخصیص‌ها
    mapping(string => Budget) public budgets;                   // بودجه‌های دسته‌بندی شده
    mapping(uint256 => Investment) public investments;          // سرمایه‌گذاری‌ها
    mapping(address => bool) public authorizedSpenders;         // مجاز به خرج کردن
    mapping(address => bool) public authorizedAllocators;       // مجاز به تخصیص
    mapping(address => bool) public investmentManagers;         // مدیران سرمایه‌گذاری

    uint256 public totalAllocations = 0;
    uint256 public totalInvestments = 0;
    uint256 public emergencyReservePercentage = 1000; // 10% برای emergency
    
    // Investment limits
    uint256 public maxSingleInvestment = 1000000 * 10**18;     // حداکثر سرمایه‌گذاری واحد
    uint256 public maxTotalInvestmentPercentage = 3000;        // حداکثر 30% کل treasury برای investment
    
    // Budget categories
    string[] public budgetCategories = [
        "development",
        "marketing", 
        "operations",
        "partnerships",
        "research",
        "community",
        "security",
        "emergency"
    ];

    // Multisig settings
    uint256 public requiredSignatures = 3;
    uint256 public totalSigners = 5;
    mapping(address => bool) public isMultisigSigner;
    mapping(bytes32 => uint256) public transactionConfirmations;
    mapping(bytes32 => mapping(address => bool)) public hasConfirmed;

    error UnauthorizedSpender();
    error UnauthorizedAllocator();
    error UnauthorizedInvestmentManager();
    error InsufficientBalance();
    error AllocationExpired();
    error BudgetExceeded();
    error InvalidInvestment();
    error InsufficientSignatures();
    error AlreadyConfirmed();
    error InvalidCategory();

    modifier onlyAuthorizedSpender() {
        if (!authorizedSpenders[msg.sender] && msg.sender != owner()) revert UnauthorizedSpender();
        _;
    }

    modifier onlyAuthorizedAllocator() {
        if (!authorizedAllocators[msg.sender] && msg.sender != owner()) revert UnauthorizedAllocator();
        _;
    }

    modifier onlyInvestmentManager() {
        if (!investmentManagers[msg.sender] && msg.sender != owner()) revert UnauthorizedInvestmentManager();
        _;
    }

    modifier validCategory(string memory category) {
        bool found = false;
        for (uint i = 0; i < budgetCategories.length; i++) {
            if (keccak256(abi.encodePacked(budgetCategories[i])) == keccak256(abi.encodePacked(category))) {
                found = true;
                break;
            }
        }
        if (!found) revert InvalidCategory();
        _;
    }

    constructor() Ownable(msg.sender) {
        authorizedSpenders[msg.sender] = true;
        authorizedAllocators[msg.sender] = true;
        investmentManagers[msg.sender] = true;
        isMultisigSigner[msg.sender] = true;
    }

    /**
     * @dev دریافت funds از protocol fees
     * @param token آدرس token
     * @param amount مقدار
     * @param source منبع دریافت
     */
    function receiveFunds(
        address token,
        uint256 amount,
        string calldata source
    ) external nonReentrant {
        if (amount == 0) revert InsufficientBalance();
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        tokenBalances[token] += amount;
        
        emit FundsReceived(msg.sender, token, amount, source);
    }

    /**
     * @dev تخصیص funds برای مقاصد خاص
     * @param to آدرس مقصد
     * @param token آدرس token
     * @param amount مقدار
     * @param purpose هدف
     * @param deadline deadline
     */
    function allocateFunds(
        address to,
        address token,
        uint256 amount,
        string calldata purpose,
        uint256 deadline
    ) external onlyAuthorizedAllocator nonReentrant {
        if (tokenBalances[token] < amount) revert InsufficientBalance();
        if (deadline <= block.timestamp) revert AllocationExpired();
        
        uint256 allocationId = totalAllocations++;
        allocations[allocationId] = Allocation({
            amount: amount,
            spent: 0,
            deadline: deadline,
            purpose: purpose,
            active: true,
            allocatedTo: to
        });
        
        tokenBalances[token] -= amount;
        
        emit FundsAllocated(to, token, amount, purpose);
    }

    /**
     * @dev خرج کردن از allocation
     * @param allocationId شناسه allocation
     * @param token آدرس token
     * @param amount مقدار
     * @param recipient آدرس دریافت کننده
     */
    function spendFromAllocation(
        uint256 allocationId,
        address token,
        uint256 amount,
        address recipient
    ) external onlyAuthorizedSpender nonReentrant {
        Allocation storage allocation = allocations[allocationId];
        
        if (!allocation.active) revert AllocationExpired();
        if (block.timestamp > allocation.deadline) revert AllocationExpired();
        if (allocation.spent + amount > allocation.amount) revert InsufficientBalance();
        if (allocation.allocatedTo != msg.sender && msg.sender != owner()) revert UnauthorizedSpender();
        
        allocation.spent += amount;
        IERC20(token).safeTransfer(recipient, amount);
        
        emit FundsSpent(msg.sender, token, amount, allocation.purpose);
    }

    /**
     * @dev تنظیم بودجه برای دسته
     * @param category دسته
     * @param amount مقدار بودجه
     * @param period دوره (ثانیه)
     */
    function setBudget(
        string calldata category,
        uint256 amount,
        uint256 period
    ) external onlyOwner validCategory(category) {
        Budget storage budget = budgets[category];
        
        // اگر دوره جدید است، reset کن
        if (block.timestamp >= budget.startTime + budget.period) {
            budget.spentAmount = 0;
            budget.categorySpent[category] = 0;
        }
        
        budget.totalBudget = amount;
        budget.period = period;
        budget.startTime = block.timestamp;
        budget.categoryBudgets[category] = amount;
        
        emit BudgetSet(category, amount, period);
    }

    /**
     * @dev خرج کردن از بودجه دسته
     * @param category دسته
     * @param token آدرس token
     * @param amount مقدار
     * @param recipient دریافت کننده
     * @param purpose هدف
     */
    function spendFromBudget(
        string calldata category,
        address token,
        uint256 amount,
        address recipient,
        string calldata purpose
    ) external onlyAuthorizedSpender nonReentrant validCategory(category) {
        Budget storage budget = budgets[category];
        
        // بررسی budget period
        if (block.timestamp >= budget.startTime + budget.period) revert BudgetExceeded();
        
        // بررسی budget limit
        if (budget.categorySpent[category] + amount > budget.categoryBudgets[category]) {
            revert BudgetExceeded();
        }
        
        if (tokenBalances[token] < amount) revert InsufficientBalance();
        
        budget.categorySpent[category] += amount;
        budget.spentAmount += amount;
        tokenBalances[token] -= amount;
        
        IERC20(token).safeTransfer(recipient, amount);
        
        emit FundsSpent(msg.sender, token, amount, purpose);
    }

    /**
     * @dev سرمایه‌گذاری در assets
     * @param asset آدرس asset
     * @param amount مقدار
     * @param expectedReturn بازده مورد انتظار
     * @param strategy استراتژی
     */
    function makeInvestment(
        address asset,
        uint256 amount,
        uint256 expectedReturn,
        string calldata strategy
    ) external onlyInvestmentManager nonReentrant {
        if (amount > maxSingleInvestment) revert InvalidInvestment();
        if (tokenBalances[asset] < amount) revert InsufficientBalance();
        
        // بررسی کل investment limit
        uint256 totalTreasuryValue = _calculateTotalTreasuryValue();
        uint256 currentInvestments = _calculateTotalInvestments();
        if ((currentInvestments + amount) * Constants.BASIS_POINTS > totalTreasuryValue * maxTotalInvestmentPercentage) {
            revert InvalidInvestment();
        }
        
        uint256 investmentId = totalInvestments++;
        investments[investmentId] = Investment({
            asset: asset,
            amount: amount,
            investmentTime: block.timestamp,
            expectedReturn: expectedReturn,
            strategy: strategy,
            active: true
        });
        
        tokenBalances[asset] -= amount;
        
        // TODO: Transfer to investment contract/strategy
        
        emit InvestmentMade(asset, amount, strategy);
    }

    /**
     * @dev بازگرداندن سرمایه‌گذاری
     * @param investmentId شناسه سرمایه‌گذاری
     * @param returnAmount مقدار برگشتی
     */
    function returnInvestment(
        uint256 investmentId,
        uint256 returnAmount
    ) external onlyInvestmentManager nonReentrant {
        Investment storage investment = investments[investmentId];
        
        if (!investment.active) revert InvalidInvestment();
        
        investment.active = false;
        tokenBalances[investment.asset] += returnAmount;
        
        uint256 profit = returnAmount > investment.amount ? returnAmount - investment.amount : 0;
        
        emit InvestmentReturned(investment.asset, returnAmount, profit);
    }

    /**
     * @dev Emergency withdrawal (نیاز به multisig)
     * @param token آدرس token
     * @param amount مقدار
     * @param to آدرس مقصد
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external nonReentrant {
        bytes32 txHash = keccak256(abi.encodePacked(token, amount, to, block.timestamp));
        
        if (!hasConfirmed[txHash][msg.sender]) {
            hasConfirmed[txHash][msg.sender] = true;
            transactionConfirmations[txHash]++;
        } else {
            revert AlreadyConfirmed();
        }
        
        if (transactionConfirmations[txHash] >= requiredSignatures) {
            if (tokenBalances[token] < amount) revert InsufficientBalance();
            
            tokenBalances[token] -= amount;
            IERC20(token).safeTransfer(to, amount);
            
            emit EmergencyWithdrawal(token, amount, to);
        }
    }

    /**
     * @dev اضافه کردن authorized spender
     * @param spender آدرس spender
     */
    function addAuthorizedSpender(address spender) external onlyOwner {
        authorizedSpenders[spender] = true;
    }

    /**
     * @dev اضافه کردن authorized allocator
     * @param allocator آدرس allocator
     */
    function addAuthorizedAllocator(address allocator) external onlyOwner {
        authorizedAllocators[allocator] = true;
    }

    /**
     * @dev اضافه کردن investment manager
     * @param manager آدرس manager
     */
    function addInvestmentManager(address manager) external onlyOwner {
        investmentManagers[manager] = true;
    }

    /**
     * @dev تنظیم emergency reserve percentage
     * @param percentage درصد جدید
     */
    function setEmergencyReservePercentage(uint256 percentage) external onlyOwner {
        require(percentage <= 2000, "Too high"); // حداکثر 20%
        emergencyReservePercentage = percentage;
    }

    /**
     * @dev تنظیم multisig settings
     * @param required تعداد required signatures
     * @param total کل signers
     */
    function setMultisigSettings(uint256 required, uint256 total) external onlyOwner {
        require(required <= total && required > 0, "Invalid settings");
        requiredSignatures = required;
        totalSigners = total;
    }

    /**
     * @dev دریافت موجودی token
     * @param token آدرس token
     * @return balance موجودی
     */
    function getTokenBalance(address token) external view returns (uint256 balance) {
        return tokenBalances[token];
    }

    /**
     * @dev دریافت budget info
     * @param category دسته
     */
    function getBudgetInfo(string calldata category) external view returns (
        uint256 totalBudget,
        uint256 spentAmount,
        uint256 remainingAmount,
        uint256 periodEnd
    ) {
        Budget storage budget = budgets[category];
        totalBudget = budget.categoryBudgets[category];
        spentAmount = budget.categorySpent[category];
        remainingAmount = totalBudget > spentAmount ? totalBudget - spentAmount : 0;
        periodEnd = budget.startTime + budget.period;
    }

    /**
     * @dev محاسبه کل ارزش treasury
     */
    function _calculateTotalTreasuryValue() internal view returns (uint256 total) {
        // ساده‌سازی: فرض می‌کنیم همه tokens ارزش یکسان دارند
        // در واقعیت باید از oracle استفاده کرد
        
        // فعلاً مجموع موجودی‌ها را برمی‌گرداند
        // TODO: پیاده‌سازی ارزش‌گذاری واقعی با oracle
        return 1000000 * 10**18; // مقدار فرضی
    }

    /**
     * @dev محاسبه کل سرمایه‌گذاری‌ها
     */
    function _calculateTotalInvestments() internal view returns (uint256 total) {
        for (uint256 i = 0; i < totalInvestments; i++) {
            if (investments[i].active) {
                total += investments[i].amount;
            }
        }
    }
}