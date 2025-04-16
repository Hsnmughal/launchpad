// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Uniswap V3 interfaces
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

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

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

/**
 * @title FundraisingToken
 * @dev Token created for fundraising with a Bancor bonding curve and Uniswap V3 integration
 */
contract FundraisingToken is ERC20, Ownable, IERC721Receiver {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens with 18 decimals
    uint256 public constant SALE_ALLOCATION = 500_000_000 * 10**18; // 500 million tokens for sale
    uint256 public constant CREATOR_ALLOCATION = 200_000_000 * 10**18; // 200 million tokens for creator
    uint256 public constant LIQUIDITY_ALLOCATION = 250_000_000 * 10**18; // 250 million tokens for liquidity
    uint256 public constant PLATFORM_FEE_ALLOCATION = 50_000_000 * 10**18; // 50 million tokens as platform fee
    uint24 public constant POOL_FEE = 3000; // 0.3%
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 60;

    uint256 public totalRaised; // Total USDC raised
    uint256 public tokensSold; // Total tokens sold

    uint256 public immutable TARGET_FUNDING; // Target funding amount in USDC
    address public immutable USDC_TOKEN_ADDRESS; // USDC token address
    address public immutable CREATOR_ADDRESS; // Creator of the fundraising campaign
    address public immutable PLATFORM_ADDRESS; // Platform owner address

    bool public fundingComplete; // Whether funding target has been reached
    bool public liquidityDeployed; // Whether liquidity has been deployed to Uniswap

    // Uniswap V3 integration
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV3Factory public immutable uniswapV3Factory;

    // NFT position details
    uint256 public tokenId; // Uniswap V3 position NFT ID

    // Track if pool exists
    address public poolAddress;

    /**
     * @dev Modifier to ensure funding is not complete
     */
    modifier fundingNotComplete() {
        if (!fundingComplete) revert FundingNotComplete();
        _;
    }

    /**
     * @dev Modifier to ensure funding is complete
     */
    modifier fundingIsComplete() {
        if (fundingComplete) revert FundingComplete();
        _;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
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

        // Initialize Uniswap V3 interfaces
        nonfungiblePositionManager = INonfungiblePositionManager(
            _nonfungiblePositionManager
        );
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);

        totalRaised = 0;
        tokensSold = 0;
        fundingComplete = false;
        liquidityDeployed = false;

        // Mint all tokens to this contract
        _mint(address(this), INITIAL_SUPPLY);
    }

    /**
     * @dev Buy tokens using the bonding curve
     * @param usdcAmount Amount of USDC to spend
     */
    function buyTokens(uint256 usdcAmount) external fundingIsComplete {
        if (usdcAmount == 0) revert();

        // Calculate tokens to be received based on bonding curve
        uint256 tokensToReceive = calculateTokenAmount(usdcAmount);

        // Check if this purchase would exceed the allocation for sale
        if (tokensSold + tokensToReceive > SALE_ALLOCATION)
            revert NotEnoughAllocatedTokens();

        // Transfer USDC from buyer to contract
        if (
            !IERC20(USDC_TOKEN_ADDRESS).transferFrom(
                msg.sender,
                address(this),
                usdcAmount
            )
        ) revert TokenTransferFailed(msg.sender, address(this), usdcAmount);

        // Update state
        unchecked {
            totalRaised += usdcAmount;
            tokensSold += tokensToReceive;
        }

        // Transfer tokens to buyer
        if (!IERC20(address(this)).transfer(msg.sender, tokensToReceive)) {
            revert TokenTransferFailed(
                msg.sender,
                address(this),
                tokensToReceive
            );
        }

        // Check if funding target has been reached
        if (tokensSold >= SALE_ALLOCATION) {
            fundingComplete = true;
        }
    }

    /**
     * @dev Calculate token amount based on Bancor bonding curve formula
     * Formula used: price = basePrice * (1 + soldTokens/totalTokens)^reserveRatio
     * Here we integrate this formula to get the total cost for a batch of tokens
     * @param usdcAmount Amount of USDC to spend
     * @return tokensToReceive Amount of tokens to receive
     */
    function calculateTokenAmount(uint256 usdcAmount)
        public
        view
        returns (uint256 tokensToReceive)
    {
        // Initial price calculation
        uint256 initialPrice = (TARGET_FUNDING * 10**18) / SALE_ALLOCATION;

        // Current price - fixed to avoid integer division truncation
        uint256 currentPrice = (initialPrice * (SALE_ALLOCATION + tokensSold)) /
            SALE_ALLOCATION;

        // First, calculate how many tokens the user would get at the current price
        uint256 tokensAtCurrentPrice = (usdcAmount * 10**18) / currentPrice;

        // Now calculate the expected average price for this purchase
        // We need to factor in price increase during the purchase
        uint256 avgPrice = (initialPrice *
            (SALE_ALLOCATION + tokensSold + (tokensAtCurrentPrice / 2))) /
            SALE_ALLOCATION;

        // Calculate tokens to receive using the average price
        tokensToReceive = (usdcAmount * 10**18) / avgPrice;
    }

    /**
     * @dev Get current token price based on bonding curve
     * @return price Current token price in USDC
     */
    function getCurrentPrice() public view returns (uint256 price) {
        uint256 initialPrice = (TARGET_FUNDING * 10**18) / SALE_ALLOCATION;
        // Use multiplication before division to avoid truncation
        price =
            (initialPrice * (SALE_ALLOCATION + tokensSold)) /
            SALE_ALLOCATION;
    }

    /**
     * @dev Finalize the fundraising and distribute tokens and USDC
     * Can only be called after funding is complete
     */
    // function finalizeFundraising() external fundingNotComplete onlyOwner {
    function finalizeFundraising() external onlyOwner {
        if (liquidityDeployed) revert FundingFinalized();

        // Calculate amounts
        uint256 creatorUsdcAmount = IERC20(USDC_TOKEN_ADDRESS).balanceOf(
            address(this)
        ) / 2;

        // Transfer creator allocation to creator
        if (
            !IERC20(address(this)).transfer(CREATOR_ADDRESS, CREATOR_ALLOCATION)
        )
            revert TokenTransferFailed(
                CREATOR_ADDRESS,
                address(this),
                CREATOR_ALLOCATION
            );

        // Transfer platform fee allocation to platform
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

        // Transfer USDC to creator
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

        // Deploy liquidity to Uniswap V3
        uniswapUsdcAmount = totalRaised - creatorUsdcAmount;

        // Create pool and add liquidity
        _createPoolAndAddLiquidity(LIQUIDITY_ALLOCATION, uniswapUsdcAmount);

        liquidityDeployed = true;
    }

    // TEST VARIABLES:
    uint256 public uniswapUsdcAmount;
    address public token0_;
    address public token1_;
    // Variables for adding liquidity
    uint256 public amount0ToMint_;
    uint256 public amount1ToMint_;

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

        // Determine token0 and token1 (Uniswap sorts them by address)
        // address token0 = address(this) < USDC_TOKEN_ADDRESS
        //     ? address(this)
        //     : USDC_TOKEN_ADDRESS;
        // address token1 = address(this) < USDC_TOKEN_ADDRESS
        //     ? USDC_TOKEN_ADDRESS
        //     : address(this);

        token0_ = address(this) < USDC_TOKEN_ADDRESS
            ? address(this)
            : USDC_TOKEN_ADDRESS;
        token1_ = address(this) < USDC_TOKEN_ADDRESS
            ? USDC_TOKEN_ADDRESS
            : address(this);

        // Check if pool already exists
        poolAddress = uniswapV3Factory.getPool(token0_, token1_, POOL_FEE);

        // If pool doesn't exist, create it
        if (poolAddress == address(0)) {
            poolAddress = uniswapV3Factory.createPool(
                token0_,
                token1_,
                POOL_FEE
            );

            // Initialize the price
            // IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            // uint160 sqrtPriceX96 = _calculateSqrtPriceX96(
            //     tokenAmount,
            //     usdcAmount
            // );
            // pool.initialize(sqrtPriceX96);
        }

        // Approve tokens for position manager
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

        // Variables for adding liquidity
        // uint256 amount0ToMint;
        // uint256 amount1ToMint;

        // Prepare amounts based on token order
        if (token0_ == address(this)) {
            amount0ToMint_ = tokenAmount;
            amount1ToMint_ = usdcAmount;
        } else {
            amount0ToMint_ = usdcAmount;
            amount1ToMint_ = tokenAmount;
        }

        // Add liquidity
        // _addLiquidityToUniswapV3(token0, token1, amount0ToMint, amount1ToMint);
    }

    function initilizePool() external {
        // Initialize the price
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        uint160 sqrtPriceX96 = _calculateSqrtPriceX96(
            LIQUIDITY_ALLOCATION,
            uniswapUsdcAmount
        );
        pool.initialize(sqrtPriceX96);
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
    ) external {
        // Parameters for adding liquidity
        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: POOL_FEE,
                tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
                tickUpper: (MAX_TICK / TICK_SPACING) * TICK_SPACING,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 15 minutes
            });

        // Mint new position
        (
            uint256 _tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = nonfungiblePositionManager.mint(params);

        tokenId = _tokenId;

        // Revert if liquidity wasn't added
        if (liquidity == 0) revert LiquidityAddingFailed();

        // Handle any leftover tokens (refund to the contract)
        if (amount0 < amount0ToMint && token0 != address(this)) {
            TransferHelper.safeApprove(
                token0,
                address(nonfungiblePositionManager),
                0
            );
            TransferHelper.safeTransfer(
                token0,
                CREATOR_ADDRESS,
                amount0ToMint - amount0
            );
            // TransferHelper.safeTransferFrom(
            //     token0,
            //     address(nonfungiblePositionManager),
            //     CREATOR_ADDRESS,
            //     amount0ToMint - amount0
            // );
        }

        if (amount1 < amount1ToMint && token1 != address(this)) {
            TransferHelper.safeApprove(
                token1,
                address(nonfungiblePositionManager),
                0
            );
            TransferHelper.safeTransfer(
                token1,
                CREATOR_ADDRESS,
                amount1ToMint - amount1
            );
            // TransferHelper.safeTransferFrom(
            //     token1,
            //     address(nonfungiblePositionManager),
            //     CREATOR_ADDRESS,
            //     amount1ToMint - amount1
            // );
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
        // Get token decimals
        uint8 tokenDecimals = decimals();
        uint8 usdcDecimals = 6; // USDC has 6 decimals

        // Calculate price ratio (token/USDC)
        // Price = (usdcAmount / 10^usdcDecimals) / (tokenAmount / 10^tokenDecimals)
        uint256 price;

        if (address(this) < USDC_TOKEN_ADDRESS) {
            // Our token is token0, USDC is token1
            // price = token1/token0 = USDC/token
            price =
                (usdcAmount * (10**tokenDecimals)) /
                (tokenAmount * (10**usdcDecimals));
        } else {
            // USDC is token0, our token is token1
            // price = token0/token1 = USDC/token
            price =
                (tokenAmount * (10**usdcDecimals)) /
                (usdcAmount * (10**tokenDecimals));
        }

        // Calculate sqrtPriceX96 = sqrt(price) * 2^96
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
            // Initial guess
            let z := add(div(x, 2), 1)

            // Set y to x initially
            y := x

            // Loop until z < y
            for {

            } lt(z, y) {

            } {
                // y = z;
                y := z

                // z = (x / z + z) / 2;
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
