// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {FundraisingToken, InvalidTokenAddress, InvalidTokenAddress, InvalidPlatformAddress, InvalidPlatformAddress, InvalidUniswapAddresses} from "./FundraisingToken.sol";

error MinimumTargetFundingNotMet();

/**
 * @title LaunchpadFactory
 * @dev Factory contract for creating new fundraising tokens
 */
contract LaunchpadFactory is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    address public usdcToken;
    address public nonfungiblePositionManager;
    address public uniswapV3Factory;
    address public swapRouter;
    address public platformFeeReceiver;

    event LaunchpadCreated(
        address indexed tokenAddress,
        string name,
        string symbol,
        address indexed creator,
        uint256 targetFunding
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _usdcToken,
        address _platformFeeReceiver,
        address _nonfungiblePositionManager,
        address _uniswapV3Factory
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        if (_usdcToken == address(0)) revert InvalidTokenAddress(_usdcToken);
        if (_platformFeeReceiver == address(0))
            revert InvalidPlatformAddress(_platformFeeReceiver);
        if (
            _nonfungiblePositionManager == address(0) ||
            _uniswapV3Factory == address(0)
        ) revert InvalidUniswapAddresses();

        usdcToken = _usdcToken;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        uniswapV3Factory = _uniswapV3Factory;
        platformFeeReceiver = _platformFeeReceiver;
    }

    /**
     * @dev Creates a new fundraising token
     * @param name Token name
     * @param symbol Token symbol
     * @param targetFunding Target funding amount in USDC (In simple decimals_Whole_Number)
     * @return tokenAddress Address of the new token contract
     */
    function createLaunchpad(
        string calldata name,
        string calldata symbol,
        uint256 targetFunding
    ) external returns (address tokenAddress) {
        if (targetFunding < 10000) revert MinimumTargetFundingNotMet();
        bytes32 _salt = keccak256(abi.encodePacked("Raga.Finance"));

        FundraisingToken token = new FundraisingToken{salt: _salt}(
            name,
            symbol,
            targetFunding,
            msg.sender,
            usdcToken,
            platformFeeReceiver,
            nonfungiblePositionManager,
            uniswapV3Factory
        );

        tokenAddress = address(token);

        emit LaunchpadCreated(
            tokenAddress,
            name,
            symbol,
            msg.sender,
            targetFunding
        );

        return tokenAddress;
    }

    /**
     * @dev Updates the platform fee receiver address
     * @param newPlatformFeeReceiver New platform fee receiver address
     */
    function updatePlatformFeeReceiver(address newPlatformFeeReceiver)
        external
        onlyOwner
    {
        if (newPlatformFeeReceiver == address(0))
            revert InvalidPlatformAddress(newPlatformFeeReceiver);
        platformFeeReceiver = newPlatformFeeReceiver;
    }

    /**
     * @dev Required override for UUPS upgradeable pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}