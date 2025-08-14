
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title MemeToken - 具有交易税、流动性池集成和交易限制的Meme代币
 */
contract MemeToken is ERC20, Ownable {
    // 交易税结构
    struct Taxes {
        uint256 buy;    // 买入税率
        uint256 sell;   // 卖出税率
        uint256 transfer; // 转账税率
    }
    
    Taxes public taxes = Taxes(3, 5, 1); // 默认税率：买入3%，卖出5%，转账1%
    address public taxWallet; // 税费接收地址
    address public liquidityWallet; // 流动性资金钱包
    
    // 交易限制
    uint256 public maxTxAmount; // 单笔交易上限
    uint256 public maxWalletAmount; // 单个钱包上限
    bool public tradingEnabled = false; // 交易开关
    
    // Uniswap V2
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    
    // 排除税费地址
    mapping(address => bool) private _isExcludedFromFee;
    // 黑名单
    mapping(address => bool) private _isBlacklisted;
    
    // 事件
    event TaxesUpdated(uint256 buy, uint256 sell, uint256 transfer);
    event TradingEnabled();
    event MaxTxAmountUpdated(uint256 amount);
    event MaxWalletAmountUpdated(uint256 amount);
    
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address routerAddress,
        address _taxWallet,
        address _liquidityWallet
    ) ERC20(name, symbol) {
        // 初始供应量
        _mint(msg.sender, initialSupply * 10**decimals());
        
        // 设置交易限制
        maxTxAmount = (initialSupply * 10**decimals()) / 100; // 1%
        maxWalletAmount = (initialSupply * 10**decimals()) / 50; // 2%
        
        // 初始化Uniswap
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(routerAddress);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;
        
        // 设置钱包地址
        taxWallet = _taxWallet;
        liquidityWallet = _liquidityWallet;
        
        // 排除owner和合约地址税费
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
    }
    
    // 重写转账函数实现交易税和限制
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "Blacklisted address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        // 检查交易是否开启
        if(from != owner() && to != owner()) {
            require(tradingEnabled, "Trading is disabled");
        }
        
        // 检查交易限制
        if(!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            require(amount <= maxTxAmount, "Exceeds max transaction amount");
            if(to != uniswapV2Pair) { // 不是卖出交易
                require(balanceOf(to) + amount <= maxWalletAmount, "Exceeds max wallet amount");
            }
        }
        
        // 计算税费
        uint256 taxAmount = 0;
        if(!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            if(to == uniswapV2Pair) { // 卖出
                taxAmount = (amount * taxes.sell) / 100;
            } else if(from == uniswapV2Pair) { // 买入
                taxAmount = (amount * taxes.buy) / 100;
            } else { // 普通转账
                taxAmount = (amount * taxes.transfer) / 100;
            }
        }
        
        // 执行转账
        if(taxAmount > 0) {
            super._transfer(from, taxWallet, taxAmount);
            amount -= taxAmount;
        }
        super._transfer(from, to, amount);
    }
    
    // 添加流动性
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external onlyOwner {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityWallet,
            block.timestamp
        );
    }
    
    // 移除流动性
    function removeLiquidity(uint256 liquidity) external onlyOwner {
        IUniswapV2Pair(uniswapV2Pair).approve(address(uniswapV2Router), liquidity);
        
        uniswapV2Router.removeLiquidityETH(
            address(this),
            liquidity,
            0,
            0,
            liquidityWallet,
            block.timestamp
        );
    }
    
    // 开启交易
    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        emit TradingEnabled();
    }
    
    // 设置税率
    function setTaxes(uint256 buy, uint256 sell, uint256 transfer) external onlyOwner {
        require(buy <= 10 && sell <= 10 && transfer <= 5, "Tax too high");
        taxes = Taxes(buy, sell, transfer);
        emit TaxesUpdated(buy, sell, transfer);
    }
    
    // 设置交易限制
    function setMaxTxAmount(uint256 amount) external onlyOwner {
        require(amount >= totalSupply() / 1000, "Too low");
        maxTxAmount = amount;
        emit MaxTxAmountUpdated(amount);
    }
    
    // 设置钱包限制
    function setMaxWalletAmount(uint256 amount) external onlyOwner {
        require(amount >= totalSupply() / 1000, "Too low");
        maxWalletAmount = amount;
        emit MaxWalletAmountUpdated(amount);
    }
    
    // 黑名单管理
    function blacklist(address account) external onlyOwner {
        _isBlacklisted[account] = true;
    }
    
    function unblacklist(address account) external onlyOwner {
        _isBlacklisted[account] = false;
    }
    
    // 排除/包含地址税费
    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }
    
    receive() external payable {}
}
