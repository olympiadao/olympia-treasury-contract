# Olympia Treasury Contract (ECIP-1112)

ETC Olympia hard fork treasury vault. Receives basefee revenue from EIP-1559 via state credit (ECIP-1111) and provides role-gated withdrawal via OpenZeppelin AccessControl.

## Architecture

```
┌─────────────────────────────────────────────┐
│  core-geth (consensus layer)                │
│  Finalize() credits baseFee * gasUsed       │
│  to OlympiaTreasuryAddress each block       │
└──────────────────┬──────────────────────────┘
                   │ state credit (no tx needed)
                   ▼
┌─────────────────────────────────────────────┐
│  OlympiaTreasury (this contract)            │
│  - AccessControl: ADMIN + WITHDRAWER roles  │
│  - withdraw(to, amount)                     │
│  - receive() for direct transfers           │
└──────────────────┬──────────────────────────┘
                   │ grantRole(WITHDRAWER_ROLE)
                   ▼
┌─────────────────────────────────────────────┐
│  Future: Futarchy DAO / Governance          │
│  - Prediction market-based spending         │
│  - Gets WITHDRAWER_ROLE from admin          │
└─────────────────────────────────────────────┘
```

## Staged Governance

1. **Phase 1 (now):** Admin EOA/multisig controls withdrawals
2. **Phase 2:** Deploy futarchy DAO, grant it `WITHDRAWER_ROLE`
3. **Phase 3:** Revoke admin's `WITHDRAWER_ROLE`, DAO is sole spender

## Setup

```bash
cp .env.example .env
# Edit .env with your Mordor wallet private key and RPC URL
```

## Build & Test

```bash
forge build
forge test -vv
```

## Deploy to Mordor (Chain 63)

```bash
source .env
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $MORDOR_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

After deployment, update `OlympiaTreasuryAddress` in `core-geth/params/config_mordor.go` with the deployed address.

## Deploy to ETC Mainnet (Chain 61)

```bash
source .env
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $ETC_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

CREATE2 salt ensures the same address on both chains (given same deployer).

## Contract

| File | Description |
|------|-------------|
| `src/OlympiaTreasury.sol` | Treasury vault with AccessControl |
| `test/OlympiaTreasury.t.sol` | 10 tests covering roles, withdrawal, events |
| `script/Deploy.s.sol` | CREATE2 deployment script |

## Dependencies

- OpenZeppelin Contracts v5.6.0
- Forge Std v1.15.0
- Solidity 0.8.28
