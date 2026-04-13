# Lido Protocol Anomaly Sentinel — Mainnet

> A production-grade Drosera Trap monitoring Lido protocol internal health metrics on **Ethereum Mainnet**, with automated on-chain response when anomalous accounting behavior is detected across consecutive block samples.

---

## Overview

This repository contains two contracts that work together as a complete Drosera Trap system on Ethereum Mainnet:

| Contract | Role | Address |
|---|---|---|
| `LidoProtocolAnomalySentinel` | Drosera Trap — collects & analyses Lido state | [`0x8E847b7E28C4C33aAEB4F65b248cB23a804f947E`](https://etherscan.io/address/0x8E847b7E28C4C33aAEB4F65b248cB23a804f947E) |
| `LidoSentinelResponse` | Response contract — records anomalies on-chain | [`0x39135dE7E43f06284Ca865DA02f53C04C8F178d5`](https://etherscan.io/address/0x39135dE7E43f06284Ca865DA02f53C04C8F178d5) |

**Operator:** [`0x689Ad0f9cBa2dA64039cF894E9fB3Aa6266861D8`](https://etherscan.io/address/0x689Ad0f9cBa2dA64039cF894E9fB3Aa6266861D8)

**Use Case Reference:** [Liquid Restaking — Mitigating Depegs](https://dev.drosera.io/use-cases)

> For testnet (Hoodi) version, see: [drosera-traps](https://github.com/DAOmindbreaker/drosera-traps)

---

## What This Trap Monitors

This Trap monitors **Lido protocol-level accounting state** — not market prices. It detects on-chain anomalies that indicate potential protocol health issues before they manifest in market prices.

> For market depeg detection, a DEX/oracle-based Trap would be required. This Trap is intentionally scoped to protocol-level accounting health.

### Contracts Monitored (Lido on Ethereum Mainnet)

| Contract | Address |
|---|---|
| stETH | [`0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`](https://etherscan.io/address/0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) |
| wstETH | [`0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`](https://etherscan.io/address/0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) |

---

## Detection Logic

Every block sample, `collect()` captures a `LidoSnapshot` struct containing:

```solidity
struct LidoSnapshot {
    uint256 totalPooledEther;    // Total ETH held by Lido (wei)
    uint256 totalShares;         // Total stETH shares outstanding
    uint256 wstEthRate;          // ETH per 1e18 wstETH shares (scaled 1e18)
    uint256 stEthInternalRate;   // ETH per 1e18 stETH shares via stETH contract
    uint256 rateConsistencyBps;  // |wstEthRate - stEthInternalRate| in basis points
    bool    valid;               // False if any external call reverted
}
```

`shouldRespond()` analyses 3 consecutive snapshots for sustained anomalies:

### Check A — Pooled ETH Collapse (CRITICAL, id=1)
Immediate trigger if `totalPooledEther` drops more than **5% (500 bps)** versus the oldest sample. No mid-sample confirmation needed — a 5%+ drop is already extreme.

### Check B — wstETH Redemption Rate Drop (HIGH, id=2)
Triggers if wstETH rate drops more than **3% (300 bps)** from oldest to current **AND** the mid-sample also shows a drop. Requiring two consecutive declining samples filters noise.

### Check C — Rate Consistency Breach (HIGH, id=3)
Triggers if stETH and wstETH disagree on redemption rate by more than **50 bps (0.5%)** in **both** current and mid samples. Sustained divergence signals accounting manipulation or oracle failure.

---

## Early Warning System (shouldAlert)

`shouldAlert()` fires before `shouldRespond()` thresholds are reached:

### Alert A — Pooled ETH Soft Drop (id=10)
Triggers when pooled ETH drops more than **2% (200 bps)** — early signal before Check A's 5% hard trigger.

### Alert B — wstETH Rate Soft Drop (id=11)
Triggers when wstETH rate drops more than **1% (100 bps)** — early signal before Check B's 3% hard trigger.

---

## Response Contract

`LidoSentinelResponse` receives structured anomaly reports from the Trap via a single entrypoint and emits fully typed events for off-chain indexers, alert systems, or governance modules.

### Single Entrypoint

```solidity
function handleAnomaly(uint8 anomalyId, uint256 a, uint256 b, uint256 c) external
```

### Events

| Anomaly ID | Event | Severity |
|---|---|---|
| 1 | `PooledEthCollapse` | CRITICAL |
| 2 | `WstEthRateDrop` | HIGH |
| 3 | `RateConsistencyBreach` | HIGH |
| 10 | `PooledEthSoftDrop` | ALERT |
| 11 | `WstEthRateSoftDrop` | ALERT |
| other | `UnknownAnomalySignal` | — |

### State Tracking

```solidity
uint256 public totalAnomalies;    // Total anomaly events recorded
uint256 public lastAnomalyBlock;  // Last block an anomaly was recorded
uint8   public lastAnomalyId;     // Last anomaly ID that triggered
```

---

## Trap Configuration

```toml
[traps.lido_anomaly_sentinel]
path                    = "out/LidoProtocolAnomalySentinel.sol/LidoProtocolAnomalySentinel.json"
response_contract       = "0x39135dE7E43f06284Ca865DA02f53C04C8F178d5"
response_function       = "handleAnomaly(uint8,uint256,uint256,uint256)"
cooldown_period_blocks  = 33
min_number_of_operators = 1
max_number_of_operators = 3
block_sample_size       = 3
private_trap            = true
whitelist               = ["0x689Ad0f9cBa2dA64039cF894E9fB3Aa6266861D8"]
address                 = "0x8E847b7E28C4C33aAEB4F65b248cB23a804f947E"
```

---

## Dryrun Stats

```
trap_name         : lido_anomaly_sentinel
trap_hash         : 0x4912128e914d1315a561a9440ce93d1d0b6df8a19b0ae6cfbdf941b78c1d5660
collect() gas     : 61,946
shouldRespond()   : 31,670
shouldAlert()     : active
accounts queried  : 6
slots queried     : 7
```

---

## v2 Improvements (vs Testnet)

- **Single entrypoint** — `handleAnomaly(uint8,uint256,uint256,uint256)` replaces multiple response functions, simplifying TOML wiring
- **Authorization model fixed** — no `msg.sender` check; Drosera protocol submits on-chain callbacks
- **`shouldAlert()` added** — 2 early warning signals fire before hard triggers
- **Check C rewritten** — monitors stETH/wstETH rate consistency instead of `shareRatioBps`
- **Mainnet addresses** — stETH and wstETH point to Ethereum Mainnet contracts

---

## Repository Structure

```
src/
├── LidoProtocolAnomalySentinel.sol   Drosera Trap — ITrap implementation
└── LidoSentinelResponse.sol          Response contract — on-chain anomaly recorder
script/
└── Deploy.s.sol                      Forge deployment script (Response contract)
```

---

## Deployment

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Drosera CLI](https://app.drosera.io/install)
- Active [Drosera Subscription](https://app.drosera.io/early-supporters-initiative)

### Deploy Response Contract

```bash
forge build
forge script script/Deploy.s.sol --rpc-url <ETH_MAINNET_RPC> --private-key <PRIVATE_KEY> --broadcast
```

### Deploy Trap

```bash
DROSERA_PRIVATE_KEY=<PRIVATE_KEY> drosera apply
```

### Run Operator

```bash
drosera-operator register --eth-rpc-url <ETH_MAINNET_RPC> --eth-private-key <PRIVATE_KEY>
drosera-operator optin --eth-rpc-url <ETH_MAINNET_RPC> --eth-private-key <PRIVATE_KEY> --trap-config-address 0x8E847b7E28C4C33aAEB4F65b248cB23a804f947E
```

---

## Network

| Parameter | Value |
|---|---|
| Network | Ethereum Mainnet |
| Chain ID | 1 |
| Drosera Proxy | `0x01C344b8406c3237a6b9dbd06ef2832142866d87` |
| Seed Node Relay | `https://relay.ethereum.drosera.io/` |

---

## Author

**DAOmindbreaker** — Built for the Drosera Network on Ethereum Mainnet.

X: [@admirjae](https://x.com/admirjae)

---

## License

MIT
