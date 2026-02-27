# Olympia Treasury Contract

Immutable treasury vault for the ETC Olympia hard fork. Built on **OpenZeppelin Contracts v5.6.0** using the AccessControl role-based permission model.

## Overview

| | |
|---|---|
| **ECIP** | [ECIP-1112](https://ecips.ethereumclassic.org/ECIPs/ecip-1112) — Treasury Vault |
| **Funding** | [ECIP-1111](https://ecips.ethereumclassic.org/ECIPs/ecip-1111) — EIP-1559 basefee redirect |
| **Governance** | [ECIP-1113](https://ecips.ethereumclassic.org/ECIPs/ecip-1113) — OpenZeppelin AccessControl (current) |
| **Future** | [ECIP-1117](https://ecips.ethereumclassic.org/ECIPs/ecip-1117) — Futarchy DAO governance |
| **Chain** | Ethereum Classic (ETC mainnet 61, Mordor testnet 63) |
| **Solidity** | 0.8.28 |

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
│  OpenZeppelin AccessControl (ECIP-1113)     │
│  ├─ DEFAULT_ADMIN_ROLE  → manages roles     │
│  ├─ WITHDRAWER_ROLE     → withdraw(to, amt) │
│  └─ receive()           → accept ETC        │
└──────────────────┬──────────────────────────┘
                   │ grantRole(WITHDRAWER_ROLE)
                   ▼
┌─────────────────────────────────────────────┐
│  Future: Futarchy DAO (ECIP-1117)           │
│  - Prediction market-based spending         │
│  - Receives WITHDRAWER_ROLE from admin      │
│  - Admin WITHDRAWER_ROLE revoked            │
└─────────────────────────────────────────────┘
```

## How the Treasury Works

### Revenue: BaseFee State Credits

The Olympia hard fork activates [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) on Ethereum Classic. Unlike Ethereum mainnet (which burns the basefee), ETC redirects 100% of basefee revenue to the treasury address via [ECIP-1111](https://ecips.ethereumclassic.org/ECIPs/ecip-1111).

Each block, core-geth's `Finalize()` function credits `baseFee × gasUsed` directly to the treasury contract's balance. This is a **state credit**, not an on-chain transaction — there is no gas cost and no transaction appears in the block. Revenue scales with network usage: more transactions means higher basefee and more gas consumed.

This mechanism works identically for both **Type-0 (legacy)** and **Type-2 (EIP-1559)** transactions. Legacy transactions pay `gasPrice = baseFee + tip`, so the basefee portion still flows to the treasury regardless of which transaction type users adopt.

### The Contract: A Role-Gated Vault

The treasury contract is intentionally minimal — 39 lines of Solidity. It has exactly two capabilities:

1. **Receive ETC** — via the `receive()` function (for direct transfers) and via state credits from the consensus layer
2. **Withdraw ETC** — via `withdraw(to, amount)`, restricted to addresses holding `WITHDRAWER_ROLE`

The contract embeds no governance logic, no allocation policy, and no automatic distribution. It is **pure custody**. All spending decisions are made by whatever entity holds the `WITHDRAWER_ROLE` — an EOA, a multisig, or a DAO contract.

The contract is **immutable**: no proxy pattern, no upgrade mechanism, no selfdestruct. The treasury address is permanent across all governance phases. Only the role assignments change.

### Withdrawals

When `withdraw(to, amount)` is called:

1. **Authorization** — `onlyRole(WITHDRAWER_ROLE)` modifier checks the caller
2. **Validation** — Reverts if `to` is the zero address or `amount` exceeds the contract balance
3. **Transfer** — Sends ETC via low-level `call{value: amount}("")`
4. **Event** — Emits `Withdrawal(to, amount)` for on-chain auditability

If any step fails, the entire call reverts with a descriptive error:

| Error | Cause |
|-------|-------|
| `AccessControlUnauthorizedAccount(account, role)` | Caller lacks `WITHDRAWER_ROLE` |
| `OlympiaTreasury: zero address` | `to` is `address(0)` |
| `OlympiaTreasury: insufficient balance` | `amount` exceeds contract balance |
| `OlympiaTreasury: transfer failed` | Recipient rejected the transfer |

## OpenZeppelin Framework (ECIP-1113)

The treasury uses OpenZeppelin's **AccessControl** for role-based permissioning. This is the standard pattern for staged governance — deploy with admin control now, delegate to a DAO later without redeploying.

### Roles

| Role | Capability | Initial Holder |
|------|-----------|----------------|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke all roles | Deployer EOA |
| `WITHDRAWER_ROLE` | Call `withdraw(to, amount)` | Deployer EOA |

### Why AccessControl (not Ownable)

- **Multi-role**: Separate admin (role management) from withdrawer (spending)
- **Composable**: Grant `WITHDRAWER_ROLE` to any address — EOA, multisig, or DAO contract
- **Revocable**: Admin can revoke roles without redeployment
- **Standard**: Battle-tested OZ pattern used by Compound, Aave, and others

## Contract API Reference

### Native Functions

#### `constructor(address admin)`

Deploys the treasury and grants both `DEFAULT_ADMIN_ROLE` and `WITHDRAWER_ROLE` to `admin`.

#### `withdraw(address payable to, uint256 amount) external`

Transfers `amount` wei of ETC to `to`. Requires `WITHDRAWER_ROLE`. Emits `Withdrawal(to, amount)`.

#### `receive() external payable`

Accepts direct ETC transfers. No access control. Production funding arrives via consensus-layer state credits, but `receive()` enables testing and voluntary deposits.

### Constants

| Name | Value |
|------|-------|
| `WITHDRAWER_ROLE` | `0x10dac8c06a04bec0b551627dad28bc00d6516b0caacd1c7b345fcdb5211334e4` |
| `DEFAULT_ADMIN_ROLE` | `0x0000000000000000000000000000000000000000000000000000000000000000` |

### Events

| Event | Parameters |
|-------|-----------|
| `Withdrawal` | `address indexed to`, `uint256 amount` |

### Inherited from AccessControl

See [OpenZeppelin AccessControl docs](https://docs.openzeppelin.com/contracts/5.x/access-control) for full details.

| Function | Access | Description |
|----------|--------|-------------|
| `hasRole(bytes32, address) → bool` | Public (view) | Check if address holds role |
| `grantRole(bytes32, address)` | Role admin | Grant role to address |
| `revokeRole(bytes32, address)` | Role admin | Revoke role from address |
| `renounceRole(bytes32, address)` | Self only | Voluntarily surrender own role |
| `getRoleAdmin(bytes32) → bytes32` | Public (view) | Get admin role for a role |
| `supportsInterface(bytes4) → bool` | Public (view) | ERC-165 interface detection |

## Role Management Guide

All examples use Foundry's `cast` CLI. Set these environment variables first:

```bash
export TREASURY=0xCfE1e0ECbff745e6c800fF980178a8dDEf94bEe2
export RPC=http://localhost:8545  # Mordor local node
```

### Checking Roles

```bash
# Check if an address has WITHDRAWER_ROLE
cast call $TREASURY "hasRole(bytes32,address)(bool)" \
  0x10dac8c06a04bec0b551627dad28bc00d6516b0caacd1c7b345fcdb5211334e4 \
  $ADDRESS --rpc-url $RPC

# Check if an address has DEFAULT_ADMIN_ROLE
cast call $TREASURY "hasRole(bytes32,address)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $ADDRESS --rpc-url $RPC
```

### Checking Balance

```bash
cast balance $TREASURY --ether --rpc-url $RPC
```

### Withdrawing Funds

```bash
# Withdraw 10 ETC to a recipient (requires WITHDRAWER_ROLE)
cast send $TREASURY "withdraw(address,uint256)" \
  $RECIPIENT $(cast to-wei 10) \
  --private-key $PRIVATE_KEY --rpc-url $RPC --legacy
```

### Granting Roles

```bash
# Grant WITHDRAWER_ROLE to a DAO contract (requires DEFAULT_ADMIN_ROLE)
cast send $TREASURY "grantRole(bytes32,address)" \
  0x10dac8c06a04bec0b551627dad28bc00d6516b0caacd1c7b345fcdb5211334e4 \
  $DAO_ADDRESS \
  --private-key $PRIVATE_KEY --rpc-url $RPC --legacy
```

### Revoking Roles

```bash
# Revoke WITHDRAWER_ROLE from an address (requires DEFAULT_ADMIN_ROLE)
cast send $TREASURY "revokeRole(bytes32,address)" \
  0x10dac8c06a04bec0b551627dad28bc00d6516b0caacd1c7b345fcdb5211334e4 \
  $OLD_WITHDRAWER \
  --private-key $PRIVATE_KEY --rpc-url $RPC --legacy
```

### Renouncing Roles (Irreversible)

```bash
# Renounce your own DEFAULT_ADMIN_ROLE (CANNOT be undone)
cast send $TREASURY "renounceRole(bytes32,address)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $YOUR_ADDRESS \
  --private-key $PRIVATE_KEY --rpc-url $RPC --legacy
```

### Governance Transition Checklist

To transition from admin EOA to a DAO contract:

1. Deploy DAO contract
2. `grantRole(WITHDRAWER_ROLE, dao)` — DAO can now withdraw
3. Verify: `hasRole(WITHDRAWER_ROLE, dao)` returns `true`
4. Test: DAO withdraws a small amount
5. `grantRole(DEFAULT_ADMIN_ROLE, dao)` — DAO can now manage roles
6. `revokeRole(WITHDRAWER_ROLE, admin)` — Remove admin's withdrawal rights
7. `renounceRole(DEFAULT_ADMIN_ROLE, admin)` — **Irreversible.** Admin loses all authority.
8. Verify: `hasRole(DEFAULT_ADMIN_ROLE, admin)` returns `false`

> **Note:** All `cast send` commands use `--legacy` because ETC is pre-EIP-1559 until the Olympia hard fork activates. After activation, `--legacy` remains valid but Type-2 transactions also work.

## Staged Governance Evolution

The treasury contract is immutable — the address never changes, only role assignments evolve. This enables zero-downtime governance transitions without redeployment.

### Stage 1: Bootstrap (ECIP-1111 + 1112)

**Authority:** Core multisig (e.g., 3-of-5 maintainers)

The multisig holds both `DEFAULT_ADMIN_ROLE` and `WITHDRAWER_ROLE`. Treasury accumulates basefee revenue immediately after hard fork activation. The multisig handles urgent operational spending — client development, security audits, node hosting infrastructure. No DAO contracts exist yet; this is the minimum viable governance.

### Stage 2: DAO Handoff (+ ECIP-1113)

**Authority:** CoreDAO contract replaces multisig

The transition happens in two phases:

- **Phase 2a — Transition period:** Multisig grants `WITHDRAWER_ROLE` to CoreDAO. Both can operate temporarily. CoreDAO begins funding core infrastructure (client maintenance, audits, public RPC hosting).
- **Phase 2b — Full handoff:** Multisig grants `DEFAULT_ADMIN_ROLE` to CoreDAO, revokes its own `WITHDRAWER_ROLE`, then renounces `DEFAULT_ADMIN_ROLE`. This is **irreversible** — the multisig can never regain authority.

After handoff, CoreDAO holds both roles. The multisig has zero authority.

### Stage 3: Futarchy (+ ECIP-1117)

**Authority:** CoreDAO (admin + withdrawer) + FutarchyDAO (withdrawer)

CoreDAO (as admin) grants `WITHDRAWER_ROLE` to a FutarchyDAO contract that uses prediction markets for spending decisions. Both DAOs operate independently — neither blocks the other:

- **CoreDAO (~60%):** Essential infrastructure — client development, audits, node hosting
- **FutarchyDAO (~40%):** Ecosystem proposals — development grants, R&D funding, new features

CoreDAO remains admin and can revoke FutarchyDAO's access if needed.

### Stage 4: Miner Incentives (+ ECIP-1115)

**Authority:** CoreDAO + FutarchyDAO + LCurveDistributor

As [ECIP-1017](https://ecips.ethereumclassic.org/ECIPs/ecip-1017) disinflation reduces block rewards, CoreDAO enables an L-curve distributor to supplement miner income with treasury-funded distributions using logarithmic weighting (top miners receive more, with diminishing returns):

- **CoreDAO (~40%):** Core infrastructure
- **FutarchyDAO (~30%):** Ecosystem proposals
- **LCurveDistributor (~30%):** Miner incentive payments

All three are independent `WITHDRAWER_ROLE` holders.

### Edge Cases

**DAO Contract Migration** — When a DAO needs upgrading (e.g., OZ v5 → v6), the existing DAO (as admin) can authorize its own succession: grant roles to the new DAO, transfer `DEFAULT_ADMIN_ROLE`, then the new DAO revokes the old one's access. Zero downtime, zero fund loss, treasury address unchanged.

**Legacy Transaction Adoption** — The EIP-1559 basefee mechanism works identically for all transaction types. Legacy transactions pay `gasPrice = baseFee + tip`, so `baseFee × gasUsed` flows to the treasury regardless of whether users adopt Type-2 transactions.

### Pattern: PaymentSplitter for Fixed Splits

When multiple DAOs share treasury access (Stages 3-4), percentage splits can be enforced using a **PaymentSplitter** contract positioned between the treasury and the DAOs:

```
Treasury ──withdraw──▶ PaymentSplitter ──release()──▶ CoreDAO (40%)
         (WITHDRAWER)                  ──release()──▶ FutarchyDAO (30%)
                                       ──release()──▶ LCurveDistributor (30%)
```

The PaymentSplitter holds `WITHDRAWER_ROLE` on the treasury. A periodic "drip" call withdraws funds from the treasury into the splitter. Each DAO calls `release()` to pull its proportional share — a [pull-payment model](https://docs.openzeppelin.com/contracts/5.x/api/utils#Address) where recipients claim rather than receiving pushes.

This abstracts percentage logic **outside** the treasury contract, keeping the treasury's role model clean: one `WITHDRAWER_ROLE` holder (the splitter) instead of three.

> **Note:** OpenZeppelin [removed PaymentSplitter in v5.0.0](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/4276). A custom implementation based on the [v4 PaymentSplitter](https://docs.openzeppelin.com/contracts/4.x/api/finance#PaymentSplitter) pattern (~50 lines) would be needed. The core math is straightforward: `payee_share = (total_received × payee_shares) / total_shares - already_released`.

## Deployments

| Chain | Address | Block |
|-------|---------|-------|
| Mordor (63) | `0xCfE1e0ECbff745e6c800fF980178a8dDEf94bEe2` | [Deployed](broadcast/Deploy.s.sol/63/) |
| ETC Mainnet (61) | — | Pending Olympia activation |

CREATE2 salt (`keccak256("OLYMPIA_TREASURY_V1")`) ensures deterministic addresses across chains given the same deployer.

## Setup

```bash
cp .env.example .env
# Edit .env with your wallet private key and RPC URLs
```

## Build & Test

```bash
forge build
forge test -vv
```

33 tests across 3 files:
- **`OlympiaTreasury.t.sol`** — 10 unit tests: role assignment, withdrawal, revocation, events, edge cases (zero address, insufficient balance, unauthorized access)
- **`StagedEvolution.t.sol`** — 6 integration tests: 4 governance stages (bootstrap → DAO → futarchy → L-curve) + 2 edge cases (DAO migration, legacy tx adoption)
- **`SecurityInvariants.t.sol`** — 17 security proofs: immutability (no selfdestruct, no delegatecall, no proxy), access control hardening, reentrancy resistance, fund safety, and fuzz tests (amounts, callers, recipients)

## Deploy

```bash
source .env

# Mordor testnet (--legacy required: pre-EIP-1559)
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $MORDOR_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --legacy

# ETC mainnet (--legacy required: pre-EIP-1559)
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $ETC_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --legacy
```

After deployment, update `OlympiaTreasuryAddress` in `core-geth/params/config_mordor.go` (or `config_classic.go` for mainnet).

## Project Structure

| File | Description |
|------|-------------|
| `src/OlympiaTreasury.sol` | Treasury vault — AccessControl + withdraw + receive |
| `test/OlympiaTreasury.t.sol` | 10 unit tests |
| `test/StagedEvolution.t.sol` | 6 integration tests (4 governance stages + 2 edge cases) |
| `test/SecurityInvariants.t.sol` | 17 security proofs (immutability, reentrancy, access control, fuzz) |
| `test/mocks/MockCoreDAO.sol` | Simulates ECIP-1113 traditional DAO governance |
| `test/mocks/MockFutarchyDAO.sol` | Simulates ECIP-1117 futarchy prediction market DAO |
| `test/mocks/MockLCurveDistributor.sol` | Simulates ECIP-1115 L-curve miner distribution |
| `script/Deploy.s.sol` | CREATE2 deterministic deployment |
| `broadcast/Deploy.s.sol/63/` | Mordor deployment logs |

## Dependencies

| Package | Version |
|---------|---------|
| OpenZeppelin Contracts | v5.6.0 |
| Forge Std | v1.15.0 |
| Solidity | 0.8.28 |
| Foundry | Latest |

## Related ECIPs

| ECIP | Title | Status |
|------|-------|--------|
| [ECIP-1111](https://ecips.ethereumclassic.org/ECIPs/ecip-1111) | Olympia Base Fee Market | Implemented in core-geth |
| [ECIP-1112](https://ecips.ethereumclassic.org/ECIPs/ecip-1112) | Olympia Treasury Contract | **This repo** |
| [ECIP-1113](https://ecips.ethereumclassic.org/ECIPs/ecip-1113) | DAO Governance Framework | Draft |
| [ECIP-1114](https://ecips.ethereumclassic.org/ECIPs/ecip-1114) | ECFP Funding Process | Draft |
| [ECIP-1115](https://ecips.ethereumclassic.org/ECIPs/ecip-1115) | L-Curve Smoothing | Draft |
| [ECIP-1116](https://ecips.ethereumclassic.org/ECIPs/ecip-1116) | Base Fee Development Funding | Draft |
| [ECIP-1117](https://ecips.ethereumclassic.org/ECIPs/ecip-1117) | Futarchy Governance | Draft |
| [ECIP-1118](https://ecips.ethereumclassic.org/ECIPs/ecip-1118) | Futarchy Funding & Disbursement | Draft |
| [ECIP-1119](https://ecips.ethereumclassic.org/ECIPs/ecip-1119) | Sanctions Constraint | Draft |
| [ECIP-1121](https://ecips.ethereumclassic.org/ECIPs/ecip-1121) | Execution Client Alignment | Implemented in core-geth |
