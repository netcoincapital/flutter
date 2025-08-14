// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Constants.sol";

/**
 * @title ProtocolFeeCollector
 * @dev جمع‌آوری و مدیریت protocol fees
 */
contract ProtocolFeeCollector is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct FeeData {
        uint256 totalCollected;     // کل fee جمع‌آوری شده
        uint256 treasuryShare;      // سهم treasury
        uint256 developmentShare;   // سهم development
        uint256 buybackShare;       // سهم buyback
        uint256 lastCollection;     // آخرین زمان جمع‌آوری
        uint256 totalWithdrawn;     // کل مقدار برداشت شده
    }

    struct AllocationConfig {
        uint256 treasuryPercentage;    // درصد treasury (basis points)
        uint256 developmentPercentage; // درصد development (basis points)
        uint256 buybackPercentage;     // درصد buyback (basis points)
        bool active;                   // فعال/غیرفعال
    }

    // Events
    event FeeCollected(
        address indexed token,
        uint256 amount,
        uint256 treasuryShare,
        uint256 developmentShare,
        uint256 buybackShare
    );

    event FeeWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount,
        string purpose
    );

    event AllocationUpdated(
        uint256 treasuryPercentage,
        uint256 developmentPercentage,
        uint256 buybackPercentage
    );

    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);

    // State variables
    mapping(address => FeeData) public feeData;
    AllocationConfig public allocationConfig;
    
    address public treasury;           // آدرس treasury اصلی (Governance Layer)
    address public developmentFund;    // آدرس صندوق توسعه
    address public buybackContract;    // آدرس contract buyback
    
    // مجوزهای withdrawal
    mapping(address => bool) public authorizedWithdrawers;
    mapping(address => mapping(string => uint256)) public withdrawalLimits; // token => purpose => limit
    
    // آمار کلی
    uint256 public totalProtocolFee;   // کل protocol fee جمع‌آوری شده
    uint256 public totalWithdrawn;     // کل مقدار برداشت شده
    
    // تنظیمات withdrawal
    uint256 public constant MAX_WITHDRAWAL_PERCENTAGE = 5000; // حداکثر 50% در هر withdrawal
    uint256 public withdrawalCooldown = 7 days;               // فاصله بین withdrawal ها
    mapping(address => uint256) public lastWithdrawal;        // آخرین withdrawal برای هر token

    error InvalidAddress();
    error InvalidPercentage();
    error UnauthorizedWithdrawer();
    error InsufficientBalance();
    error WithdrawalTooFrequent();
    error ExcessiveWithdrawal();
    error InvalidPurpose();

    modifier onlyAuthorizedWithdrawer() {
        if (!authorizedWithdrawers[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedWithdrawer();
        }
        _;
    }

    modifier validWithdrawal(address token, uint256 amount) {
        if (amount == 0) revert InsufficientBalance();
        if (block.timestamp < lastWithdrawal[token] + withdrawalCooldown) {
            revert WithdrawalTooFrequent();
        }
        
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (amount > tokenBalance) revert InsufficientBalance();
        
        // بررسی حد مجاز withdrawal
        uint256 maxWithdrawal = (tokenBalance * MAX_WITHDRAWAL_PERCENTAGE) / Constants.BASIS_POINTS;
        if (amount > maxWithdrawal) revert ExcessiveWithdrawal();
        _;
    }

    constructor(
        address _treasury,
        address _developmentFund,
        address _buybackContract
    ) Ownable(msg.sender) {
        if (_treasury == address(0) || _developmentFund == address(0) || _buybackContract == address(0)) {
            revert InvalidAddress();
        }

        treasury = _treasury;
        developmentFund = _developmentFund;
        buybackContract = _buybackContract;
        
        // تنظیم اولیه allocation
        allocationConfig = AllocationConfig({
            treasuryPercentage: 6000,    // 60% به treasury
            developmentPercentage: 3000, // 30% به development
            buybackPercentage: 1000,     // 10% به buyback
            active: true
        });
        
        authorizedWithdrawers[msg.sender] = true;
    }

    /**
     * @dev جمع‌آوری protocol fee
     * @param token آدرس token
     * @param amount مقدار fee
     */
    function collectFee(address token, uint256 amount) external nonReentrant {
        if (amount == 0) return;
        
        // دریافت token (فرض می‌کنیم caller قبلاً approve کرده)
        // IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        // یا اینکه token مستقیماً transfer شده باشد
        
        FeeData storage data = feeData[token];
        
        // محاسبه تقسیم بندی
        (uint256 treasuryShare, uint256 developmentShare, uint256 buybackShare) = 
            _calculateShares(amount);
        
        // به‌روزرسانی داده‌ها
        data.totalCollected += amount;
        data.treasuryShare += treasuryShare;
        data.developmentShare += developmentShare;
        data.buybackShare += buybackShare;
        data.lastCollection = block.timestamp;
        
        totalProtocolFee += amount;
        
        emit FeeCollected(token, amount, treasuryShare, developmentShare, buybackShare);
    }

    /**
     * @dev برداشت fee برای treasury
     * @param token آدرس token
     * @param amount مقدار برداشت
     */
    function withdrawToTreasury(
        address token,
        uint256 amount
    ) external onlyAuthorizedWithdrawer validWithdrawal(token, amount) {
        FeeData storage data = feeData[token];
        
        if (amount > data.treasuryShare) {
            amount = data.treasuryShare;
        }
        
        data.treasuryShare -= amount;
        data.totalWithdrawn += amount;
        totalWithdrawn += amount;
        lastWithdrawal[token] = block.timestamp;
        
        IERC20(token).safeTransfer(treasury, amount);
        
        emit FeeWithdrawn(token, treasury, amount, "treasury");
    }

    /**
     * @dev برداشت fee برای development
     * @param token آدرس token
     * @param amount مقدار برداشت
     */
    function withdrawToDevelopment(
        address token,
        uint256 amount
    ) external onlyAuthorizedWithdrawer validWithdrawal(token, amount) {
        FeeData storage data = feeData[token];
        
        if (amount > data.developmentShare) {
            amount = data.developmentShare;
        }
        
        data.developmentShare -= amount;
        data.totalWithdrawn += amount;
        totalWithdrawn += amount;
        lastWithdrawal[token] = block.timestamp;
        
        IERC20(token).safeTransfer(developmentFund, amount);
        
        emit FeeWithdrawn(token, developmentFund, amount, "development");
    }

    /**
     * @dev برداشت fee برای buyback
     * @param token آدرس token
     * @param amount مقدار برداشت
     */
    function withdrawToBuyback(
        address token,
        uint256 amount
    ) external onlyAuthorizedWithdrawer validWithdrawal(token, amount) {
        FeeData storage data = feeData[token];
        
        if (amount > data.buybackShare) {
            amount = data.buybackShare;
        }
        
        data.buybackShare -= amount;
        data.totalWithdrawn += amount;
        totalWithdrawn += amount;
        lastWithdrawal[token] = block.timestamp;
        
        IERC20(token).safeTransfer(buybackContract, amount);
        
        emit FeeWithdrawn(token, buybackContract, amount, "buyback");
    }

    /**
     * @dev برداشت همه موجودی token به نسبت allocation
     * @param token آدرس token
     */
    function withdrawAllAllocations(address token) external onlyAuthorizedWithdrawer {
        FeeData storage data = feeData[token];
        
        uint256 treasuryAmount = data.treasuryShare;
        uint256 developmentAmount = data.developmentShare;
        uint256 buybackAmount = data.buybackShare;
        
        if (treasuryAmount > 0) {
            data.treasuryShare = 0;
            data.totalWithdrawn += treasuryAmount;
            totalWithdrawn += treasuryAmount;
            IERC20(token).safeTransfer(treasury, treasuryAmount);
            emit FeeWithdrawn(token, treasury, treasuryAmount, "treasury");
        }
        
        if (developmentAmount > 0) {
            data.developmentShare = 0;
            data.totalWithdrawn += developmentAmount;
            totalWithdrawn += developmentAmount;
            IERC20(token).safeTransfer(developmentFund, developmentAmount);
            emit FeeWithdrawn(token, developmentFund, developmentAmount, "development");
        }
        
        if (buybackAmount > 0) {
            data.buybackShare = 0;
            data.totalWithdrawn += buybackAmount;
            totalWithdrawn += buybackAmount;
            IERC20(token).safeTransfer(buybackContract, buybackAmount);
            emit FeeWithdrawn(token, buybackContract, buybackAmount, "buyback");
        }
        
        lastWithdrawal[token] = block.timestamp;
    }

    /**
     * @dev تنظیم allocation percentages
     * @param treasuryPercentage درصد treasury
     * @param developmentPercentage درصد development
     * @param buybackPercentage درصد buyback
     */
    function setAllocation(
        uint256 treasuryPercentage,
        uint256 developmentPercentage,
        uint256 buybackPercentage
    ) external onlyOwner {
        if (treasuryPercentage + developmentPercentage + buybackPercentage != Constants.BASIS_POINTS) {
            revert InvalidPercentage();
        }
        
        allocationConfig.treasuryPercentage = treasuryPercentage;
        allocationConfig.developmentPercentage = developmentPercentage;
        allocationConfig.buybackPercentage = buybackPercentage;
        
        emit AllocationUpdated(treasuryPercentage, developmentPercentage, buybackPercentage);
    }

    /**
     * @dev تنظیم آدرس treasury
     * @param _treasury آدرس جدید
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryAddressUpdated(oldTreasury, _treasury);
    }

    /**
     * @dev تنظیم آدرس development fund
     * @param _developmentFund آدرس جدید
     */
    function setDevelopmentFund(address _developmentFund) external onlyOwner {
        if (_developmentFund == address(0)) revert InvalidAddress();
        developmentFund = _developmentFund;
    }

    /**
     * @dev تنظیم آدرس buyback contract
     * @param _buybackContract آدرس جدید
     */
    function setBuybackContract(address _buybackContract) external onlyOwner {
        if (_buybackContract == address(0)) revert InvalidAddress();
        buybackContract = _buybackContract;
    }

    /**
     * @dev اضافه کردن authorized withdrawer
     * @param withdrawer آدرس withdrawer
     */
    function addAuthorizedWithdrawer(address withdrawer) external onlyOwner {
        if (withdrawer == address(0)) revert InvalidAddress();
        authorizedWithdrawers[withdrawer] = true;
    }

    /**
     * @dev حذف authorized withdrawer
     * @param withdrawer آدرس withdrawer
     */
    function removeAuthorizedWithdrawer(address withdrawer) external onlyOwner {
        authorizedWithdrawers[withdrawer] = false;
    }

    /**
     * @dev تنظیم withdrawal cooldown
     * @param cooldown cooldown جدید
     */
    function setWithdrawalCooldown(uint256 cooldown) external onlyOwner {
        require(cooldown >= 1 hours && cooldown <= 30 days, "Invalid cooldown");
        withdrawalCooldown = cooldown;
    }

    /**
     * @dev دریافت اطلاعات fee برای token
     * @param token آدرس token
     */
    function getFeeData(address token) external view returns (
        uint256 totalCollected,
        uint256 treasuryShare,
        uint256 developmentShare,
        uint256 buybackShare,
        uint256 lastCollection,
        uint256 totalWithdrawn
    ) {
        FeeData storage data = feeData[token];
        return (
            data.totalCollected,
            data.treasuryShare,
            data.developmentShare,
            data.buybackShare,
            data.lastCollection,
            data.totalWithdrawn
        );
    }

    /**
     * @dev دریافت موجودی قابل برداشت
     * @param token آدرس token
     * @param purpose هدف برداشت
     * @return amount مقدار قابل برداشت
     */
    function getWithdrawableAmount(address token, string calldata purpose) external view returns (uint256 amount) {
        FeeData storage data = feeData[token];
        
        if (keccak256(abi.encodePacked(purpose)) == keccak256(abi.encodePacked("treasury"))) {
            amount = data.treasuryShare;
        } else if (keccak256(abi.encodePacked(purpose)) == keccak256(abi.encodePacked("development"))) {
            amount = data.developmentShare;
        } else if (keccak256(abi.encodePacked(purpose)) == keccak256(abi.encodePacked("buyback"))) {
            amount = data.buybackShare;
        }
    }

    /**
     * @dev محاسبه تقسیم بندی shares
     */
    function _calculateShares(uint256 totalAmount) private view returns (
        uint256 treasuryShare,
        uint256 developmentShare,
        uint256 buybackShare
    ) {
        treasuryShare = (totalAmount * allocationConfig.treasuryPercentage) / Constants.BASIS_POINTS;
        developmentShare = (totalAmount * allocationConfig.developmentPercentage) / Constants.BASIS_POINTS;
        buybackShare = totalAmount - treasuryShare - developmentShare; // باقی‌مانده
    }

    /**
     * @dev emergency withdrawal برای owner
     * @param token آدرس token
     * @param amount مقدار
     * @param to آدرس مقصد
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
        emit FeeWithdrawn(token, to, amount, "emergency");
    }
}