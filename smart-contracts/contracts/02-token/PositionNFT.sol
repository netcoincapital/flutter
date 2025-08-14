// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "../01-core/AccessControl.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/TickMath.sol";

/**
 * @title PositionNFT
 * @dev NFT برای نمایش و مدیریت liquidity positions در Concentrated Liquidity
 * @notice هر NFT نمایانگر یک position منحصر به فرد با range و liquidity مشخص است
 */
contract PositionNFT is 
    ERC721, 
    ERC721Enumerable, 
    ERC721URIStorage, 
    Pausable, 
    LaxceAccessControl 
{
    using Strings for uint256;
    using TickMath for int24;
    using LaxceReentrancyGuard for LaxceReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر تعداد positions
    uint256 public constant MAX_POSITIONS = 1000000;
    
    /// @dev مدت زمان پیش‌فرض انقضا (365 روز)
    uint256 public constant DEFAULT_EXPIRY = 365 days;
    
    /// @dev حداکثر مدت انقضا (2 سال)
    uint256 public constant MAX_EXPIRY = 2 * 365 days;
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات کامل position
    struct Position {
        uint96 nonce;               // نonce منحصر به فرد
        address operator;           // operator مجاز
        address token0;             // آدرس توکن اول
        address token1;             // آدرس توکن دوم
        uint24 fee;                 // کارمزد pool
        int24 tickLower;            // tick پایین
        int24 tickUpper;            // tick بالا
        uint128 liquidity;          // مقدار نقدینگی
        uint256 feeGrowthInside0LastX128; // آخرین fee growth توکن 0
        uint256 feeGrowthInside1LastX128; // آخرین fee growth توکن 1
        uint128 tokensOwed0;        // توکن‌های مدیون 0
        uint128 tokensOwed1;        // توکن‌های مدیون 1
        uint256 createdAt;          // زمان ایجاد
        uint256 updatedAt;          // آخرین به‌روزرسانی
        uint256 expiresAt;          // زمان انقضا
        bool active;                // وضعیت فعال
    }
    
    /// @dev اطلاعات metadata برای نمایش
    struct PositionMetadata {
        string name;                // نام position
        string description;         // توضیحات
        string image;               // تصویر SVG
        string animationUrl;        // URL انیمیشن
        string externalUrl;         // URL خارجی
        string backgroundColor;     // رنگ پس‌زمینه
        uint256 priceRangeLower;    // قیمت پایین range
        uint256 priceRangeUpper;    // قیمت بالای range
        uint256 currentPrice;       // قیمت فعلی
        bool inRange;               // آیا در range است
        uint256 feeEarned0;         // fee کسب شده توکن 0
        uint256 feeEarned1;         // fee کسب شده توکن 1
    }
    
    /// @dev اطلاعات pool
    struct PoolInfo {
        address poolAddress;        // آدرس pool
        string token0Symbol;        // نماد توکن 0
        string token1Symbol;        // نماد توکن 1
        uint8 token0Decimals;       // اعشار توکن 0
        uint8 token1Decimals;       // اعشار توکن 1
        uint256 token0Price;        // قیمت توکن 0
        uint256 token1Price;        // قیمت توکن 1
        uint160 sqrtPriceX96;       // قیمت فعلی pool
        int24 currentTick;          // tick فعلی
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev محافظت از reentrancy
    LaxceReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev mapping از tokenId به اطلاعات position
    mapping(uint256 => Position) public positions;
    
    /// @dev mapping از tokenId به اطلاعات pool
    mapping(uint256 => PoolInfo) public poolInfo;
    
    /// @dev شمارنده tokenId
    uint256 public nextTokenId = 1;
    
    /// @dev آدرس factory
    address public factory;
    
    /// @dev آدرس position manager
    address public positionManager;
    
    /// @dev base URI برای metadata
    string public baseTokenURI;
    
    /// @dev آیا metadata on-chain است
    bool public onChainMetadata = true;
    
    /// @dev mapping برای operator های مجاز برای هر position
    mapping(uint256 => mapping(address => bool)) public positionOperators;
    
    /// @dev mapping برای tracking fee rewards
    mapping(uint256 => mapping(address => uint256)) public feeRewards;
    
    // ==================== EVENTS ====================
    
    event PositionMinted(
        uint256 indexed tokenId,
        address indexed owner,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    );
    
    event PositionUpdated(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );
    
    event PositionBurned(uint256 indexed tokenId, address indexed owner);
    
    event OperatorApproved(
        uint256 indexed tokenId,
        address indexed operator,
        bool approved
    );
    
    event FeeCollected(
        uint256 indexed tokenId,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1
    );
    
    event PositionExpired(uint256 indexed tokenId, uint256 expiredAt);
    
    event MetadataUpdated(uint256 indexed tokenId, string newMetadata);
    
    // ==================== ERRORS ====================
    
    error PositionNFT__Unauthorized();
    error PositionNFT__PositionNotExists();
    error PositionNFT__PositionExpired();
    error PositionNFT__InvalidTickRange();
    error PositionNFT__ZeroLiquidity();
    error PositionNFT__MaxPositionsReached();
    error PositionNFT__InvalidPool();
    error PositionNFT__ZeroAddress();
    error PositionNFT__PositionNotActive();
    error PositionNFT__InvalidExpiry();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier onlyPositionManager() {
        require(msg.sender == positionManager, "Not position manager");
        _;
    }
    
    modifier onlyAuthorized(uint256 tokenId) {
        if (!_isAuthorized(msg.sender, tokenId)) {
            revert PositionNFT__Unauthorized();
        }
        _;
    }
    
    modifier positionExists(uint256 tokenId) {
        if (_ownerOf(tokenId) == address(0)) revert PositionNFT__PositionNotExists();
        _;
    }
    
    modifier positionActive(uint256 tokenId) {
        if (!positions[tokenId].active) revert PositionNFT__PositionNotActive();
        _;
    }
    
    modifier positionNotExpired(uint256 tokenId) {
        if (block.timestamp >= positions[tokenId].expiresAt) {
            revert PositionNFT__PositionExpired();
        }
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _factory,
        address _positionManager,
        string memory _baseTokenURI
    ) ERC721("LAXCE Liquidity Positions", "LAXCE-LP") {
        if (_factory == address(0)) revert PositionNFT__ZeroAddress();
        if (_positionManager == address(0)) revert PositionNFT__ZeroAddress();
        
        factory = _factory;
        positionManager = _positionManager;
        baseTokenURI = _baseTokenURI;
        
        // مقداردهی اولیه reentrancy guard
        _reentrancyGuard.initialize();
    }
    
    // ==================== POSITION MANAGEMENT ====================
    
    /**
     * @dev mint کردن position NFT جدید
     * @param to آدرس دریافت‌کننده
     * @param token0 آدرس توکن اول
     * @param token1 آدرس توکن دوم
     * @param fee کارمزد pool
     * @param tickLower tick پایین
     * @param tickUpper tick بالا
     * @param liquidity مقدار نقدینگی
     * @param expiry زمان انقضا (0 برای پیش‌فرض)
     * @return tokenId شناسه NFT
     */
    function mint(
        address to,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 expiry
    ) external onlyPositionManager nonReentrant returns (uint256 tokenId) {
        if (to == address(0)) revert PositionNFT__ZeroAddress();
        if (liquidity == 0) revert PositionNFT__ZeroLiquidity();
        if (tickLower >= tickUpper) revert PositionNFT__InvalidTickRange();
        if (nextTokenId > MAX_POSITIONS) revert PositionNFT__MaxPositionsReached();
        
        // تنظیم expiry
        uint256 expiresAt;
        if (expiry == 0) {
            expiresAt = block.timestamp.add(DEFAULT_EXPIRY);
        } else {
            if (expiry > MAX_EXPIRY) revert PositionNFT__InvalidExpiry();
            expiresAt = block.timestamp.add(expiry);
        }
        
        tokenId = nextTokenId++;
        
        // ایجاد position
        positions[tokenId] = Position({
            nonce: uint96(tokenId),
            operator: address(0),
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            expiresAt: expiresAt,
            active: true
        });
        
        // mint NFT
        _mint(to, tokenId);
        
        emit PositionMinted(
            tokenId,
            to,
            token0,
            token1,
            fee,
            tickLower,
            tickUpper,
            liquidity
        );
    }
    
    /**
     * @dev به‌روزرسانی position
     * @param tokenId شناسه position
     * @param liquidityDelta تغییر نقدینگی
     * @param feeGrowthInside0X128 fee growth توکن 0
     * @param feeGrowthInside1X128 fee growth توکن 1
     */
    function updatePosition(
        uint256 tokenId,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) external onlyPositionManager positionExists(tokenId) positionActive(tokenId) {
        Position storage position = positions[tokenId];
        
        // محاسبه fee های جدید
        uint256 tokensOwed0 = _calculateTokensOwed(
            position.feeGrowthInside0LastX128,
            feeGrowthInside0X128,
            position.liquidity
        );
        
        uint256 tokensOwed1 = _calculateTokensOwed(
            position.feeGrowthInside1LastX128,
            feeGrowthInside1X128,
            position.liquidity
        );
        
        // به‌روزرسانی position
        if (liquidityDelta != 0) {
            position.liquidity = uint128(int128(position.liquidity) + liquidityDelta);
        }
        
        position.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        position.tokensOwed0 += uint128(tokensOwed0);
        position.tokensOwed1 += uint128(tokensOwed1);
        position.updatedAt = block.timestamp;
        
        emit PositionUpdated(
            tokenId,
            position.liquidity,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }
    
    /**
     * @dev جمع‌آوری fee های position
     * @param tokenId شناسه position
     * @param recipient آدرس دریافت‌کننده
     * @return amount0 مقدار توکن 0
     * @return amount1 مقدار توکن 1
     */
    function collectFees(
        uint256 tokenId,
        address recipient
    ) external onlyAuthorized(tokenId) positionExists(tokenId) returns (
        uint256 amount0,
        uint256 amount1
    ) {
        if (recipient == address(0)) revert PositionNFT__ZeroAddress();
        
        Position storage position = positions[tokenId];
        
        amount0 = position.tokensOwed0;
        amount1 = position.tokensOwed1;
        
        position.tokensOwed0 = 0;
        position.tokensOwed1 = 0;
        
        emit FeeCollected(tokenId, recipient, amount0, amount1);
    }
    
    /**
     * @dev burn کردن position NFT
     * @param tokenId شناسه position
     */
    function burn(uint256 tokenId) 
        external 
        onlyAuthorized(tokenId) 
        positionExists(tokenId) 
    {
        Position storage position = positions[tokenId];
        
        // بررسی خالی بودن position
        require(position.liquidity == 0, "Position not empty");
        require(position.tokensOwed0 == 0 && position.tokensOwed1 == 0, "Fees not collected");
        
        // غیرفعال کردن position
        position.active = false;
        
        address owner = ownerOf(tokenId);
        
        // burn NFT
        _burn(tokenId);
        
        emit PositionBurned(tokenId, owner);
    }
    
    // ==================== OPERATOR MANAGEMENT ====================
    
    /**
     * @dev تنظیم operator برای position
     * @param tokenId شناسه position
     * @param operator آدرس operator
     * @param approved تایید یا عدم تایید
     */
    function setPositionOperator(
        uint256 tokenId,
        address operator,
        bool approved
    ) external onlyAuthorized(tokenId) positionExists(tokenId) {
        positionOperators[tokenId][operator] = approved;
        
        if (approved) {
            positions[tokenId].operator = operator;
        } else if (positions[tokenId].operator == operator) {
            positions[tokenId].operator = address(0);
        }
        
        emit OperatorApproved(tokenId, operator, approved);
    }
    
    // ==================== METADATA FUNCTIONS ====================
    
    /**
     * @dev دریافت URI توکن
     * @param tokenId شناسه توکن
     * @return URI توکن
     */
    function tokenURI(uint256 tokenId) 
        public 
        view 
        override(ERC721, ERC721URIStorage) 
        positionExists(tokenId) 
        returns (string memory) 
    {
        if (onChainMetadata) {
            return _generateOnChainMetadata(tokenId);
        } else {
            return super.tokenURI(tokenId);
        }
    }
    
    /**
     * @dev تولید metadata on-chain
     * @param tokenId شناسه توکن
     * @return metadata به صورت data URI
     */
    function _generateOnChainMetadata(uint256 tokenId) 
        internal 
        view 
        returns (string memory) 
    {
        Position memory position = positions[tokenId];
        PositionMetadata memory metadata = _buildMetadata(tokenId);
        
        string memory json = string(abi.encodePacked(
            '{"name":"',
            metadata.name,
            '","description":"',
            metadata.description,
            '","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(_generateSVG(tokenId))),
            '","attributes":[',
            _generateAttributes(tokenId),
            ']}'
        ));
        
        return string(abi.encodePacked(
            'data:application/json;base64,',
            Base64.encode(bytes(json))
        ));
    }
    
    /**
     * @dev تولید تصویر SVG
     * @param tokenId شناسه توکن
     * @return SVG به صورت string
     */
    function _generateSVG(uint256 tokenId) internal view returns (string memory) {
        Position memory position = positions[tokenId];
        PositionMetadata memory metadata = _buildMetadata(tokenId);
        
        return string(abi.encodePacked(
            '<svg width="400" height="600" xmlns="http://www.w3.org/2000/svg">',
            '<defs>',
            '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
            '<stop offset="0%" style="stop-color:#667eea;stop-opacity:1" />',
            '<stop offset="100%" style="stop-color:#764ba2;stop-opacity:1" />',
            '</linearGradient>',
            '</defs>',
            '<rect width="400" height="600" fill="url(#bg)" />',
            '<text x="20" y="40" fill="white" font-size="24" font-weight="bold">LAXCE LP Position</text>',
            '<text x="20" y="80" fill="white" font-size="16">#', tokenId.toString(), '</text>',
            '<text x="20" y="120" fill="white" font-size="14">Pool: ', metadata.name, '</text>',
            '<text x="20" y="150" fill="white" font-size="12">Liquidity: ', position.liquidity.toString(), '</text>',
            '<text x="20" y="180" fill="white" font-size="12">Range: ', metadata.priceRangeLower.toString(), ' - ', metadata.priceRangeUpper.toString(), '</text>',
            '<text x="20" y="210" fill="white" font-size="12">Current Price: ', metadata.currentPrice.toString(), '</text>',
            '<text x="20" y="240" fill="white" font-size="12">Status: ', metadata.inRange ? 'In Range' : 'Out of Range', '</text>',
            '<text x="20" y="280" fill="white" font-size="12">Fee Earned Token0: ', metadata.feeEarned0.toString(), '</text>',
            '<text x="20" y="310" fill="white" font-size="12">Fee Earned Token1: ', metadata.feeEarned1.toString(), '</text>',
            _generateRangeVisualization(tokenId),
            '</svg>'
        ));
    }
    
    /**
     * @dev تولید نمایش بصری range
     * @param tokenId شناسه توکن
     * @return SVG elements برای نمایش range
     */
    function _generateRangeVisualization(uint256 tokenId) 
        internal 
        view 
        returns (string memory) 
    {
        Position memory position = positions[tokenId];
        
        // محاسبه موقعیت‌های range
        uint256 rangeStart = 50;
        uint256 rangeWidth = 300;
        uint256 rangeHeight = 20;
        uint256 rangeY = 400;
        
        return string(abi.encodePacked(
            '<rect x="', rangeStart.toString(), '" y="', rangeY.toString(), 
            '" width="', rangeWidth.toString(), '" height="', rangeHeight.toString(), 
            '" fill="rgba(255,255,255,0.2)" stroke="white" stroke-width="2" />',
            '<rect x="', (rangeStart + 50).toString(), '" y="', rangeY.toString(), 
            '" width="', (rangeWidth - 100).toString(), '" height="', rangeHeight.toString(), 
            '" fill="rgba(17,198,153,0.8)" />',
            '<circle cx="', (rangeStart + rangeWidth / 2).toString(), '" cy="', (rangeY + rangeHeight / 2).toString(), 
            '" r="5" fill="yellow" />'
        ));
    }
    
    /**
     * @dev ساخت metadata
     * @param tokenId شناسه توکن
     * @return metadata کامل
     */
    function _buildMetadata(uint256 tokenId) 
        internal 
        view 
        returns (PositionMetadata memory) 
    {
        Position memory position = positions[tokenId];
        PoolInfo memory pool = poolInfo[tokenId];
        
        return PositionMetadata({
            name: string(abi.encodePacked(pool.token0Symbol, "/", pool.token1Symbol)),
            description: string(abi.encodePacked(
                "LAXCE Liquidity Position #", tokenId.toString(),
                " for ", pool.token0Symbol, "/", pool.token1Symbol, " pool"
            )),
            image: "",
            animationUrl: "",
            externalUrl: "",
            backgroundColor: "#667eea",
            priceRangeLower: uint256(position.tickLower.getSqrtRatioAtTick()),
            priceRangeUpper: uint256(position.tickUpper.getSqrtRatioAtTick()),
            currentPrice: uint256(pool.sqrtPriceX96),
            inRange: _isInRange(position, pool.currentTick),
            feeEarned0: position.tokensOwed0,
            feeEarned1: position.tokensOwed1
        });
    }
    
    /**
     * @dev تولید attributes برای metadata
     * @param tokenId شناسه توکن
     * @return attributes به صورت JSON
     */
    function _generateAttributes(uint256 tokenId) 
        internal 
        view 
        returns (string memory) 
    {
        Position memory position = positions[tokenId];
        PoolInfo memory pool = poolInfo[tokenId];
        
        return string(abi.encodePacked(
            '{"trait_type":"Token0","value":"', pool.token0Symbol, '"},',
            '{"trait_type":"Token1","value":"', pool.token1Symbol, '"},',
            '{"trait_type":"Fee Tier","value":"', uint256(position.fee).toString(), '"},',
            '{"trait_type":"Liquidity","value":"', uint256(position.liquidity).toString(), '"},',
            '{"trait_type":"Status","value":"', position.active ? "Active" : "Inactive", '"},',
            '{"trait_type":"In Range","value":"', _isInRange(position, pool.currentTick) ? "Yes" : "No", '"}'
        ));
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev دریافت اطلاعات position
     * @param tokenId شناسه position
     * @return اطلاعات کامل position
     */
    function getPosition(uint256 tokenId) 
        external 
        view 
        positionExists(tokenId) 
        returns (Position memory) 
    {
        return positions[tokenId];
    }
    
    /**
     * @dev بررسی authorization
     * @param spender آدرس spender
     * @param tokenId شناسه توکن
     * @return true اگر مجاز باشد
     */
    function _isAuthorized(address spender, uint256 tokenId) 
        internal 
        view 
        returns (bool) 
    {
        address owner = ownerOf(tokenId);
        return (
            spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender) ||
            positionOperators[tokenId][spender] ||
            spender == positionManager
        );
    }
    
    /**
     * @dev بررسی در range بودن
     * @param position اطلاعات position
     * @param currentTick tick فعلی
     * @return true اگر در range باشد
     */
    function _isInRange(Position memory position, int24 currentTick) 
        internal 
        pure 
        returns (bool) 
    {
        return currentTick >= position.tickLower && currentTick < position.tickUpper;
    }
    
    /**
     * @dev محاسبه tokens owed
     * @param feeGrowthInsideLast آخرین fee growth
     * @param feeGrowthInsideCurrent fee growth فعلی
     * @param liquidity مقدار نقدینگی
     * @return مقدار tokens owed
     */
    function _calculateTokensOwed(
        uint256 feeGrowthInsideLast,
        uint256 feeGrowthInsideCurrent,
        uint128 liquidity
    ) internal pure returns (uint256) {
        return uint256(liquidity).mul(
            feeGrowthInsideCurrent.sub(feeGrowthInsideLast)
        ).div(2**128);
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev تنظیم position manager
     * @param newPositionManager آدرس جدید
     */
    function setPositionManager(address newPositionManager) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        if (newPositionManager == address(0)) revert PositionNFT__ZeroAddress();
        positionManager = newPositionManager;
    }
    
    /**
     * @dev تنظیم base URI
     * @param newBaseURI URI جدید
     */
    function setBaseURI(string calldata newBaseURI) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        baseTokenURI = newBaseURI;
    }
    
    /**
     * @dev تنظیم on-chain metadata
     * @param enabled فعال یا غیرفعال
     */
    function setOnChainMetadata(bool enabled) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        onChainMetadata = enabled;
    }
    
    /**
     * @dev به‌روزرسانی pool info
     * @param tokenId شناسه position
     * @param poolAddress آدرس pool
     * @param token0Symbol نماد توکن 0
     * @param token1Symbol نماد توکن 1
     * @param sqrtPriceX96 قیمت فعلی
     * @param currentTick tick فعلی
     */
    function updatePoolInfo(
        uint256 tokenId,
        address poolAddress,
        string calldata token0Symbol,
        string calldata token1Symbol,
        uint160 sqrtPriceX96,
        int24 currentTick
    ) external onlyPositionManager positionExists(tokenId) {
        poolInfo[tokenId] = PoolInfo({
            poolAddress: poolAddress,
            token0Symbol: token0Symbol,
            token1Symbol: token1Symbol,
            token0Decimals: 18,
            token1Decimals: 18,
            token0Price: 0,
            token1Price: 0,
            sqrtPriceX96: sqrtPriceX96,
            currentTick: currentTick
        });
    }
    
    /**
     * @dev pause کردن کانترکت
     */
    function pause() external onlyValidRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev unpause کردن کانترکت
     */
    function unpause() external onlyValidRole(ADMIN_ROLE) {
        _unpause();
    }
    
    // ==================== OVERRIDES ====================
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
    
    function _burn(uint256 tokenId) 
        internal 
        override(ERC721, ERC721URIStorage) 
    {
        super._burn(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, LaxceAccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
} 