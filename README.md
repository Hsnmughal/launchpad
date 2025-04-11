# Bancor Bonding Curve Token Launchpad

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Uniswap](https://img.shields.io/badge/Uniswap-V2-ff69b4)](https://uniswap.org/)

A decentralized fundraising platform that leverages Bancor bonding curve mechanics to incentivize early participants, while providing automatic liquidity provisioning on completion.

## 📑 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Bonding Curve Mechanics](#bonding-curve-mechanics)
- [Installation](#installation)
- [Usage](#usage)
- [Deployed Contracts](#deployed-contracts)
- [Contributing](#contributing)
- [Testing](#testing)
- [License](#license)

## 🔍 Overview

This project creates a token launchpad platform that allows creators to raise funds using a bonding curve pricing model. Early supporters get better prices, and once fundraising completes, automatic liquidity is added to Uniswap, making the token instantly tradable.

## ✨ Features

- **Bonding Curve Pricing**: Linear price curve that incentivizes early buyers
- **Automatic Token Distribution**:
  - 500M tokens (50%) for sale to participants
  - 200M tokens (20%) to project creator
  - 250M tokens (25%) for liquidity pools
  - 50M tokens (5%) as platform fee
- **Automatic Liquidity Creation**: After funding completes, 50% of raised funds are paired with tokens for Uniswap liquidity
- **UUPS Upgradeable**: Smart contracts can be improved over time without migrations
- **Gas Optimized**: Uses custom errors and efficient coding patterns
- **Creator Control**: Project creators can finalize fundraising when ready

## 🏗 Architecture

The system consists of two main contracts:

1. **FundraisingToken.sol**
   - ERC20 token implementation with built-in bonding curve mechanics
   - Handles token sales, fund collection, and liquidity provisioning
   - Manages token distribution upon fundraising completion

2. **LaunchpadFactory.sol**
   - Factory contract to create new fundraising campaigns
   - Uses CREATE2 for deterministic token addresses
   - Handles configuration and deployment of new tokens

## 📈 Bonding Curve Mechanics

The implemented bonding curve uses a linear price model:

```solidity
initialPrice = targetFunding / saleAllocation
currentPrice = initialPrice * (1 + tokensSold / saleAllocation)
```

This creates a price curve where:
- The price starts at `initialPrice`
- Price increases linearly as tokens are sold
- The final price is double the initial price when all tokens are sold

Advantages of this approach:
- Predictable pricing model easy for users to understand
- Early participants get better prices
- Fair token distribution based on contribution amount

## 🚀 Installation & Setup

This project is designed to work with [Remix IDE](https://remix.ethereum.org/), making it accessible without local development environment setup.

### Using Remix (Recommended):
1. Visit [Remix IDE](https://remix.ethereum.org/)
2. Create a new workspace
3. Create new files for each contract (FundraisingToken.sol and LaunchpadFactory.sol)
4. Copy and paste the contract code
5. Select Solidity compiler version 0.8.20
6. Compile the contracts

### Alternative Local Setup:

If you prefer a local development environment:

```bash
# Clone the repository
git clone https://github.com/yourusername/bancor-launchpad.git
cd bancor-launchpad

# For Hardhat
npm install
npx hardhat compile

# For Foundry
forge install
forge build
```

## 💻 Usage

### Creating a new launchpad:

```javascript
// Create a new fundraising token
const tokenAddress = await launchpadFactory.createLaunchpad(
  "My Token",             // Token name
  "MTK",                  // Token symbol
  ethers.utils.parseUnits("1000000", 6),  // Target funding (1M USDC)
  ethers.utils.formatBytes32String("salt") // Random salt for address generation
);
```

### Participating in a fundraise:

```javascript
// Approve USDC spending
await usdc.approve(tokenAddress, ethers.utils.parseUnits("1000", 6));

// Buy tokens with 1000 USDC
await token.buyTokens(ethers.utils.parseUnits("1000", 6));
```

### Finalizing fundraising:

```javascript
// Can only be called by creator after funding complete
await token.finalizeFundraising();
```

## 🌐 Deployed Contracts

**Sepolia Testnet**:
- **Mock USDC**: [0x398782BE945DD3E7a016717cDE76Ec3Cf8638e8E](https://sepolia.etherscan.io/address/0x398782BE945DD3E7a016717cDE76Ec3Cf8638e8E#code)
- **Launchpad Factory**: [0xAe67CB3437E76bF06D49a7A1807AfE6AB47D74DC](https://sepolia.etherscan.io/address/0xAe67CB3437E76bF06D49a7A1807AfE6AB47D74DC#code)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 🧪 Testing

### Remix Testing:
This project is optimized for testing with Remix IDE's built-in tools:

1. **Remix VM (Blockchain)**: 
   - Deploy contracts to the JavaScript VM environment
   - Test functions directly through the Remix interface
   - Experiment with different accounts and parameters

2. **Remix Debugger**:
   - Execute transactions and debug them step-by-step
   - Inspect state changes and variable values
   - Identify issues with execution flow

### Advanced Testing Options:

For more comprehensive testing:

```bash
# Foundry (Mainnet Fork Testing)
forge test --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY

# Hardhat Local Testing
npx hardhat test

# Hardhat Mainnet Fork
npx hardhat test --network hardhat-fork
```

### Manual Testnet Deployment:
The contracts are verified on Sepolia testnet and can be tested with real transactions using tools like Metamask and Etherscan.


## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.