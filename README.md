# Bancor Bonding Curve Token Launchpad

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-0.2.0-orange)](https://getfoundry.sh/)

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

### Prerequisites

- [Foundry](https://getfoundry.sh/) (version 0.2.0 or later)
- [Git](https://git-scm.com/)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/bancor-launchpad.git
cd bancor-launchpad
```

2. Install dependencies:
```bash
forge install
```

3. Build the project:
```bash
forge build
```

### Project Structure

```
.
├── src/                    # Source files
├── test/                   # Test files
├── script/                 # Deployment scripts
├── lib/                    # Dependencies
├── foundry.toml           # Foundry configuration
└── remappings.txt         # Solidity import remappings
```

### Dependencies

The project uses the following main dependencies:
- OpenZeppelin Contracts
- OpenZeppelin Contracts Upgradeable
- Uniswap V2 & V3 Core and Periphery
- Uniswap V4 Core and Periphery
- Solmate
- Forge Standard Library

## 💻 Usage

### Creating a new launchpad:

```solidity
// Create a new fundraising token
const tokenAddress = await launchpadFactory.createLaunchpad(
  "My Token",             // Token name
  "MTK",                  // Token symbol
  ethers.utils.parseUnits("1000000", 6),  // Target funding (1M USDC)
  ethers.utils.formatBytes32String("salt") // Random salt for address generation
);
```

### Participating in a fundraise:

```solidity
// Approve USDC spending
await usdc.approve(tokenAddress, ethers.utils.parseUnits("1000", 6));

// Buy tokens with 1000 USDC
await token.buyTokens(ethers.utils.parseUnits("1000", 6));
```

### Finalizing fundraising:

```solidity
// Can only be called by creator after funding complete
await token.finalizeFundraising();
```

## 🧪 Testing

### Running Tests

```bash
# Run all tests
forge test

# Run tests with detailed gas reports
forge test --gas-report

# Run specific test file
forge test --match-path test/FundraisingToken.t.sol

# Run tests with debug traces
forge test -vvv
```

### Coverage

```bash
# Generate coverage report
forge coverage
```

### Fork Testing

```bash
# Run tests on a forked mainnet
forge test --fork-url $RPC_URL
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.