# 🔄 Cross-Chain Rebase Token

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.30-363636?logo=solidity)](https://soliditylang.org/)
[![Built with Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C?logo=ethereum)](https://getfoundry.sh/)
[![Chainlink CCIP](https://img.shields.io/badge/Powered%20by-Chainlink%20CCIP-375BD2)](https://chain.link/cross-chain)

A cross-chain rebase token system that rewards users for depositing ETH into a vault. Balances grow automatically over time via linear interest accrual, and tokens can be bridged between chains while preserving each user's personal interest rate.

> This project is for educational purposes and is based on Patrick Collins' Cyfrin Updraft Advanced Foundry course.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [How It Works](#how-it-works)
  - [Interest Accrual](#interest-accrual)
  - [Cross-Chain Bridging](#cross-chain-bridging)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Environment Setup](#environment-setup)
- [Deployment](#deployment)
  - [Step 1 — Deploy on Sepolia](#step-1--deploy-on-sepolia)
  - [Step 2 — Deploy Vault on Sepolia](#step-2--deploy-vault-on-sepolia)
  - [Step 3 — Deploy on OP Sepolia](#step-3--deploy-on-op-sepolia)
  - [Step 4 — Configure Sepolia Pool](#step-4--configure-sepolia-pool)
  - [Step 5 — Configure OP Sepolia Pool](#step-5--configure-op-sepolia-pool)
  - [Step 6 — Deposit into Vault](#step-6--deposit-into-vault)
  - [Step 7 — Bridge Tokens](#step-7--bridge-tokens)
- [Usage](#usage)
- [Deployed Contracts](#deployed-contracts)
- [Network Details](#network-details)
- [Security Considerations](#security-considerations)
- [Known Limitations](#known-limitations)
- [License](#license)

---

## Overview

The **Cross-Chain Rebase Token** allows users to deposit ETH into a vault on Sepolia and receive rebase tokens that automatically grow in value over time. These tokens can be bridged to Optimism Sepolia via Chainlink CCIP, with the user's personal interest rate preserved across chains.

---

## Features

- **Automatic Interest Accrual** — Token balances grow linearly over time without any manual claiming
- **Per-User Interest Rates** — Each user locks in the global rate at deposit time; early depositors always earn more
- **Rate Can Only Decrease** — The global interest rate is monotonically decreasing, rewarding early adopters
- **Cross-Chain Bridging** — Tokens bridge between Sepolia and OP Sepolia via Chainlink CCIP
- **Interest Rate Preservation** — User's personal rate is encoded in the CCIP message and restored on the destination chain
- **ETH-Backed** — Tokens are redeemable 1:1 for ETH at any time (plus accrued interest, funded by vault rewards)

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                          Sepolia                                   │
│                                                                    │
│   User ──ETH──> Vault ──mint()──> RebaseToken                     │
│                                        │                          │
│                                   balanceOf()                     │
│                                   grows over time                 │
│                                        │                          │
│                              RebaseTokenPool                      │
│                              (burn + encode rate)                 │
└────────────────────────────────────┬───────────────────────────────┘
                                     │ Chainlink CCIP
                                     │ (carries interest rate)
┌────────────────────────────────────▼───────────────────────────────┐
│                        OP Sepolia                                  │
│                                                                    │
│                       RebaseTokenPool                             │
│                       (decode rate + mint)                        │
│                              │                                    │
│                         RebaseToken                               │
│                         (same rate, grows over time)              │
└────────────────────────────────────────────────────────────────────┘
```

---

## Contracts

| Contract | Description |
|---|---|
| `RebaseToken.sol` | ERC20 token with linear interest accrual. Balances grow automatically each second based on the user's locked-in rate. |
| `RebaseTokenPool.sol` | CCIP token pool that burns tokens on the source chain and mints on the destination chain, preserving the user's interest rate via pool data. |
| `Vault.sol` | Accepts ETH deposits and mints RebaseTokens 1:1. Also handles redemptions back to ETH. |
| `IRebaseToken.sol` | Interface used by both the Vault and Pool to interact with the token. |

---

## How It Works

### Interest Accrual

Interest is linear and calculated per second. Each user's balance is computed dynamically:

```
balanceOf(user) = principalBalance × (1 + timeElapsed × userInterestRate) / 1e18
```

The principal balance (stored on-chain) only updates when a user interacts with the protocol — deposit, redeem, transfer, or bridge. At that point, `_mintAccruedInterest` materializes the virtual interest into real tokens.

The global interest rate starts at `3e9` (~10% APY) and can only decrease over time. Each user's rate is set at the moment they receive tokens and never changes for them unless they burn their entire balance.

### Cross-Chain Bridging

When a user bridges tokens via the CCIP router:

1. `RebaseTokenPool.lockOrBurn` is called on the source chain
2. It reads the user's current interest rate via `getUserInterestRate`
3. Burns the tokens from the pool
4. Encodes the interest rate into `destPoolData` and sends it with the CCIP message

On the destination chain:

1. `RebaseTokenPool.releaseOrMint` is called
2. It decodes the interest rate from `sourcePoolData`
3. Mints the same amount of tokens to the receiver with the original interest rate

The user continues accruing at the same rate on the destination chain as they had on the source chain.

---

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/)
- [Git](https://git-scm.com/)
- Sepolia and OP Sepolia testnet ETH
- Sepolia and OP Sepolia LINK tokens

### Installation

```bash
git clone https://github.com/danushkka/cross-chain-rebase-token.git
cd cross-chain-rebase-token
forge install
```

### Environment Setup

Create a `.env` file in the root directory:

```env
MY_WALLET=0x<your-wallet-address>

SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/<your-api-key>
OP_SEPOLIA_RPC_URL=https://opt-sepolia.g.alchemy.com/v2/<your-api-key>

ETHERSCAN_API_KEY=<your-etherscan-api-key>

SEPOLIA_CHAIN_SELECTOR=16015286601757825753
OP_SEPOLIA_CHAIN_SELECTOR=5224473277236331295

SEPOLIA_LINK_ADDRESS=0x779877A7B0D9E8603169DdbD7836e478b4624789
OP_SEPOLIA_LINK_ADDRESS=0xE4aB69C077896252FAFBD49EFD26B5D171A32410

SEPOLIA_ROUTER=0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
OP_SEPOLIA_ROUTER=0x114A20A10b43D4115e5aeef7345a1A71d2a60C57
```

Load the variables:

```bash
source .env
```

> ⚠️ Never commit your `.env` file. Ensure it is listed in `.gitignore`.

Get testnet tokens:
- Sepolia ETH + LINK: https://faucets.chain.link/sepolia
- OP Sepolia ETH + LINK: https://faucets.chain.link/optimism-sepolia

---

## Deployment

### Step 1 — Deploy on Sepolia

```bash
forge script script/DeployTokenAndPool.s.sol:DeployTokenAndPool \
  --rpc-url $SEPOLIA_RPC_URL \
  --account <keystore-account> \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

Save the output addresses to your `.env`:
```env
SEPOLIA_TOKEN=0x...
SEPOLIA_POOL=0x...
```

### Step 2 — Deploy Vault on Sepolia

```bash
forge script script/DeployTokenAndPool.s.sol:DeployVault \
  --rpc-url $SEPOLIA_RPC_URL \
  --account <keystore-account> \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --sig "run(address)" $SEPOLIA_TOKEN \
  -vvvv
```

Save:
```env
SEPOLIA_VAULT=0x...
```

### Step 3 — Deploy on OP Sepolia

```bash
forge script script/DeployTokenAndPool.s.sol:DeployTokenAndPool \
  --rpc-url $OP_SEPOLIA_RPC_URL \
  --account <keystore-account> \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

Save:
```env
OP_TOKEN=0x...
OP_POOL=0x...
```

### Step 4 — Configure Sepolia Pool

```bash
forge script script/ConfigurePool.s.sol:ConfigurePool \
  --rpc-url $SEPOLIA_RPC_URL \
  --account <keystore-account> \
  --broadcast \
  --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
  $SEPOLIA_POOL \
  $OP_SEPOLIA_CHAIN_SELECTOR \
  $OP_POOL \
  $OP_TOKEN \
  false 0 0 \
  false 0 0 \
  -vvvv
```

### Step 5 — Configure OP Sepolia Pool

```bash
forge script script/ConfigurePool.s.sol:ConfigurePool \
  --rpc-url $OP_SEPOLIA_RPC_URL \
  --account <keystore-account> \
  --broadcast \
  --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
  $OP_POOL \
  $SEPOLIA_CHAIN_SELECTOR \
  $SEPOLIA_POOL \
  $SEPOLIA_TOKEN \
  false 0 0 \
  false 0 0 \
  -vvvv
```

### Step 6 — Deposit into Vault

> ⚠️ Make sure to call `deposit()` explicitly — sending ETH directly to the vault address will NOT mint tokens.

```bash
cast send $SEPOLIA_VAULT \
  "deposit()" \
  --value 0.01ether \
  --rpc-url $SEPOLIA_RPC_URL \
  --account <keystore-account>
```

Verify your token balance:

```bash
cast call $SEPOLIA_TOKEN \
  "balanceOf(address)(uint256)" \
  $MY_WALLET \
  --rpc-url $SEPOLIA_RPC_URL
```

### Step 7 — Bridge Tokens

```bash
forge script script/BridgeTokens.s.sol:BridgeTokens \
  --rpc-url $SEPOLIA_RPC_URL \
  --account <keystore-account> \
  --broadcast \
  --sig "run(address,uint256,address,address,address,uint64)" \
  $SEPOLIA_TOKEN \
  1000000000000000 \
  $MY_WALLET \
  $SEPOLIA_LINK_ADDRESS \
  $SEPOLIA_ROUTER \
  $OP_SEPOLIA_CHAIN_SELECTOR \
  -vvvv
```

Track the bridge transaction at https://ccip.chain.link — it typically takes 5–20 minutes to finalize.

---

## Usage

**Redeem tokens for ETH on Sepolia:**

```bash
cast send $SEPOLIA_VAULT \
  "redeem(uint256)" \
  <amount-in-wei> \
  --rpc-url $SEPOLIA_RPC_URL \
  --account <keystore-account>
```

Pass `type(uint256).max` to redeem your entire balance:

```bash
cast send $SEPOLIA_VAULT \
  "redeem(uint256)" \
  115792089237316195423570985008687907853269984665640564039457584007913129639935 \
  --rpc-url $SEPOLIA_RPC_URL \
  --account <keystore-account>
```

**Check accrued interest:**

```bash
cast call $SEPOLIA_TOKEN \
  "getAccumulatedInterestSinceLastInteraction(address)(uint256)" \
  $MY_WALLET \
  --rpc-url $SEPOLIA_RPC_URL
```

**Check current global interest rate:**

```bash
cast call $SEPOLIA_TOKEN \
  "getInterestRate()(uint256)" \
  --rpc-url $SEPOLIA_RPC_URL
```

---

## Deployed Contracts

### Sepolia

| Contract | Address |
|---|---|
| `RebaseToken` | [`0xf49BD0860169A9ec8Ac38b27188BA8970C770638`](https://sepolia.etherscan.io/address/0xf49BD0860169A9ec8Ac38b27188BA8970C770638) |
| `RebaseTokenPool` | [`0x43f45b7f1f1B0A6A483D634a7ed6615A7F0eA570`](https://sepolia.etherscan.io/address/0x43f45b7f1f1B0A6A483D634a7ed6615A7F0eA570) |
| `Vault` | [`0xe453298404967131275fd1a94e905022cc112c0c`](https://sepolia.etherscan.io/address/0xe453298404967131275fd1a94e905022cc112c0c) |

### OP Sepolia

| Contract | Address |
|---|---|
| `RebaseToken` | [`0x7f2e7adc9b5de9201c4f548abdfe286a02370f64`](https://sepolia-optimism.etherscan.io/address/0x7f2e7adc9b5de9201c4f548abdfe286a02370f64) |
| `RebaseTokenPool` | [`0x18b562fe65ad62bb1cceb637864b7c897ef4b537`](https://sepolia-optimism.etherscan.io/address/0x18b562fe65ad62bb1cceb637864b7c897ef4b537) |

---

## Network Details

| Network | Chain Selector | Router | LINK |
|---|---|---|---|
| Sepolia | `16015286601757825753` | `0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59` | `0x779877A7B0D9E8603169DdbD7836e478b4624789` |
| OP Sepolia | `5224473277236331295` | `0x114A20A10b43D4115e5aeef7345a1A71d2a60C57` | `0xE4aB69C077896252FAFBD49EFD26B5D171A32410` |

---

## Security Considerations

- **Interest rate can only decrease** — the owner cannot inflate rewards for new depositors at the expense of existing ones
- **Role-based minting** — only the Vault and Pool contracts hold `MINT_AND_BURN_ROLE`; the owner cannot mint arbitrarily
- **Interest materialized before burns** — `_mintAccruedInterest` is always called before burning to prevent interest loss
- **Rate preserved cross-chain** — the user's personal rate is encoded in the CCIP message, so it cannot be tampered with in transit
- **Not audited** — this is an educational project; do not use in production without a formal security audit

---

## Known Limitations

- **Vault only exists on Sepolia** — tokens bridged to OP Sepolia cannot be redeemed for ETH there; bridge back to Sepolia first
- **Vault requires explicit `deposit()` call** — sending ETH directly to the vault address triggers `receive()` and does not mint tokens
- **No yield source** — the vault does not deploy ETH into any yield protocol; interest payouts require the vault to be manually funded with ETH rewards
- **Single owner** — the owner can decrease the interest rate and grant roles; there is no timelock or multisig

---

## License

This project is licensed under the [MIT License](LICENSE).