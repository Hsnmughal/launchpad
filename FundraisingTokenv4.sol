// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import {PoolManager, BalanceDelta, IHooks} from "https://github.com/Uniswap/v4-core/blob/main/src/PoolManager.sol";
import {IPoolManager} from "https://github.com/Uniswap/v4-core/blob/main/src/interfaces/IPoolManager.sol";
import {Currency} from "https://github.com/Uniswap/v4-core/blob/main/src/types/Currency.sol";
import {PoolKey} from "https://github.com/Uniswap/v4-core/blob/main/src/types/PoolKey.sol";
import {PoolId} from "https://github.com/Uniswap/v4-core/blob/main/src/types/PoolId.sol";

error NotCreator();
error FundingNotComplete();
error FundingComplete();
error NotEnoughAllocatedTokens();
error FundingFinalized();
error IncorrectTargerFunding(uint256 targetFunding);
error InvalidCreatorAddress(address creator);
error InvalidTokenAddress(address usdcToken);
error InvalidPlatformAddress(address platformAddress);
error InvalidUniswapAddress(address uniswapRouter);
error TokenTransferFailed(address recipient, address sender, uint256 value);

/**
 * @title FundraisingToken
 * @dev Token created for fundraising with a Bancor bonding curve
 */
contract FundraisingToken is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant SALE_ALLOCATION = 500_000_000 * 10**18;
    uint256 public constant CREATOR_ALLOCATION = 200_000_000 * 10**18;
    uint256 public constant LIQUIDITY_ALLOCATION = 250_000_000 * 10**18;
    uint256 public constant PLATFORM_FEE_ALLOCATION = 50_000_000 * 10**18;
    uint24 public constant POOL_FEE = 3000;
    int24 public constant TICK_SPACING = 60;

    uint256 public totalRaised;
    uint256 public tokensSold;

    uint256 public immutable TARGET_FUNDING;
    address public immutable USDC_TOKEN_ADDRESS;
    address public immutable CREATOR_ADDRESS;
    address public immutable PLATFORM_ADDRESS;

    bool public fundingComplete;
    bool public liquidityDeployed;

    PoolKey public poolKey;
    PoolId public poolId;
    IPoolManager public immutable poolManager;

    modifier onlyCreator() {
        if (msg.sender != CREATOR_ADDRESS) revert NotCreator();
        _;
    }

    modifier fundingNotComplete() {
        if (fundingComplete) revert FundingNotComplete();
        _;
    }

    modifier fundingIsComplete() {
        if (!fundingComplete) revert FundingComplete();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _targetFunding,
        address _creator,
        address _usdcToken,
        address _platform,
        address _poolManager
    ) ERC20(_name, _symbol) Ownable(_creator) {
        if (_targetFunding < 0) revert IncorrectTargerFunding(_targetFunding);
        if (_creator == address(0)) revert InvalidCreatorAddress(_creator);
        if (_usdcToken == address(0)) revert InvalidTokenAddress(_usdcToken);
        if (_platform == address(0)) revert InvalidPlatformAddress(_platform);
        if (_poolManager == address(0))
            revert InvalidUniswapAddress(_poolManager);

        TARGET_FUNDING = _targetFunding;
        CREATOR_ADDRESS = _creator;
        USDC_TOKEN_ADDRESS = _usdcToken;
        PLATFORM_ADDRESS = _platform;
        poolManager = IPoolManager(_poolManager);

        totalRaised = 0;
        tokensSold = 0;
        fundingComplete = false;
        liquidityDeployed = false;

        poolKey = PoolKey({
            currency0: Currency.wrap(address(this)) < Currency.wrap(_usdcToken)
                ? Currency.wrap(address(this))
                : Currency.wrap(_usdcToken),
            currency1: Currency.wrap(address(this)) < Currency.wrap(_usdcToken)
                ? Currency.wrap(_usdcToken)
                : Currency.wrap(address(this)),
            fee: POOL_FEE,
            hooks: IHooks(address(0)),
            tickSpacing: TICK_SPACING
        });
        poolId = poolKey.toId();

        _mint(address(this), INITIAL_SUPPLY);
    }

    function buyTokens(uint256 usdcAmount) external fundingNotComplete {
        if (usdcAmount < 0) revert();

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

        if (!transfer(msg.sender, tokensToReceive)) {
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

    function getCurrentPrice() public view returns (uint256 price) {
        uint256 initialPrice = (TARGET_FUNDING * 10**18) / SALE_ALLOCATION;
        price =
            (initialPrice * (SALE_ALLOCATION + tokensSold)) /
            SALE_ALLOCATION;
    }

    function finalizeFundraising() external fundingIsComplete onlyCreator {
        if (liquidityDeployed) revert FundingFinalized();

        uint256 creatorUsdcAmount = TARGET_FUNDING / 2;

        if (!transfer(CREATOR_ADDRESS, CREATOR_ALLOCATION))
            revert TokenTransferFailed(
                CREATOR_ADDRESS,
                address(this),
                CREATOR_ALLOCATION
            );

        if (!transfer(PLATFORM_ADDRESS, PLATFORM_FEE_ALLOCATION))
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
        uint160 sqrtPriceX96 = _calculateSqrtPriceX96(
            LIQUIDITY_ALLOCATION,
            uniswapUsdcAmount
        );

        _addLiquidityToUniswap(
            LIQUIDITY_ALLOCATION,
            uniswapUsdcAmount,
            sqrtPriceX96
        );

        liquidityDeployed = true;
    }

    function _addLiquidityToUniswap(
        uint256 tokenAmount,
        uint256 usdcAmount,
        uint160 sqrtPriceX96
    ) internal {
        poolManager.initialize(poolKey, sqrtPriceX96);
        approve(address(poolManager), tokenAmount);
        IERC20(USDC_TOKEN_ADDRESS).approve(address(poolManager), usdcAmount);
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager
            .ModifyLiquidityParams({
                tickLower: -887220,
                tickUpper: 887220,
                liquidityDelta: int256(tokenAmount),
                salt: bytes32(0)
            });

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            poolKey,
            params,
            ""
        );

        if (delta.amount0() < 0) {
            transfer(address(poolManager), uint128(-delta.amount0()));
        }
        if (delta.amount1() < 0) {
            transfer(address(poolManager), uint128(-delta.amount1()));
        }

        if (
            delta.amount0() < 0 &&
            Currency.unwrap(poolKey.currency0) == USDC_TOKEN_ADDRESS
        ) {
            IERC20(USDC_TOKEN_ADDRESS).transfer(
                address(poolManager),
                uint128(delta.amount0())
            );
        }
        if (
            delta.amount1() < 0 &&
            Currency.unwrap(poolKey.currency1) == USDC_TOKEN_ADDRESS
        ) {
            IERC20(USDC_TOKEN_ADDRESS).transfer(
                address(poolManager),
                uint128(delta.amount1())
            );
        }

        poolManager.settle();
    }

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

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        assembly {
            let z := add(div(x, 2), 1)
            y := x
            for {} lt(z, y) {} {
                y := z
                z := div(add(div(x, z), z), 2)
            }
        }
    }

    function getCreatorAllocation() public pure returns (uint256) {
        return CREATOR_ALLOCATION;
    }

    function getPlatformFeeAllocation() public pure returns (uint256) {
        return PLATFORM_FEE_ALLOCATION;
    }

    function getLiquidityAllocation() public pure returns (uint256) {
        return LIQUIDITY_ALLOCATION;
    }

    function getSaleAllocation() public pure returns (uint256) {
        return SALE_ALLOCATION;
    }
}