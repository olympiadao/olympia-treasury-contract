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

## Staged Governance

1. **Phase 1 — Admin EOA (now):** Deployer holds both roles. Simple, auditable.
2. **Phase 2 — Futarchy DAO (ECIP-1117):** Deploy futarchy contract, grant it `WITHDRAWER_ROLE`. Both admin and DAO can withdraw during transition.
3. **Phase 3 — DAO Only:** Revoke admin's `WITHDRAWER_ROLE`. DAO is sole spender. Admin retains role management for emergency governance changes.

The contract is **immutable** — no upgradeable proxy. The treasury address stays constant across all governance phases. Only the role assignments change.

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

10 tests covering: role assignment, withdrawal, revocation, events, edge cases (zero address, insufficient balance, unauthorized access).

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
| `test/OlympiaTreasury.t.sol` | 10 Forge tests |
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
| [ECIP-1111](https://ecips.ethereumclassic.org/ECIPs/ecip-1111) | EIP-1559 + basefee treasury redirect | Implemented in core-geth |
| [ECIP-1112](https://ecips.ethereumclassic.org/ECIPs/ecip-1112) | Treasury vault contract | **This repo** |
| [ECIP-1113](https://ecips.ethereumclassic.org/ECIPs/ecip-1113) | OZ AccessControl governance | **This repo** |
| [ECIP-1117](https://ecips.ethereumclassic.org/ECIPs/ecip-1117) | Futarchy DAO governance | Future — separate contract |
| [ECIP-1121](https://ecips.ethereumclassic.org/ECIPs/ecip-1121) | Execution layer EIP alignment | Implemented in core-geth |
