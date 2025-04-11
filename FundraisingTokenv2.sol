// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

error FundingNotComplete();
error FundingComplete();
error NotEnoughAllocatedTokens();
error FundingFinalized();
error IncorrectTargerFunding(uint256 targetFunding);
error InvalidCreatorAddress(address creator);
error InvalidTokenAddress(address usdcToken);
error InvalidPlatformAddress(address platformAddress);
error InvalidUniswapAddresses();
error TokenTransferFailed(address recipient, address sender, uint256 value);
error LiquidityAddingFailed();
error InvalidLiquidityParameters();

/**
 * @title FundraisingToken
 * @dev Token created for fundraising with a Bancor bonding curve and Uniswap V3 integration
 */
contract FundraisingToken is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant SALE_ALLOCATION = 500_000_000 * 10**18;
    uint256 public constant CREATOR_ALLOCATION = 200_000_000 * 10**18;
    uint256 public constant LIQUIDITY_ALLOCATION = 250_000_000 * 10**18;
    uint256 public constant PLATFORM_FEE_ALLOCATION = 50_000_000 * 10**18;
    uint24 public constant POOL_FEE = 3000;

    uint256 public totalRaised;
    uint256 public tokensSold;

    uint256 public immutable TARGET_FUNDING;
    address public immutable USDC_TOKEN_ADDRESS;
    address public immutable CREATOR_ADDRESS;
    address public immutable PLATFORM_ADDRESS;

    bool public fundingComplete;
    bool public liquidityDeployed;

    // INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV2Router02 public immutable uniswapRouter;
    IUniswapV2Factory public immutable uniswapFactory;

    uint256 public tokenId;

    address public poolAddress;

    modifier fundingNotComplete() {
        if (!fundingComplete) revert FundingNotComplete();
        _;
    }

    modifier fundingIsComplete() {
        if (fundingComplete) revert FundingComplete();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _targetFunding,
        address _creator,
        address _usdcToken,
        address _platform,
        address _uniswapRouter
    ) ERC20(_name, _symbol) Ownable(_creator) {
        if (_targetFunding == 0) revert IncorrectTargerFunding(_targetFunding);
        if (_creator == address(0)) revert InvalidCreatorAddress(_creator);
        if (_usdcToken == address(0)) revert InvalidTokenAddress(_usdcToken);
        if (_platform == address(0)) revert InvalidPlatformAddress(_platform);
        if (_uniswapRouter == address(0)) revert InvalidUniswapAddresses();

        TARGET_FUNDING = _targetFunding * 10**6;
        CREATOR_ADDRESS = _creator;
        USDC_TOKEN_ADDRESS = _usdcToken;
        PLATFORM_ADDRESS = _platform;

        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());

        totalRaised = 0;
        tokensSold = 0;
        fundingComplete = false;
        liquidityDeployed = false;

        _mint(address(this), INITIAL_SUPPLY);
    }

    /**
     * @dev Buy tokens using the bonding curve
     * @param usdcAmount Amount of USDC to spend
     */
    function buyTokens(uint256 usdcAmount) external fundingIsComplete {
        if (usdcAmount == 0) revert();

        uint256 tokensToReceive = calculateTokenAmount(usdcAmount);

        if (tokensSold + tokensToReceive > SALE_ALLOCATION)
            revert NotEnoughAllocatedTokens();

        if (
            !IERC20(USDC_TOKEN_ADDRESS).transferFrom(
                msg.sender,
                address(this),
                usdcAmount
            )
        ) revert TokenTransferFailed(msg.sender, address(this), usdcAmount);

        unchecked {
            totalRaised += usdcAmount;
            tokensSold += tokensToReceive;
        }

        if (!IERC20(address(this)).transfer(msg.sender, tokensToReceive)) {
            revert TokenTransferFailed(
                msg.sender,
                address(this),
                tokensToReceive
            );
        }

        if (tokensSold >= SALE_ALLOCATION) {
            fundingComplete = true;
        }
    }

    /**
     * @dev Calculate token amount based on Bancor bonding curve formula
     * @param usdcAmount Amount of USDC to spend
     * @return tokensToReceive Amount of tokens to receive
     */
    function calculateTokenAmount(uint256 usdcAmount)
        public
        view
        returns (uint256 tokensToReceive)
    {
        uint256 initialPrice = (TARGET_FUNDING * 10**18) / SALE_ALLOCATION;

        uint256 currentPrice = (initialPrice * (SALE_ALLOCATION + tokensSold)) /
            SALE_ALLOCATION;

        uint256 tokensAtCurrentPrice = (usdcAmount * 10**18) / currentPrice;

        uint256 avgPrice = (initialPrice *
            (SALE_ALLOCATION + tokensSold + (tokensAtCurrentPrice / 2))) /
            SALE_ALLOCATION;

        tokensToReceive = (usdcAmount * 10**18) / avgPrice;
    }

    /**
     * @dev Get current token price based on bonding curve
     * @return price Current token price in USDC
     */
    function getCurrentPrice() public view returns (uint256 price) {
        uint256 initialPrice = (TARGET_FUNDING * 10**18) / SALE_ALLOCATION;
        price =
            (initialPrice * (SALE_ALLOCATION + tokensSold)) /
            SALE_ALLOCATION;
    }

    /**
     * @dev Finalize the fundraising and distribute tokens and USDC
     * Can only be called after funding is complete
     */
    function finalizeFundraising() external fundingNotComplete onlyOwner {
        if (liquidityDeployed) revert FundingFinalized();

        uint256 creatorUsdcAmount = IERC20(USDC_TOKEN_ADDRESS).balanceOf(
            address(this)
        ) / 2;

        if (
            !IERC20(address(this)).transfer(CREATOR_ADDRESS , CREATOR_ALLOCATION + IERC20(USDC_TOKEN_ADDRESS).balanceOf(address(this)))
        )
            revert TokenTransferFailed(
                CREATOR_ADDRESS,
                address(this),
                CREATOR_ALLOCATION
            );

        if (
            !IERC20(address(this)).transfer(
                PLATFORM_ADDRESS,
                PLATFORM_FEE_ALLOCATION
            )
        )
            revert TokenTransferFailed(
                PLATFORM_ADDRESS,
                address(this),
                PLATFORM_FEE_ALLOCATION
            );

        if (
            !IERC20(USDC_TOKEN_ADDRESS).transfer(
                CREATOR_ADDRESS,
                creatorUsdcAmount
            )
        )
            revert TokenTransferFailed(
                CREATOR_ADDRESS,
                address(this),
                creatorUsdcAmount
            );

        uint256 uniswapUsdcAmount = totalRaised - creatorUsdcAmount;

        _createPoolAndAddLiquidity(LIQUIDITY_ALLOCATION, uniswapUsdcAmount);

        liquidityDeployed = true;
    }

    /**
     * @dev Add liquidity to Uniswap
     * @param tokenAmount Amount of tokens to add to liquidity
     * @param usdcAmount Amount of USDC to add to liquidity
     */
    function _createPoolAndAddLiquidity(uint256 tokenAmount, uint256 usdcAmount)
        internal
    {
        address pair = uniswapFactory.getPair(address(this), USDC_TOKEN_ADDRESS);
        
        // Create pair if it doesn't exist
        if (pair == address(0)) {
            pair = uniswapFactory.createPair(address(this), USDC_TOKEN_ADDRESS);
        }
        // Approve tokens for router
        IERC20(address(this)).approve(address(uniswapRouter), tokenAmount);
        IERC20(USDC_TOKEN_ADDRESS).approve(address(uniswapRouter), usdcAmount);

        // Add liquidity
        uniswapRouter.addLiquidity(
            address(this), // tokenA
            USDC_TOKEN_ADDRESS, // tokenB
            tokenAmount, // amountADesired
            usdcAmount, // amountBDesired
            (tokenAmount * 99) / 100, // amountAMin (1% slippage)
            (usdcAmount * 99) / 100, // amountBMin (1% slippage)
            CREATOR_ADDRESS, // To address (LP tokens go to creator)
            block.timestamp + 15 minutes // Deadline
        );
    }

    /**
     * @dev Get creator's share of tokens
     * @return Amount of tokens allocated to creator
     */
    function getCreatorAllocation() public pure returns (uint256) {
        return CREATOR_ALLOCATION;
    }

    /**
     * @dev Get platform fee allocation
     * @return Amount of tokens allocated to platform as fee
     */
    function getPlatformFeeAllocation() public pure returns (uint256) {
        return PLATFORM_FEE_ALLOCATION;
    }

    /**
     * @dev Get liquidity allocation
     * @return Amount of tokens allocated to liquidity
     */
    function getLiquidityAllocation() public pure returns (uint256) {
        return LIQUIDITY_ALLOCATION;
    }

    /**
     * @dev Get sale allocation
     * @return Amount of tokens allocated for sale
     */
    function getSaleAllocation() public pure returns (uint256) {
        return SALE_ALLOCATION;
    }
}
