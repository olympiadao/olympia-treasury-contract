# Olympia Treasury Contract

Immutable treasury vault for the ETC Olympia hard fork (ECIP-1112). **Pure Solidity** — no OpenZeppelin dependency. Single authorized caller (`immutable executor`) pre-computed before deployment.

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

## Deterministic Deployment

The OlympiaExecutor's CREATE2 address is pre-computed and hardcoded as the Treasury's `immutable executor` at deployment time. Before the Executor contract is deployed, the executor address has no code and all `withdraw()` calls revert. Once the Executor is deployed to the pre-computed address, withdrawals become possible.

Treasury deploys via **CREATE** (`address = f(deployer, nonce)`), Executor deploys via **CREATE2** (`address = f(deployer, salt, initcodeHash)`). Both contracts have immutable constructor args pointing to each other. CREATE2 addresses depend on constructor args (part of initcode hash), so mutual CREATE2 would require solving `x = hash(..., y)` and `y = hash(..., x)` — impossible with keccak256. CREATE breaks this cycle because its address is independent of constructor args. Per ECIP-1112 §Deterministic Deployment: *"An implementation MAY use CREATE or CREATE2, but the resulting address MUST be predetermined and published in advance of deployment."*

All governance contracts use CREATE2 via the [deterministic deployer factory](https://github.com/Arachnid/deterministic-deployment-proxy) (`0x4e59b44847b379578588920cA78FbF26c0B4956C`). `PrecomputeAddresses.s.sol` in the governance repo computes all addresses for both repos.

## Revenue

[ECIP-1111](https://ecips.ethereumclassic.org/ECIPs/ecip-1111) activates [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) on Ethereum Classic. ETC redirects 100% of basefee revenue to the treasury address (Ethereum mainnet burns the basefee). Each block, the execution client's `Finalize()` function credits `baseFee × gasUsed` to the treasury contract's balance as a state credit (no on-chain transaction, no gas cost).

## Properties

| Property | Value |
|---|---|
| Lines of code | ~30 |
| OpenZeppelin dependency | None |
| Attack surface | None |
| Admin functions | 0 |
| Upgrade path | None (immutable) |
| Bytecode audit | Self-contained |
| Duplicate execution prevention | TimelockController (ECIP-1113) |

Capabilities: `receive()` accepts ETC transfers and state credits. `withdraw(to, amount)` transfers ETC to the specified recipient, restricted to the single `immutable executor` address. No governance logic, no role management, no proxy pattern, no selfdestruct.

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

### Demo v0.2 (Pre-Olympia, OZ 5.1 Governance) — Deployed

Treasury deployed via **CREATE** (nonce-based). Governance contracts deployed via **CREATE2**. All source code verified on Blockscout.

Deployer: `0x7C3311F29e318617fed0833E68D6522948AaE995` (fresh EOA, nonce 0)

| Chain | Treasury | Executor | Blockscout |
|-------|----------|----------|------------|
| Mordor (63) | `0x035b2e3c189B772e52F4C3DA6c45c84A3bB871bf` | `0x64624f74F77639CbA268a6c8bEDC2778B707eF9a` | [View](https://etc-mordor.blockscout.com/address/0x035b2e3c189b772e52f4c3da6c45c84a3bb871bf) |
| ETC Mainnet (61) | `0x035b2e3c189B772e52F4C3DA6c45c84A3bB871bf` | `0x64624f74F77639CbA268a6c8bEDC2778B707eF9a` | [View](https://etc.blockscout.com/address/0x035b2e3c189b772e52f4c3da6c45c84a3bb871bf) |

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
| `script/Deploy.s.sol` | CREATE deployment (nonce-based, executor pre-computed via CREATE2) |

## Dependencies

| Package | Version |
|---------|---------|
| Forge Std | v1.15.0 |
| Solidity | 0.8.28 |
| Foundry | Latest |

## Branch Strategy

- **`demo_v0.2`**: Pure Solidity, immutable executor, CREATE deployment (executor via CREATE2 salt `OLYMPIA_DEMO_V0_2`)
- **`main`**: Production (future, after Olympia activates Cancun)

## Related

- [Olympia Governance Contracts](https://github.com/olympiadao/olympia-governance-contracts) — Governor, Executor, ECFPRegistry, SanctionsOracle, MemberNFT (ECIP-1113/1114/1119)
- [Olympia Framework](https://github.com/olympiadao/olympia-framework) — Full specification library (11 ECIPs)
- [Olympia App](https://github.com/olympiadao/olympia-app) — Governance dApp (Next.js 16 + wagmi)

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
