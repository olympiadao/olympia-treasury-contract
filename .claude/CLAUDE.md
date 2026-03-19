# Olympia Treasury Contract

## Project Description

> **Demo v0.1** — Not Olympia ECIP spec compliant. Deployed for fast iterative development to build project scaffolding. Not for production use. See `demo_v0.2` for the spec-aligned deployment.

ETC Olympia hard fork treasury vault (ECIP-1112). Built on OpenZeppelin AccessControlDefaultAdminRules (v5.6, ECIP-1113) with 2-step admin transfer and 600s delay. Receives basefee revenue from EIP-1559 via state credit (ECIP-1111) and provides role-gated withdrawal. Staged governance — admin EOA now, 2-step transfer to futarchy DAO (ECIP-1117) later.

## Tech Stack
- Solidity 0.8.28
- Foundry (Forge, Cast, Anvil)
- OpenZeppelin Contracts v5.6.0
- Target chains: Mordor testnet (63), ETC mainnet (61)

## Quick Commands
```bash
forge build          # Compile
forge test -vv       # Run tests
forge fmt            # Format Solidity
forge snapshot       # Gas snapshots
```

## Deploy
```bash
source .env
# Mordor (--legacy required until Olympia activates EIP-1559)
forge script script/Deploy.s.sol:DeployScript --rpc-url $MORDOR_RPC_URL --private-key $PRIVATE_KEY --broadcast --legacy
# ETC mainnet
forge script script/Deploy.s.sol:DeployScript --rpc-url $ETC_RPC_URL --private-key $PRIVATE_KEY --broadcast --legacy
```

## Project Structure
```
src/OlympiaTreasury.sol        # Treasury vault contract (AccessControlDefaultAdminRules)
test/OlympiaTreasury.t.sol     # 10 unit tests
test/StagedEvolution.t.sol     # 6 integration tests (governance lifecycle)
test/SecurityInvariants.t.sol  # 22 security proofs
test/mocks/MockCoreDAO.sol     # Mock DAO for integration tests
script/Deploy.s.sol            # CREATE2 deployment (salt: OLYMPIA_DEMO_V0_1)
broadcast/Deploy.s.sol/63/     # Mordor deployment logs
broadcast/Deploy.s.sol/61/     # ETC mainnet deployment logs
```

## Deployments
- **Mordor:** `0xd6165F3aF4281037bce810621F62B43077Fb0e37`
- **ETC mainnet:** `0xd6165F3aF4281037bce810621F62B43077Fb0e37`

## Boundaries
### Always Do
- Run `forge test` before committing
- Use CREATE2 for deterministic addresses
- Keep contract minimal — governance logic goes in separate contracts

### Ask First
- Adding new roles beyond WITHDRAWER_ROLE
- Changing the CREATE2 salt
- Any mainnet deployment

### Never Do
- Commit `.env` files
- Deploy without `--broadcast` flag verification
- Modify deployed contract addresses in broadcast logs
