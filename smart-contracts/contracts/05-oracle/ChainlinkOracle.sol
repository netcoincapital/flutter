// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";

import "../01-core/AccessControl.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/**
 * @title ChainlinkOracle
 * @dev Chainlink price feed integration for LAXCE DEX
 * @dev Provides external price data with validation and heartbeat checks
 */
contract ChainlinkOracle is Pausable, LaxceAccessControl {
    using LaxceReentrancyGuard for LaxceReentrancyGuard.ReentrancyData;

    // =========== CONSTANTS ===========
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant MAX_HEARTBEAT = 86400; // 24 hours
    uint256 public constant MIN_HEARTBEAT = 60; // 1 minute
    uint256 public constant MAX_PRICE_DEVIATION = 5000; // 50%
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 1 hour

    // =========== STRUCTS ===========
    struct PriceFeed {
        AggregatorV3Interface aggregator;
        uint256 heartbeat;
        uint8 decimals;
        bool isActive;
        uint256 lastValidPrice;
        uint256 lastValidTimestamp;
        string description;
    }

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 roundId;
        bool isValid;
        string source;
    }

    struct ValidationConfig {
        uint256 maxPriceDeviation;
        uint256 stalePriceThreshold;
        bool enableValidation;
        bool requireMinAnswers;
        uint256 minAnswers;
    }

    // =========== STATE VARIABLES ===========
    LaxceReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    // Token pair => price feed
    mapping(bytes32 => PriceFeed) public priceFeeds;
    
    // All registered feed keys
    bytes32[] public feedKeys;
    mapping(bytes32 => bool) public isFeedRegistered;
    
    // Price history for validation
    mapping(bytes32 => uint256[]) public priceHistory;
    mapping(bytes32 => uint256) public historyIndex;
    
    // Configuration
    ValidationConfig public validationConfig;
    uint256 public maxHistoryLength = 100;
    
    // Fallback prices (in case of oracle failure)
    mapping(bytes32 => uint256) public fallbackPrices;
    mapping(bytes32 => uint256) public fallbackTimestamps;
    bool public fallbackMode = false;

    // =========== EVENTS ===========
    event PriceFeedAdded(
        bytes32 indexed feedKey,
        address indexed aggregator,
        string description,
        uint256 heartbeat
    );
    
    event PriceFeedUpdated(
        bytes32 indexed feedKey,
        address indexed aggregator,
        uint256 heartbeat
    );
    
    event PriceFeedRemoved(bytes32 indexed feedKey);
    
    event PriceUpdated(
        bytes32 indexed feedKey,
        uint256 price,
        uint256 timestamp,
        uint256 roundId
    );
    
    event FallbackPriceSet(bytes32 indexed feedKey, uint256 price, uint256 timestamp);
    event FallbackModeToggled(bool enabled);
    event ValidationConfigUpdated(ValidationConfig config);
    event StalePriceDetected(bytes32 indexed feedKey, uint256 lastUpdate, uint256 threshold);

    // =========== ERRORS ===========
    error ChainlinkOracle__InvalidFeed();
    error ChainlinkOracle__FeedAlreadyExists();
    error ChainlinkOracle__FeedNotFound();
    error ChainlinkOracle__InvalidHeartbeat();
    error ChainlinkOracle__StalePrice();
    error ChainlinkOracle__InvalidPrice();
    error ChainlinkOracle__PriceDeviationTooHigh();
    error ChainlinkOracle__InsufficientData();

    // =========== MODIFIERS ===========
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }

    modifier validFeedKey(bytes32 feedKey) {
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();
        _;
    }

    // =========== CONSTRUCTOR ===========
    constructor() {
        _reentrancyGuard.initialize();
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // Initialize validation config
        validationConfig = ValidationConfig({
            maxPriceDeviation: 1000, // 10%
            stalePriceThreshold: STALE_PRICE_THRESHOLD,
            enableValidation: true,
            requireMinAnswers: false,
            minAnswers: 1
        });
    }

    // =========== FEED MANAGEMENT ===========

    /**
     * @dev Add a new price feed
     * @param token0 First token address
     * @param token1 Second token address
     * @param aggregator Chainlink aggregator address
     * @param heartbeat Expected update frequency in seconds
     */
    function addPriceFeed(
        address token0,
        address token1,
        address aggregator,
        uint256 heartbeat
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        if (aggregator == address(0)) revert ChainlinkOracle__InvalidFeed();
        if (heartbeat < MIN_HEARTBEAT || heartbeat > MAX_HEARTBEAT) {
            revert ChainlinkOracle__InvalidHeartbeat();
        }

        bytes32 feedKey = _getFeedKey(token0, token1);
        if (isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedAlreadyExists();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(aggregator);
        
        // Validate feed by getting latest data
        try priceFeed.latestRoundData() returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (price <= 0) revert ChainlinkOracle__InvalidPrice();
            
            uint8 decimals = priceFeed.decimals();
            string memory description = priceFeed.description();
            
            // Store price feed
            priceFeeds[feedKey] = PriceFeed({
                aggregator: priceFeed,
                heartbeat: heartbeat,
                decimals: decimals,
                isActive: true,
                lastValidPrice: uint256(price),
                lastValidTimestamp: updatedAt,
                description: description
            });
            
            // Initialize price history
            priceHistory[feedKey] = new uint256[](maxHistoryLength);
            priceHistory[feedKey][0] = uint256(price);
            historyIndex[feedKey] = 1;
            
            // Add to registry
            feedKeys.push(feedKey);
            isFeedRegistered[feedKey] = true;
            
            emit PriceFeedAdded(feedKey, aggregator, description, heartbeat);
            emit PriceUpdated(feedKey, uint256(price), updatedAt, roundId);
            
        } catch {
            revert ChainlinkOracle__InvalidFeed();
        }
    }

    /**
     * @dev Update existing price feed configuration
     * @param token0 First token address
     * @param token1 Second token address
     * @param aggregator New aggregator address
     * @param heartbeat New heartbeat
     */
    function updatePriceFeed(
        address token0,
        address token1,
        address aggregator,
        uint256 heartbeat
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();
        if (aggregator == address(0)) revert ChainlinkOracle__InvalidFeed();
        if (heartbeat < MIN_HEARTBEAT || heartbeat > MAX_HEARTBEAT) {
            revert ChainlinkOracle__InvalidHeartbeat();
        }

        AggregatorV3Interface priceFeed = AggregatorV3Interface(aggregator);
        
        // Validate new feed
        try priceFeed.latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (price <= 0) revert ChainlinkOracle__InvalidPrice();
            
            uint8 decimals = priceFeed.decimals();
            string memory description = priceFeed.description();
            
            // Update price feed
            priceFeeds[feedKey].aggregator = priceFeed;
            priceFeeds[feedKey].heartbeat = heartbeat;
            priceFeeds[feedKey].decimals = decimals;
            priceFeeds[feedKey].description = description;
            
            emit PriceFeedUpdated(feedKey, aggregator, heartbeat);
            
        } catch {
            revert ChainlinkOracle__InvalidFeed();
        }
    }

    /**
     * @dev Remove a price feed
     * @param token0 First token address
     * @param token1 Second token address
     */
    function removePriceFeed(
        address token0,
        address token1
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();

        // Remove from feedKeys array
        for (uint256 i = 0; i < feedKeys.length; i++) {
            if (feedKeys[i] == feedKey) {
                feedKeys[i] = feedKeys[feedKeys.length - 1];
                feedKeys.pop();
                break;
            }
        }

        // Clean up mappings
        delete priceFeeds[feedKey];
        delete priceHistory[feedKey];
        delete historyIndex[feedKey];
        delete isFeedRegistered[feedKey];
        delete fallbackPrices[feedKey];
        delete fallbackTimestamps[feedKey];

        emit PriceFeedRemoved(feedKey);
    }

    // =========== PRICE QUERIES ===========

    /**
     * @dev Get latest price for token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @return priceData Latest price data
     */
    function getLatestPrice(address token0, address token1) 
        external 
        view 
        returns (PriceData memory priceData) 
    {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();

        if (fallbackMode) {
            return _getFallbackPrice(feedKey);
        }

        return _getChainlinkPrice(feedKey);
    }

    /**
     * @dev Get price at specific round
     * @param token0 First token address
     * @param token1 Second token address
     * @param roundId Specific round ID
     * @return priceData Historical price data
     */
    function getPriceAtRound(
        address token0,
        address token1,
        uint80 roundId
    ) external view returns (PriceData memory priceData) {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();

        PriceFeed memory feed = priceFeeds[feedKey];
        
        try feed.aggregator.getRoundData(roundId) returns (
            uint80 _roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (price <= 0) revert ChainlinkOracle__InvalidPrice();
            
            uint256 normalizedPrice = _normalizePrice(uint256(price), feed.decimals);
            
            priceData = PriceData({
                price: normalizedPrice,
                timestamp: updatedAt,
                roundId: _roundId,
                isValid: true,
                source: "Chainlink"
            });
            
        } catch {
            revert ChainlinkOracle__InvalidPrice();
        }
    }

    /**
     * @dev Get multiple latest prices for different pairs
     * @param token0s Array of first tokens
     * @param token1s Array of second tokens
     * @return pricesData Array of price data
     */
    function getLatestPrices(
        address[] calldata token0s,
        address[] calldata token1s
    ) external view returns (PriceData[] memory pricesData) {
        require(token0s.length == token1s.length, "Array length mismatch");
        
        pricesData = new PriceData[](token0s.length);
        
        for (uint256 i = 0; i < token0s.length; i++) {
            bytes32 feedKey = _getFeedKey(token0s[i], token1s[i]);
            
            if (isFeedRegistered[feedKey]) {
                if (fallbackMode) {
                    pricesData[i] = _getFallbackPrice(feedKey);
                } else {
                    try this.getLatestPrice(token0s[i], token1s[i]) returns (
                        PriceData memory data
                    ) {
                        pricesData[i] = data;
                    } catch {
                        pricesData[i] = PriceData({
                            price: 0,
                            timestamp: 0,
                            roundId: 0,
                            isValid: false,
                            source: "Error"
                        });
                    }
                }
            } else {
                pricesData[i] = PriceData({
                    price: 0,
                    timestamp: 0,
                    roundId: 0,
                    isValid: false,
                    source: "Not Found"
                });
            }
        }
    }

    /**
     * @dev Check if price feed is healthy
     * @param token0 First token address
     * @param token1 Second token address
     * @return isHealthy True if feed is responding and up-to-date
     */
    function isPriceFeedHealthy(address token0, address token1) 
        external 
        view 
        returns (bool isHealthy) 
    {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) return false;

        PriceFeed memory feed = priceFeeds[feedKey];
        if (!feed.isActive) return false;

        try feed.aggregator.latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (price <= 0) return false;
            if (block.timestamp > updatedAt + feed.heartbeat) return false;
            
            return true;
            
        } catch {
            return false;
        }
    }

    // =========== INTERNAL FUNCTIONS ===========

    /**
     * @dev Get Chainlink price with validation
     */
    function _getChainlinkPrice(bytes32 feedKey) 
        internal 
        view 
        returns (PriceData memory priceData) 
    {
        PriceFeed memory feed = priceFeeds[feedKey];
        
        try feed.aggregator.latestRoundData() returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (price <= 0) revert ChainlinkOracle__InvalidPrice();
            
            // Check if price is stale
            if (block.timestamp > updatedAt + feed.heartbeat) {
                revert ChainlinkOracle__StalePrice();
            }
            
            uint256 normalizedPrice = _normalizePrice(uint256(price), feed.decimals);
            
            // Validate price if enabled
            if (validationConfig.enableValidation) {
                _validatePrice(feedKey, normalizedPrice);
            }
            
            priceData = PriceData({
                price: normalizedPrice,
                timestamp: updatedAt,
                roundId: roundId,
                isValid: true,
                source: "Chainlink"
            });
            
        } catch {
            // Return fallback price if available
            if (fallbackTimestamps[feedKey] > 0) {
                return _getFallbackPrice(feedKey);
            } else {
                revert ChainlinkOracle__InvalidPrice();
            }
        }
    }

    /**
     * @dev Get fallback price
     */
    function _getFallbackPrice(bytes32 feedKey) 
        internal 
        view 
        returns (PriceData memory priceData) 
    {
        uint256 fallbackPrice = fallbackPrices[feedKey];
        uint256 fallbackTimestamp = fallbackTimestamps[feedKey];
        
        if (fallbackPrice == 0) revert ChainlinkOracle__InvalidPrice();
        
        priceData = PriceData({
            price: fallbackPrice,
            timestamp: fallbackTimestamp,
            roundId: 0,
            isValid: true,
            source: "Fallback"
        });
    }

    /**
     * @dev Validate price against historical data
     */
    function _validatePrice(bytes32 feedKey, uint256 newPrice) internal view {
        uint256[] memory history = priceHistory[feedKey];
        uint256 histIdx = historyIndex[feedKey];
        
        if (histIdx == 0) return; // No history to validate against
        
        // Get previous price
        uint256 prevIndex = histIdx > 0 ? histIdx - 1 : maxHistoryLength - 1;
        uint256 prevPrice = history[prevIndex];
        
        if (prevPrice == 0) return; // No valid previous price
        
        // Calculate deviation
        uint256 deviation = newPrice > prevPrice 
            ? (newPrice - prevPrice) * 10000 / prevPrice
            : (prevPrice - newPrice) * 10000 / prevPrice;
            
        if (deviation > validationConfig.maxPriceDeviation) {
            revert ChainlinkOracle__PriceDeviationTooHigh();
        }
    }

    /**
     * @dev Normalize price to 18 decimals
     */
    function _normalizePrice(uint256 price, uint8 decimals) 
        internal 
        pure 
        returns (uint256) 
    {
        if (decimals == 18) {
            return price;
        } else if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else {
            return price / (10 ** (decimals - 18));
        }
    }

    /**
     * @dev Generate feed key for token pair
     */
    function _getFeedKey(address token0, address token1) 
        internal 
        pure 
        returns (bytes32) 
    {
        return token0 < token1 
            ? keccak256(abi.encodePacked(token0, token1))
            : keccak256(abi.encodePacked(token1, token0));
    }

    // =========== ADMIN FUNCTIONS ===========

    /**
     * @dev Set validation configuration
     */
    function setValidationConfig(ValidationConfig calldata config) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        validationConfig = config;
        emit ValidationConfigUpdated(config);
    }

    /**
     * @dev Set fallback price for a feed
     */
    function setFallbackPrice(
        address token0,
        address token1,
        uint256 price
    ) external onlyRole(ADMIN_ROLE) {
        bytes32 feedKey = _getFeedKey(token0, token1);
        fallbackPrices[feedKey] = price;
        fallbackTimestamps[feedKey] = block.timestamp;
        
        emit FallbackPriceSet(feedKey, price, block.timestamp);
    }

    /**
     * @dev Toggle fallback mode
     */
    function setFallbackMode(bool enabled) external onlyRole(ADMIN_ROLE) {
        fallbackMode = enabled;
        emit FallbackModeToggled(enabled);
    }

    /**
     * @dev Set feed active status
     */
    function setFeedActive(
        address token0,
        address token1,
        bool active
    ) external onlyRole(OPERATOR_ROLE) {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();
        
        priceFeeds[feedKey].isActive = active;
    }

    /**
     * @dev Update price history for a feed (operator function)
     */
    function updatePriceHistory(address token0, address token1) 
        external 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
    {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();

        PriceData memory data = _getChainlinkPrice(feedKey);
        
        // Add to price history
        uint256 index = historyIndex[feedKey] % maxHistoryLength;
        priceHistory[feedKey][index] = data.price;
        historyIndex[feedKey] = index + 1;
        
        // Update last valid price
        priceFeeds[feedKey].lastValidPrice = data.price;
        priceFeeds[feedKey].lastValidTimestamp = data.timestamp;
    }

    /**
     * @dev Emergency pause
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // =========== VIEW FUNCTIONS ===========

    /**
     * @dev Get all registered feed keys
     */
    function getAllFeedKeys() external view returns (bytes32[] memory) {
        return feedKeys;
    }

    /**
     * @dev Get feed information
     */
    function getFeedInfo(address token0, address token1) 
        external 
        view 
        returns (
            address aggregator,
            uint256 heartbeat,
            uint8 decimals,
            bool isActive,
            string memory description
        ) 
    {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();
        
        PriceFeed memory feed = priceFeeds[feedKey];
        return (
            address(feed.aggregator),
            feed.heartbeat,
            feed.decimals,
            feed.isActive,
            feed.description
        );
    }

    /**
     * @dev Get price history for a feed
     */
    function getPriceHistory(address token0, address token1, uint256 count) 
        external 
        view 
        returns (uint256[] memory prices) 
    {
        bytes32 feedKey = _getFeedKey(token0, token1);
        if (!isFeedRegistered[feedKey]) revert ChainlinkOracle__FeedNotFound();
        
        uint256[] memory history = priceHistory[feedKey];
        uint256 histIdx = historyIndex[feedKey];
        uint256 returnCount = count > histIdx ? histIdx : count;
        
        prices = new uint256[](returnCount);
        
        for (uint256 i = 0; i < returnCount; i++) {
            uint256 index = (histIdx + maxHistoryLength - 1 - i) % maxHistoryLength;
            prices[i] = history[index];
        }
    }
} 