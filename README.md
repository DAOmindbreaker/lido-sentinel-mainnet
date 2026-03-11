# stETH Depeg Sentinel — Drosera Trap

A Drosera Trap that monitors the Lido wstETH/stETH ratio on Hoodi testnet
and triggers an alert if a potential depeg event is detected.

## Use Case

**Liquid Restaking — Mitigating Depegs**

Lido stETH is one of the most widely used liquid staking tokens in DeFi.
A sudden depeg between wstETH and ETH can cause cascading liquidations
across lending protocols and destabilize the broader DeFi ecosystem.

This Trap provides an automated early warning system for such events.

## How It Works

1. **collect()** — Reads the current ETH-per-wstETH rate from Lido's wstETH
   contract on Hoodi testnet every block sample
2. **shouldRespond()** — Compares current rate vs previous rate
3. If the rate drops more than **5%** → Trap triggers an alert

## Threshold

| Parameter | Value |
|---|---|
| Depeg Threshold | 5% drop |
| Block Sample Size | 10 blocks |
| Cooldown Period | 33 blocks |

## Contracts Used (Hoodi Testnet)

| Contract | Address |
|---|---|
| wstETH (Lido official) | `0x7E99eE3C66636DE415D2d7C880938F2f40f94De4` |
| Drosera Response Contract | `0x25E2CeF36020A736CF8a4D2cAdD2EBE3940F4608` |

## References

- [Drosera Use Cases — Liquid Restaking](https://dev.drosera.io/use-cases)
- [Lido Deployed Contracts — Hoodi](https://docs.lido.fi/deployed-contracts/hoodi)

## Author

- Discord: aymgeprexlevmax
- GitHub: DAOmindbreaker
