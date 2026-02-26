# Olympia Treasury Contract

## Project Description
ETC Olympia hard fork treasury vault (ECIP-1112). Built on OpenZeppelin AccessControl (ECIP-1113). Receives basefee revenue from EIP-1559 via state credit (ECIP-1111) and provides role-gated withdrawal. Staged governance — admin EOA now, futarchy DAO (ECIP-1117) later.

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
# Mordor (--legacy required until EIP-1559 activates at block 15,800,850)
forge script script/Deploy.s.sol:DeployScript --rpc-url $MORDOR_RPC_URL --private-key $PRIVATE_KEY --broadcast --legacy
# ETC mainnet
forge script script/Deploy.s.sol:DeployScript --rpc-url $ETC_RPC_URL --private-key $PRIVATE_KEY --broadcast --legacy
```

## Project Structure
```
src/OlympiaTreasury.sol      # Treasury vault contract
test/OlympiaTreasury.t.sol   # 10 tests
script/Deploy.s.sol          # CREATE2 deployment
broadcast/Deploy.s.sol/63/   # Mordor deployment logs
```

## Deployments
- **Mordor:** `0xCfE1e0ECbff745e6c800fF980178a8dDEf94bEe2`
- **ETC mainnet:** Not yet deployed

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
