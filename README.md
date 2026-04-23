# Lido Protocol Anomaly Sentinel

Drosera Traps monitoring Lido protocol internal health on Ethereum Mainnet.

## Deployed Traps

| Version | Trap Address | Response Contract | Status |
|---------|-------------|-------------------|--------|
| V2 | [0x8E847b...947E](https://etherscan.io/address/0x8E847b7E28C4C33aAEB4F65b248cB23a804f947E) | [0x39135d...178d5](https://etherscan.io/address/0x39135dE7E43f06284Ca865DA02f53C04C8F178d5) | ✅ Active |
| V3 | [0x9D1BDf...d92](https://etherscan.io/address/0x9D1BDf9Af513AFDeCC8fF8107ceDdFf4748Abd92) | [0x9E9bf4...c47](https://etherscan.io/address/0x9E9bf4FaAD8661421c423a30b49d7B8c49041c47) | ✅ Active |

## Detection Logic

### V2
- **Check A** — Pooled ETH collapse > 5%
- **Check B** — wstETH redemption rate drop > 3% (sustained)
- **Check C** — stETH/wstETH rate inconsistency > 50 bps (sustained)
- **Alert A/B** — Early warnings at 2% / 1% thresholds

### V3 (Current)
- **Check A** — Pooled ETH collapse > 5% (sustained, mid confirmation required)
- **Check B** — wstETH redemption rate drop > 3% (sustained)
- **Check C** — stETH/wstETH rate inconsistency > 30 bps (tightened)
- **Check D** 🆕 — Withdrawal queue stress: unfinalizedStETH > 15% of pooled
- **Alert A/B/C** — Early warnings including queue build-up > 8%

## Contracts Monitored
- stETH: `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`
- wstETH: `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`
- WithdrawalQueue (V3): `0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1`

## Built with
- [Drosera Network](https://drosera.io)
- Foundry
- Solidity ^0.8.20

## Author
[@DAOmindbreaker](https://github.com/DAOmindbreaker)
