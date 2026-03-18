# Olympia Treasury Contract

Immutable treasury vault for the ETC Olympia hard fork (ECIP-1112). **Pure Solidity** — no OpenZeppelin dependency. Single authorized caller (`immutable executor`) pre-computed via CREATE2 before deployment.

## Overview

| | |
|---|---|
| **ECIP** | [ECIP-1112](https://ecips.ethereumclassic.org/ECIPs/ecip-1112) — Treasury Vault |
| **Funding** | [ECIP-1111](https://ecips.ethereumclassic.org/ECIPs/ecip-1111) — EIP-1559 basefee redirect |
| **Governance** | [ECIP-1113](https://ecips.ethereumclassic.org/ECIPs/ecip-1113) — OlympiaExecutor (via CREATE2) |
| **Chain** | Ethereum Classic (ETC mainnet 61, Mordor testnet 63) |
| **Solidity** | 0.8.28 |
| **OZ Dependency** | None |

## Architecture

```
┌─────────────────────────────────────────────┐
│  core-geth (consensus layer)                │
│  Finalize() credits baseFee × gasUsed       │
│  to OlympiaTreasuryAddress each block       │
└──────────────────┬──────────────────────────┘
                   │ state credit (no tx needed)
                   ▼
┌─────────────────────────────────────────────┐
│  OlympiaTreasury (this contract)            │
│                                             │
│  address public immutable executor          │
│  ├─ withdraw(to, amount) → executor only    │
│  └─ receive()            → accept ETC       │
│                                             │
│  No admin. No roles. No upgrade path.       │
└──────────────────┬──────────────────────────┘
                   │ executor = pre-computed CREATE2
                   ▼
┌─────────────────────────────────────────────┐
│  OlympiaExecutor (governance contracts)     │
│  Governor → Timelock → Executor → Treasury  │
│  Deployed at pre-computed CREATE2 address    │
└─────────────────────────────────────────────┘
```

## The Bootstrap Problem

How does the Treasury know its executor before the executor exists?

**Answer: Pre-computed CREATE2.** The OlympiaExecutor's future CREATE2 address is hardcoded as the Treasury's `immutable executor` at deployment time. That address has no code initially — any call to `withdraw()` reverts because no one can call from an address with no code. Treasury accumulates passively.

When the DAO contracts are ready (audited, testnet-validated, community-reviewed), the Executor is deployed to that exact predetermined address using CREATE2 with the published salt and bytecode. From that point, withdrawals become possible. No admin key, no setter function, no transition ceremony.

This makes the bootstrap question **verifiable rather than trust-based**: does the deployed DAO bytecode match the executor address hardcoded in the treasury? Anyone can check independently.

## How the Treasury Works

### Revenue: BaseFee State Credits

The Olympia hard fork activates [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) on Ethereum Classic. Unlike Ethereum mainnet (which burns the basefee), ETC redirects 100% of basefee revenue to the treasury address via [ECIP-1111](https://ecips.ethereumclassic.org/ECIPs/ecip-1111).

Each block, core-geth's `Finalize()` function credits `baseFee × gasUsed` directly to the treasury contract's balance. This is a **state credit**, not an on-chain transaction — there is no gas cost and no transaction appears in the block.

### The Contract: An Immutable Vault

The treasury contract is ~30 lines of pure Solidity. It has exactly two capabilities:

1. **Receive ETC** — via the `receive()` function (for direct transfers) and via state credits from the consensus layer
2. **Withdraw ETC** — via `withdraw(to, amount)`, restricted to the single `immutable executor` address

The contract embeds no governance logic, no allocation policy, no role management, and no admin functions. It is **pure custody** with a single authorized caller.

The contract is **immutable**: no proxy pattern, no upgrade mechanism, no selfdestruct, no setter for the executor. The executor address is baked into the bytecode at construction time and can never change.

### Why No OpenZeppelin?

| | Demo v0.1 (OZ 5.6) | Demo v0.2 (Pure Solidity) |
|---|---|---|
| Lines of code | ~694 (inherited) | ~30 |
| Attack surface | AccessControl, DefaultAdminRules, ERC165 | None |
| Admin functions | 15+ externally callable | 0 |
| Upgrade path | Role transfer | None (immutable) |
| Bytecode audit | Requires OZ source verification | Self-contained, trivially auditable |
| Duplicate execution | N/A (handled by TimelockController) | N/A (handled by TimelockController) |

The treasury is a dumb vault: receive ETC, send ETC to one authorized address. OZ's role-based access control was appropriate for v0.1's bootstrap phase (admin EOA model). For v0.2, the executor is pre-determined — there's nothing to configure.

## Contract API

### `constructor(address _executor)`

Sets the immutable executor. Reverts if `_executor` is `address(0)`.

### `withdraw(address payable to, uint256 amount) external`

Transfers `amount` wei of ETC to `to`. Only callable by the executor. Emits `Withdrawal(to, amount)`.

| Error | Cause |
|-------|-------|
| `Unauthorized()` | Caller is not the executor |
| `ZeroAddress()` | `to` is `address(0)` |
| `InsufficientBalance()` | `amount` exceeds contract balance |
| `TransferFailed()` | Recipient rejected the transfer |

### `receive() external payable`

Accepts direct ETC transfers. No access control. Emits `Received(from, amount)`.

### `executor() external view returns (address)`

Returns the immutable executor address.

## Interface

```solidity
interface IOlympiaTreasury {
    event Withdrawal(address indexed to, uint256 amount);
    event Received(address indexed from, uint256 amount);
    function executor() external view returns (address);
    function withdraw(address payable to, uint256 amount) external;
}
```

## Deployments

### Demo v0.2 (Pre-Olympia, OZ 5.1 Governance)

| Chain | Address | Salt |
|-------|---------|------|
| Mordor (63) | TBD | `keccak256("OLYMPIA_DEMO_V0_2")` |

### Demo v0.1 (OZ 5.6 AccessControlDefaultAdminRules)

Preserved on the `demo_v0.1` branch.

| Chain | Address | Salt |
|-------|---------|------|
| Mordor (63) | `0xd6165F3aF4281037bce810621F62B43077Fb0e37` | `keccak256("OLYMPIA_DEMO_V0_1")` |
| ETC Mainnet (61) | `0xd6165F3aF4281037bce810621F62B43077Fb0e37` | `keccak256("OLYMPIA_DEMO_V0_1")` |

## Build & Test

```bash
forge build
forge test -vv
```

33 tests across 3 files:
- **`OlympiaTreasury.t.sol`** — 15 unit tests: constructor, withdraw (happy path, unauthorized, zero address, insufficient balance, entire balance, zero amount, fuzz), receive
- **`SecurityInvariants.t.sol`** — 12 security proofs: bytecode checks (no SELFDESTRUCT/DELEGATECALL/CALLCODE/proxy), immutability, bytecode size <1KB, gas bound, interface compliance, reentrancy resistance, fuzz
- **`PreGovernance.t.sol`** — 6 pre-governance tests: accumulation without executor code, non-executor reverts, executor has no code, donations tracked, cumulative balance

## Deploy

```bash
source .env

# Mordor testnet (--legacy required: pre-EIP-1559)
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $MORDOR_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --legacy
```

## Project Structure

| File | Description |
|------|-------------|
| `src/OlympiaTreasury.sol` | Treasury vault — immutable executor, withdraw, receive |
| `src/interfaces/IOlympiaTreasury.sol` | ECIP-1112 interface |
| `test/OlympiaTreasury.t.sol` | 15 unit tests |
| `test/SecurityInvariants.t.sol` | 12 security proofs |
| `test/PreGovernance.t.sol` | 6 pre-governance tests |
| `test/mocks/MockExecutor.sol` | Calls treasury.withdraw() |
| `test/mocks/ReentrantAttacker.sol` | Re-enters withdraw() in receive() |
| `test/mocks/RejectingRecipient.sol` | Contract that rejects ETH |
| `script/Deploy.s.sol` | CREATE2 deterministic deployment |

## Dependencies

| Package | Version |
|---------|---------|
| Forge Std | v1.15.0 |
| Solidity | 0.8.28 |
| Foundry | Latest |

## Branch Strategy

- **`demo_v0.2`**: Pure Solidity, immutable executor, CREATE2 salt `OLYMPIA_DEMO_V0_2`
- **`demo_v0.1`**: OZ 5.6 AccessControlDefaultAdminRules, salt `OLYMPIA_DEMO_V0_1` (deployed Mordor + ETC mainnet)
- **`main`**: Production (future, after Olympia activates Cancun)

## Related ECIPs

| ECIP | Title | Status |
|------|-------|--------|
| [ECIP-1111](https://ecips.ethereumclassic.org/ECIPs/ecip-1111) | Olympia Base Fee Market | Implemented (3 clients) |
| [ECIP-1112](https://ecips.ethereumclassic.org/ECIPs/ecip-1112) | Olympia Treasury Contract | **This repo** |
| [ECIP-1113](https://ecips.ethereumclassic.org/ECIPs/ecip-1113) | DAO Governance Framework | Draft |
| [ECIP-1114](https://ecips.ethereumclassic.org/ECIPs/ecip-1114) | ECFP Funding Process | Draft |
| [ECIP-1119](https://ecips.ethereumclassic.org/ECIPs/ecip-1119) | Sanctions Constraint | Draft |
| [ECIP-1121](https://ecips.ethereumclassic.org/ECIPs/ecip-1121) | Execution Client Alignment | Implemented (3 clients) |

## License

MIT
