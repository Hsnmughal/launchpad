# Token Fundraising Launchpad with Bancor Bonding Curve

## Problem Statement
Create a fundraising token launchpad that implements a Bancor bonding curve mechanism, where initial users are incentivized more than later participants. The platform should handle token distribution, liquidity provisioning, and implement secure upgrade mechanisms.

## My Approach

### 1. Exploring Bonding Curve Mechanisms
I began by exploring different Bancor bonding curve implementations and their mathematical properties:
- **Linear curve**: Simple and predictable price increases
- **Quadratic curve**: Provides more aggressive price growth
- **Exponential curve**: Creates even stronger early-buyer incentives
- **Logarithmic curve**: Provides diminishing price increases
- **Sigmoid curve**: S-shaped curve with slower growth at beginning and end

After testing different mathematical models, I chose to start with a linear implementation for simplicity and predictability while still providing early-buyer incentives.

### 2. Creating Basic Architecture
I designed the system with the following key components:
- `FundraisingToken`: Main ERC20 token contract with bonding curve pricing mechanism
- `LaunchpadFactory`: Factory pattern for creating new fundraising campaigns
- UUPS upgradeability pattern for future-proofing

The token system implements:
- Initial supply of 1 billion tokens
- 500M tokens for sale via bonding curve
- 200M tokens allocated to creator after fundraising
- 250M tokens + 50% of raised funds for liquidity
- 50M tokens as platform fee

### 3. Implementing Price Logic
For the bonding curve pricing mechanism, I implemented a linear approximation:
```solidity
uint256 initialPrice = (targetFunding * 10**18) / SALE_ALLOCATION;
uint256 currentPrice = initialPrice * (1 + tokensSold / SALE_ALLOCATION);
```

This creates a curve where:
- Initial price starts at `targetFunding / SALE_ALLOCATION`
- Price doubles by the time all tokens are sold
- The average price for each purchase is calculated for fair token distribution

### 4. DEX Integration Challenges

#### Uniswap V4 Implementation
I initially tried implementing with Uniswap V4 for the latest features, but faced significant challenges:
- Remix debugger couldn't locate source files on Sourcify or Etherscan
- Compilation issues due to complex dependency structure
- Reference issue documented at: https://github.com/ethereum/remix-project/issues/3979

#### Uniswap V3 Attempt
After facing issues with V4, I downgraded to Uniswap V3:
- Encountered similar source file location issues
- Interface conflicts remained problematic

#### Final Implementation with Uniswap V2
Due to time constraints and debugging difficulties, I eventually opted for Uniswap V2:
- More straightforward integration
- Well-documented interfaces
- Better compatibility with Remix environment

The primary issue across all attempts was related to contract interface conflicts. The inherited contracts were importing the same ERC20 and IERC20 libraries, causing compilation failures due to duplication.

### 5. Pool Creation and Liquidity Provisioning
The final implementation ensures proper liquidity provisioning by:
1. Creating a pool if it doesn't exist using Uniswap factory
2. Adding liquidity with appropriate slippage protection
3. Distributing LP tokens to the creator

### 6. Gas Optimization
For production readiness, I implemented several gas optimizations:
- Replaced `require` statements with custom errors
- Used direct token transfers instead of interface calls where possible
- Efficient state variable packing

## Deployed Contracts

The contracts have been deployed on the Sepolia testnet:

- **Mock USDC**: [0x398782BE945DD3E7a016717cDE76Ec3Cf8638e8E](https://sepolia.etherscan.io/address/0x398782BE945DD3E7a016717cDE76Ec3Cf8638e8E#code)
- **Launchpad**: [0xAe67CB3437E76bF06D49a7A1807AfE6AB47D74DC](https://sepolia.etherscan.io/address/0xAe67CB3437E76bF06D49a7A1807AfE6AB47D74DC#code)

## Future Improvements

1. **Advanced Bonding Curves**: Implement more sophisticated curve options that projects can choose from
2. **Multi-token Support**: Enable fundraising in multiple stablecoins or ETH
3. **Vesting Mechanisms**: Add token vesting for team allocations
4. **Governance Integration**: Add DAO governance for upgrade decisions

## Conclusion
Despite challenges with Uniswap integration, the final implementation successfully meets all requirements with a gas-efficient, secure, and upgradeable design. The bonding curve mechanism effectively incentivizes early participants while ensuring fair token distribution and automated liquidity provisioning.