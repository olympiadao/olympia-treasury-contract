# Olympia Treasury Contract — Copilot Instructions

## Tech Stack
- Solidity 0.8.28, Foundry, OpenZeppelin v5.6.0
- Target: ETC (PoW chain, chain IDs 61/63)

## Rules
- All contracts use SPDX-License-Identifier: MIT
- Use OpenZeppelin AccessControl for role management
- Use CREATE2 for deterministic deployment addresses
- Tests use Forge Test with vm.prank/vm.deal/vm.expectRevert
- No upgradeable proxies — contracts are immutable

## Protected Files
- `broadcast/` — on-chain deployment records, never modify
- `.env` — never commit

## Validation
```bash
forge build && forge test -vv
```
