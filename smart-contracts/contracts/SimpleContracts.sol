// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Simple LAXCE Token
 * @dev نسخه ساده‌شده LAXCE token برای deploy سریع
 */
contract SimpleLAXCE is ERC20, Ownable, Pausable {
    uint256 public totalSupply_;
    
    constructor(
        uint256 _totalSupply,
        address _owner
    ) ERC20("LAXCE Token", "LAXCE") Ownable(_owner) {
        totalSupply_ = _totalSupply;
        _mint(_owner, _totalSupply);
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        totalSupply_ += amount;
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        totalSupply_ -= amount;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }
}

/**
 * @title Simple Token Registry
 * @dev نسخه ساده‌شده token registry
 */
contract SimpleTokenRegistry is Ownable, Pausable {
    struct TokenInfo {
        string name;
        string symbol;
        bool isActive;
    }
    
    mapping(address => TokenInfo) public tokens;
    address[] public tokenList;
    
    event TokenRegistered(address indexed token, string name, string symbol);
    event TokenDeactivated(address indexed token);
    
    constructor(address _owner) Ownable(_owner) {}
    
    function registerToken(
        address _token,
        string memory _name,
        string memory _symbol
    ) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(!tokens[_token].isActive, "Token already registered");
        
        tokens[_token] = TokenInfo({
            name: _name,
            symbol: _symbol,
            isActive: true
        });
        
        tokenList.push(_token);
        
        emit TokenRegistered(_token, _name, _symbol);
    }
    
    function deactivateToken(address _token) external onlyOwner {
        require(tokens[_token].isActive, "Token not active");
        tokens[_token].isActive = false;
        
        emit TokenDeactivated(_token);
    }
    
    function isTokenActive(address _token) external view returns (bool) {
        return tokens[_token].isActive;
    }
    
    function getTokenInfo(address _token) external view returns (string memory name, string memory symbol, bool isActive) {
        TokenInfo memory info = tokens[_token];
        return (info.name, info.symbol, info.isActive);
    }
    
    function getTokenCount() external view returns (uint256) {
        return tokenList.length;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
}

/**
 * @title Simple Quoter
 * @dev نسخه ساده‌شده quoter برای قیمت‌گذاری
 */
contract SimpleQuoter is Ownable, Pausable {
    SimpleLAXCE public laxceToken;
    SimpleTokenRegistry public tokenRegistry;
    
    // Mock prices (در واقع از oracle می‌آید)
    mapping(address => uint256) public tokenPrices; // قیمت در wei
    
    event PriceUpdated(address indexed token, uint256 price);
    
    constructor(
        address _laxceToken,
        address _tokenRegistry,
        address _owner
    ) Ownable(_owner) {
        laxceToken = SimpleLAXCE(_laxceToken);
        tokenRegistry = SimpleTokenRegistry(_tokenRegistry);
    }
    
    function updatePrice(address _token, uint256 _price) external onlyOwner {
        require(tokenRegistry.isTokenActive(_token), "Token not active");
        tokenPrices[_token] = _price;
        
        emit PriceUpdated(_token, _price);
    }
    
    function getSwapQuote(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256 amountOut, uint256 priceImpact) {
        require(tokenRegistry.isTokenActive(_tokenIn), "Input token not active");
        require(tokenRegistry.isTokenActive(_tokenOut), "Output token not active");
        
        uint256 priceIn = tokenPrices[_tokenIn];
        uint256 priceOut = tokenPrices[_tokenOut];
        
        require(priceIn > 0 && priceOut > 0, "Price not available");
        
        // ساده‌ترین محاسبه: امونت * قیمت_ورودی / قیمت_خروجی
        amountOut = (_amountIn * priceIn) / priceOut;
        
        // مک price impact (در حقیقت باید از liquidity محاسبه شود)
        priceImpact = 100; // 1% price impact (100 basis points)
        
        return (amountOut, priceImpact);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
}

/**
 * @title Simple Router
 * @dev نسخه ساده‌شده router برای swaps
 */
contract SimpleRouter is Ownable, Pausable {
    SimpleLAXCE public laxceToken;
    SimpleTokenRegistry public tokenRegistry;
    SimpleQuoter public quoter;
    
    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    constructor(
        address _laxceToken,
        address _tokenRegistry,
        address _quoter,
        address _owner
    ) Ownable(_owner) {
        laxceToken = SimpleLAXCE(_laxceToken);
        tokenRegistry = SimpleTokenRegistry(_tokenRegistry);
        quoter = SimpleQuoter(_quoter);
    }
    
    function executeSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external whenNotPaused {
        require(tokenRegistry.isTokenActive(_tokenIn), "Input token not active");
        require(tokenRegistry.isTokenActive(_tokenOut), "Output token not active");
        
        // دریافت quote
        (uint256 amountOut, ) = quoter.getSwapQuote(_tokenIn, _tokenOut, _amountIn);
        require(amountOut >= _minAmountOut, "Insufficient output amount");
        
        // ساده‌ترین روش: فقط transfer (در واقع باید از pool liquidity استفاده کرد)
        require(
            ERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn),
            "Transfer failed"
        );
        
        require(
            ERC20(_tokenOut).transfer(msg.sender, amountOut),
            "Transfer failed"
        );
        
        emit SwapExecuted(msg.sender, _tokenIn, _tokenOut, _amountIn, amountOut);
    }
    
    // Owner می‌تواند liquidity اضافه کند (مک implementation)
    function addLiquidity(address _token, uint256 _amount) external onlyOwner {
        require(
            ERC20(_token).transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
} 