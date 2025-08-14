// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Timelock
 * @dev قفل زمانی برای اجرای تراکنش‌های governance
 */
contract Timelock is Ownable, ReentrancyGuard {

    struct QueuedTransaction {
        address target;             // آدرس مقصد
        uint256 value;              // مقدار ETH
        string signature;           // امضای تابع
        bytes data;                 // داده تراکنش
        uint256 eta;                // زمان قابل اجرا
        bool executed;              // آیا اجرا شده
        bool cancelled;             // آیا لغو شده
        string description;         // توضیحات
    }

    // Events
    event TransactionQueued(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );

    event TransactionExecuted(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta,
        bool success
    );

    event TransactionCancelled(bytes32 indexed txHash);
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    // State variables
    mapping(bytes32 => QueuedTransaction) public queuedTransactions;
    mapping(address => bool) public isAdmin;
    mapping(bytes32 => bool) public cancelledTransactions;
    
    uint256 public delay;                   // تاخیر اجرا (ثانیه)
    uint256 public constant MIN_DELAY = 1 hours;    // حداقل تاخیر
    uint256 public constant MAX_DELAY = 30 days;    // حداکثر تاخیر
    uint256 public constant GRACE_PERIOD = 14 days; // دوره grace
    
    address public admin;                   // ادمین اصلی (معمولاً Governor)
    address public pendingAdmin;            // ادمین در انتظار
    
    // Emergency settings
    bool public emergencyPaused = false;
    address public guardian;
    mapping(bytes32 => bool) public emergencyTransactions;

    error InvalidDelay();
    error TransactionAlreadyQueued();
    error TransactionNotQueued();
    error TransactionNotReady();
    error TransactionExpired();
    error TransactionFailed();
    error UnauthorizedCaller();
    error EmergencyPaused();
    error InvalidTarget();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert UnauthorizedCaller();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian && msg.sender != owner()) revert UnauthorizedCaller();
        _;
    }

    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPaused();
        _;
    }

    constructor(uint256 _delay, address _admin, address _guardian) Ownable(msg.sender) {
        if (_delay < MIN_DELAY || _delay > MAX_DELAY) revert InvalidDelay();
        
        delay = _delay;
        admin = _admin;
        guardian = _guardian;
        
        isAdmin[_admin] = true;
    }

    receive() external payable {}

    /**
     * @dev قرار دادن تراکنش در صف
     * @param target آدرس مقصد
     * @param value مقدار ETH
     * @param signature امضای تابع
     * @param data داده تراکنش
     * @param eta زمان قابل اجرا
     * @param description توضیحات
     */
    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta,
        string calldata description
    ) external onlyAdmin notPaused returns (bytes32 txHash) {
        if (target == address(0)) revert InvalidTarget();
        if (eta < block.timestamp + delay) revert TransactionNotReady();
        
        txHash = keccak256(abi.encode(target, value, signature, data, eta));
        
        if (queuedTransactions[txHash].eta != 0) revert TransactionAlreadyQueued();
        
        queuedTransactions[txHash] = QueuedTransaction({
            target: target,
            value: value,
            signature: signature,
            data: data,
            eta: eta,
            executed: false,
            cancelled: false,
            description: description
        });
        
        emit TransactionQueued(txHash, target, value, signature, data, eta);
    }

    /**
     * @dev اجرای تراکنش از صف
     * @param target آدرس مقصد
     * @param value مقدار ETH
     * @param signature امضای تابع
     * @param data داده تراکنش
     * @param eta زمان قابل اجرا
     */
    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external payable onlyAdmin nonReentrant notPaused returns (bool success, bytes memory result) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        QueuedTransaction storage txn = queuedTransactions[txHash];
        
        if (txn.eta == 0) revert TransactionNotQueued();
        if (txn.executed) revert TransactionFailed();
        if (txn.cancelled) revert TransactionFailed();
        if (block.timestamp < txn.eta) revert TransactionNotReady();
        if (block.timestamp > txn.eta + GRACE_PERIOD) revert TransactionExpired();
        
        txn.executed = true;
        
        bytes memory callData;
        if (bytes(signature).length > 0) {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        } else {
            callData = data;
        }
        
        (success, result) = target.call{value: value}(callData);
        
        emit TransactionExecuted(txHash, target, value, signature, data, eta, success);
        
        if (!success) {
            // Don't revert, just emit event and return false
            return (false, result);
        }
    }

    /**
     * @dev لغو تراکنش از صف
     * @param target آدرس مقصد
     * @param value مقدار ETH
     * @param signature امضای تابع
     * @param data داده تراکنش
     * @param eta زمان قابل اجرا
     */
    function cancelTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyAdmin {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        QueuedTransaction storage txn = queuedTransactions[txHash];
        
        if (txn.eta == 0) revert TransactionNotQueued();
        if (txn.executed) revert TransactionFailed();
        
        txn.cancelled = true;
        cancelledTransactions[txHash] = true;
        
        emit TransactionCancelled(txHash);
    }

    /**
     * @dev اجرای emergency transaction
     * @param target آدرس مقصد
     * @param value مقدار ETH
     * @param signature امضای تابع
     * @param data داده تراکنش
     */
    function executeEmergencyTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data
    ) external payable onlyGuardian nonReentrant returns (bool success, bytes memory result) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, block.timestamp));
        emergencyTransactions[txHash] = true;
        
        bytes memory callData;
        if (bytes(signature).length > 0) {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        } else {
            callData = data;
        }
        
        (success, result) = target.call{value: value}(callData);
        
        emit TransactionExecuted(txHash, target, value, signature, data, block.timestamp, success);
    }

    /**
     * @dev تنظیم delay جدید
     * @param newDelay delay جدید
     */
    function setDelay(uint256 newDelay) external {
        require(msg.sender == address(this), "Only timelock can set delay");
        if (newDelay < MIN_DELAY || newDelay > MAX_DELAY) revert InvalidDelay();
        
        uint256 oldDelay = delay;
        delay = newDelay;
        
        emit DelayUpdated(oldDelay, newDelay);
    }

    /**
     * @dev تغییر admin
     * @param newAdmin ادمین جدید
     */
    function setPendingAdmin(address newAdmin) external onlyAdmin {
        pendingAdmin = newAdmin;
    }

    /**
     * @dev تایید admin جدید
     */
    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "Not pending admin");
        
        address oldAdmin = admin;
        admin = pendingAdmin;
        pendingAdmin = address(0);
        
        isAdmin[oldAdmin] = false;
        isAdmin[admin] = true;
        
        emit AdminChanged(oldAdmin, admin);
    }

    /**
     * @dev اضافه کردن admin اضافی
     * @param newAdmin آدرس admin جدید
     */
    function addAdmin(address newAdmin) external {
        require(msg.sender == address(this), "Only timelock can add admin");
        isAdmin[newAdmin] = true;
    }

    /**
     * @dev حذف admin
     * @param adminToRemove آدرس admin برای حذف
     */
    function removeAdmin(address adminToRemove) external {
        require(msg.sender == address(this), "Only timelock can remove admin");
        require(adminToRemove != admin, "Cannot remove main admin");
        isAdmin[adminToRemove] = false;
    }

    /**
     * @dev تنظیم guardian
     * @param newGuardian guardian جدید
     */
    function setGuardian(address newGuardian) external onlyOwner {
        guardian = newGuardian;
    }

    /**
     * @dev فعال/غیرفعال emergency pause
     * @param paused وضعیت
     */
    function setEmergencyPaused(bool paused) external onlyGuardian {
        emergencyPaused = paused;
    }

    /**
     * @dev دریافت اطلاعات تراکنش
     * @param txHash hash تراکنش
     */
    function getTransaction(bytes32 txHash) external view returns (
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta,
        bool executed,
        bool cancelled,
        string memory description
    ) {
        QueuedTransaction storage txn = queuedTransactions[txHash];
        return (
            txn.target,
            txn.value,
            txn.signature,
            txn.data,
            txn.eta,
            txn.executed,
            txn.cancelled,
            txn.description
        );
    }

    /**
     * @dev بررسی آماده بودن تراکنش برای اجرا
     * @param txHash hash تراکنش
     * @return ready آیا آماده است
     */
    function isTransactionReady(bytes32 txHash) external view returns (bool ready) {
        QueuedTransaction storage txn = queuedTransactions[txHash];
        
        if (txn.eta == 0 || txn.executed || txn.cancelled) return false;
        if (block.timestamp < txn.eta) return false;
        if (block.timestamp > txn.eta + GRACE_PERIOD) return false;
        
        return true;
    }

    /**
     * @dev محاسبه hash تراکنش
     * @param target آدرس مقصد
     * @param value مقدار ETH
     * @param signature امضای تابع
     * @param data داده تراکنش
     * @param eta زمان قابل اجرا
     * @return txHash
     */
    function getTransactionHash(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external pure returns (bytes32 txHash) {
        return keccak256(abi.encode(target, value, signature, data, eta));
    }

    /**
     * @dev دریافت تعداد تراکنش‌های در صف
     * @return count تعداد
     */
    function getQueuedTransactionsCount() external view returns (uint256 count) {
        // این تابع نیاز به پیاده‌سازی mapping اضافی دارد
        // فعلاً ساده‌سازی شده است
        return 0;
    }

    /**
     * @dev emergency withdrawal
     * @param token آدرس token (0x0 برای ETH)
     * @param amount مقدار
     * @param to آدرس مقصد
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyGuardian {
        if (token == address(0)) {
            // ETH withdrawal
            payable(to).transfer(amount);
        } else {
            // Token withdrawal
            IERC20(token).transfer(to, amount);
        }
    }
}

// Interface برای ERC20
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}