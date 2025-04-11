// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

import "https://github.com/Uniswap/v3-core/blob/0.8/contracts/interfaces/IUniswapV3Factory.sol";
import "https://github.com/Uniswap/v3-core/blob/0.8/contracts/interfaces/IUniswapV3Pool.sol";
import "https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/interfaces/INonfungiblePositionManager.sol";
import "https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/libraries/TransferHelper.sol";

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

    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV3Factory public immutable uniswapV3Factory;

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
        address _nonfungiblePositionManager,
        address _uniswapV3Factory
    ) ERC20(_name, _symbol) Ownable(_creator) {
        if (_targetFunding == 0) revert IncorrectTargerFunding(_targetFunding);
        if (_creator == address(0)) revert InvalidCreatorAddress(_creator);
        if (_usdcToken == address(0)) revert InvalidTokenAddress(_usdcToken);
        if (_platform == address(0)) revert InvalidPlatformAddress(_platform);
        if (
            _nonfungiblePositionManager == address(0) ||
            _uniswapV3Factory == address(0)
        ) revert InvalidUniswapAddresses();

        TARGET_FUNDING = _targetFunding * 10**6;
        CREATOR_ADDRESS = _creator;
        USDC_TOKEN_ADDRESS = _usdcToken;
        PLATFORM_ADDRESS = _platform;

        nonfungiblePositionManager = INonfungiblePositionManager(
            _nonfungiblePositionManager
        );
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);

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
    function finalizeFundraising() external onlyOwner {
        if (liquidityDeployed) revert FundingFinalized();

        uint256 creatorUsdcAmount = IERC20(USDC_TOKEN_ADDRESS).balanceOf(address(this)) / 2;

        if (
            !IERC20(address(this)).transfer(CREATOR_ADDRESS, CREATOR_ALLOCATION)
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
     * @dev Create a pool in Uniswap V3 and add liquidity to it
     * @param tokenAmount Amount of tokens to add
     * @param usdcAmount Amount of USDC to add
     */
    function _createPoolAndAddLiquidity(uint256 tokenAmount, uint256 usdcAmount)
        internal
    {
        if (tokenAmount == 0 || usdcAmount == 0)
            revert InvalidLiquidityParameters();

        address token0 = address(this) < USDC_TOKEN_ADDRESS
            ? address(this)
            : USDC_TOKEN_ADDRESS;
        address token1 = address(this) < USDC_TOKEN_ADDRESS
            ? USDC_TOKEN_ADDRESS
            : address(this);

        poolAddress = uniswapV3Factory.getPool(token0, token1, POOL_FEE);

        if (poolAddress == address(0)) {
            poolAddress = uniswapV3Factory.createPool(token0, token1, POOL_FEE);

            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            uint160 sqrtPriceX96 = _calculateSqrtPriceX96(
                tokenAmount,
                usdcAmount
            );
            pool.initialize(sqrtPriceX96);
        }

        TransferHelper.safeApprove(
            address(this),
            address(nonfungiblePositionManager),
            tokenAmount
        );
        TransferHelper.safeApprove(
            USDC_TOKEN_ADDRESS,
            address(nonfungiblePositionManager),
            usdcAmount
        );

        uint256 amount0ToMint;
        uint256 amount1ToMint;

        if (token0 == address(this)) {
            amount0ToMint = tokenAmount;
            amount1ToMint = usdcAmount;
        } else {
            amount0ToMint = usdcAmount;
            amount1ToMint = tokenAmount;
        }

        _addLiquidityToUniswapV3(token0, token1, amount0ToMint, amount1ToMint);
    }

    /**
     * @dev Add liquidity to Uniswap V3
     * @param token0 First token address
     * @param token1 Second token address
     * @param amount0ToMint Amount of token0 to add
     * @param amount1ToMint Amount of token1 to add
     */
    function _addLiquidityToUniswapV3(
        address token0,
        address token1,
        uint256 amount0ToMint,
        uint256 amount1ToMint
    ) internal {
        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: POOL_FEE,
                tickLower: -887272,
                tickUpper: 887272,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: CREATOR_ADDRESS,
                deadline: block.timestamp + 15 minutes
            });

        (
            ,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = nonfungiblePositionManager.mint(params);

        if (liquidity == 0) revert LiquidityAddingFailed();

        if (amount0 < amount0ToMint && token0 != address(this)) {
            TransferHelper.safeTransferFrom(
                token0,
                address(nonfungiblePositionManager),
                CREATOR_ADDRESS,
                amount0ToMint - amount0
            );
        }

        if (amount1 < amount1ToMint && token1 != address(this)) {
            TransferHelper.safeTransferFrom(
                token1,
                address(nonfungiblePositionManager),
                CREATOR_ADDRESS,
                amount1ToMint - amount1
            );
        }
    }

    /**
     * @dev Calculate sqrtPriceX96 for initializing the pool
     * @param tokenAmount Amount of this token
     * @param usdcAmount Amount of USDC
     * @return sqrtPriceX96 The square root price as a Q64.96
     */
    function _calculateSqrtPriceX96(uint256 tokenAmount, uint256 usdcAmount)
        internal
        view
        returns (uint160)
    {
        uint8 tokenDecimals = decimals();
        uint8 usdcDecimals = 6;

        uint256 price;

        if (address(this) < USDC_TOKEN_ADDRESS) {
            price =
                (usdcAmount * (10**tokenDecimals)) /
                (tokenAmount * (10**usdcDecimals));
        } else {
            price =
                (tokenAmount * (10**usdcDecimals)) /
                (usdcAmount * (10**tokenDecimals));
        }

        uint256 sqrtPrice = sqrt(price);
        uint256 sqrtPriceX96 = sqrtPrice * (1 << 96);

        return uint160(sqrtPriceX96);
    }

    /**
     * @dev Calculate square root using Babylonian method
     * @param x Input number
     * @return y The square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        assembly {
            let z := add(div(x, 2), 1)
            y := x
            for {

            } lt(z, y) {

            } {
                y := z
                z := div(add(div(x, z), z), 2)
            }
        }
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