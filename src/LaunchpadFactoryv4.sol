// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {FundraisingToken, InvalidTokenAddress, InvalidPlatformAddress, InvalidUniswapAddress} from "./FundraisingTokenv4.sol";

error InvalidPlatformFee();
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
    address public poolManager;
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
        address _poolManager,
        address _platformFeeReceiver
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        if (_usdcToken == address(0)) revert InvalidTokenAddress(_usdcToken);
        if (_platformFeeReceiver == address(0))
            revert InvalidPlatformAddress(_platformFeeReceiver);
        if (_poolManager == address(0))
            revert InvalidUniswapAddress(_poolManager);

        usdcToken = _usdcToken;
        poolManager = _poolManager;
        platformFeeReceiver = _platformFeeReceiver;
    }

    function createLaunchpad(
        string calldata name,
        string calldata symbol,
        uint256 targetFunding,
        bytes32 _salt
    ) external returns (address tokenAddress) {
        if (targetFunding < 10000) revert MinimumTargetFundingNotMet();

        FundraisingToken token = new FundraisingToken{salt: _salt}(
            name,
            symbol,
            targetFunding,
            msg.sender,
            usdcToken,
            platformFeeReceiver,
            poolManager
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

    function updatePlatformFeeReceiver(address newPlatformFeeReceiver)
        external
        onlyOwner
    {
        if (newPlatformFeeReceiver == address(0))
            revert InvalidPlatformAddress(newPlatformFeeReceiver);
        platformFeeReceiver = newPlatformFeeReceiver;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}