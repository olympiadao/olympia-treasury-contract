# Olympia Treasury Contract

## Project Description
ETC Olympia hard fork treasury vault (ECIP-1112). Pure Solidity, no OpenZeppelin dependency. Single authorized caller (`immutable executor`) pre-computed deterministically. Treasury deploys via CREATE (nonce-based), Executor via CREATE2. Receives basefee revenue from EIP-1559 via state credit (ECIP-1111). Executor is the OlympiaExecutor contract from the governance suite (ECIP-1113).

**Repo:** `olympiadao/olympia-treasury-contract`

## Tech Stack
- Solidity 0.8.28
- Foundry (Forge, Cast, Anvil)
- Forge Std v1.15.0
- **No OpenZeppelin dependency**
- Target chains: Mordor testnet (63), ETC mainnet (61)

## Quick Commands
```bash
forge build          # Compile
forge test -vv       # Run tests (33 tests)
forge fmt            # Format Solidity
forge snapshot       # Gas snapshots
```

## Deploy
```bash
source .env
# Mordor (--legacy required until EIP-1559 activates at block 15,800,850)
forge script script/Deploy.s.sol:DeployScript --rpc-url $MORDOR_RPC_URL --private-key $PRIVATE_KEY --broadcast --legacy
```

## Project Structure
```
src/OlympiaTreasury.sol            # Treasury vault (immutable executor)
src/interfaces/IOlympiaTreasury.sol # ECIP-1112 interface
test/OlympiaTreasury.t.sol         # 15 unit tests
test/SecurityInvariants.t.sol      # 12 security proofs
test/PreGovernance.t.sol           # 6 pre-governance tests
test/mocks/MockExecutor.sol        # Mock executor for testing
test/mocks/ReentrantAttacker.sol   # Reentrancy test mock
test/mocks/RejectingRecipient.sol  # ETH rejection test mock
script/Deploy.s.sol                # CREATE deployment (executor pre-computed via CREATE2)
```

## Branch Strategy

- **`demo_v0.2`**: Pure Solidity, immutable executor, CREATE deployment (executor via CREATE2 salt `OLYMPIA_DEMO_V0_2`)
- **`main`**: Production (future, post-Olympia Cancun activation)

## Boundaries
### Always Do
- Run `forge test` before committing
- Treasury uses CREATE (nonce-based), executor uses CREATE2 — see Bootstrap Problem in README
- Keep contract minimal — governance logic goes in separate contracts

### Ask First
- Changing the CREATE2 salt
- Any mainnet deployment
- Modifying the IOlympiaTreasury interface (affects governance contracts)

### Never Do
- Commit `.env` files
- Deploy without `--broadcast` flag verification
- Modify deployed contract addresses in broadcast logs
- Add OpenZeppelin or any external dependency (contract must remain pure Solidity)
