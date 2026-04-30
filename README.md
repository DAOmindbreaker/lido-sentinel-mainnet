# Lido Protocol Anomaly Sentinel

> A production-grade Drosera Trap monitoring **Lido protocol internal accounting health** on Ethereum Mainnet. Triggers automated on-chain responses when anomalous behavior is detected and sustained across consecutive block samples.

[![Mainnet](https://img.shields.io/badge/Network-Ethereum%20Mainnet-blue)](https://ethereum.org)
[![Drosera](https://img.shields.io/badge/Powered%20by-Drosera%20Network-orange)](https://drosera.io)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## Why Internal Accounting — Not Market Price

Most DeFi security tooling reacts to price. This trap detects the cause before the symptom.

When a protocol's internal accounting drifts — pooled ETH collapses, redemption rates diverge, withdrawal queues spike — market prices follow. By the time a depeg is visible on a DEX, damage is already done.

This trap fires on the **on-chain truth**: what the contracts themselves report about their own state. No oracle. No market feed. Pure protocol-level signal.

> The earnETH/rsETH event in April 2026 is a direct example of the scenario this trap is designed to catch: withdrawal queue stress building up as unfinalizedStETH grows relative to pooled ETH — precisely what Check D monitors.

---

## Overview

| Contract | Role | Version |
|---|---|---|
| `LidoProtocolAnomalySentinel` | Drosera Trap — collects & analyses Lido state | V2 |
| `LidoSentinelV3` | Drosera Trap — enhanced with withdrawal queue monitoring | V3 |
| `LidoSentinelResponse` | Response contract — records anomalies on-chain | V2 |
| `LidoSentinelV3Response` | Response contract — records anomalies on-chain | V3 |

**Use Case Reference:** [Liquid Restaking — Mitigating Depegs](https://dev.drosera.io/use-cases)

---

## Deployed on Ethereum Mainnet

| Version | Trap Address | Response Contract | Status |
|---------|-------------|-------------------|--------|
| V2 | [`0x8E847b7E28C4C33aAEB4F65b248cB23a804f947E`](https://etherscan.io/address/0x8E847b7E28C4C33aAEB4F65b248cB23a804f947E) | [`0x39135dE7E43f06284Ca865DA02f53C04C8F178d5`](https://etherscan.io/address/0x39135dE7E43f06284Ca865DA02f53C04C8F178d5) | ✅ Active |
| V3 | [`0x9D1BDf9Af513AFDeCC8fF8107ceDdFf4748Abd92`](https://etherscan.io/address/0x9D1BDf9Af513AFDeCC8fF8107ceDdFf4748Abd92) | [`0x9E9bf4FaAD8661421c423a30b49d7B8c49041c47`](https://etherscan.io/address/0x9E9bf4FaAD8661421c423a30b49d7B8c49041c47) | ✅ Active |

---

## Contracts Monitored

| Contract | Address | Role |
|---|---|---|
| stETH | [`0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`](https://etherscan.io/address/0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) | Liquid staking token, pooled ETH accounting |
| wstETH | [`0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`](https://etherscan.io/address/0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) | Wrapped stETH, redemption rate |
| WithdrawalQueue | [`0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1`](https://etherscan.io/address/0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1) | Pending withdrawals (V3 only) |

---

## Detection Logic

### Design Philosophy

Every check requires **sustained** anomalies across multiple consecutive block samples before triggering. A single-block spike — from a rebase, large deposit, or MEV activity — will not fire the trap. The signal must persist.

This design eliminates the primary source of false positives in threshold-based monitoring: transient state.

### V3 — Hard Triggers (`shouldRespond`)

3 consecutive snapshots analyzed. Both `current` and `mid` must breach threshold.

| Check | Signal | Threshold | Confirmation |
|-------|--------|-----------|--------------|
| A | Pooled ETH collapse | > 5% drop from oldest | current + mid both drop |
| B | wstETH redemption rate drop | > 3% from oldest | current + mid both drop |
| C | stETH/wstETH rate inconsistency | > 30 bps delta | current + mid both breach |
| D | Withdrawal queue stress | unfinalizedStETH > 15% of pooled | current + mid both breach |

### V3 — Early Warnings (`shouldAlert`)

2 snapshots. Fires before hard thresholds breach — giving protocols time to react.

| Alert | Signal | Threshold |
|-------|--------|-----------|
| A | Pooled ETH soft drop | > 2% |
| B | wstETH rate soft drop | > 1% |
| C | Withdrawal queue build-up | > 8% of pooled |

### Why These Thresholds

- **Check A (5%):** Lido's pooled ETH grows monotonically under normal operation. Any drop signals accounting failure, not market movement.
- **Check B (3%):** wstETH rate should only increase over time as staking rewards accrue. Sustained decline = redemption mechanism failure.
- **Check C (30 bps):** stETH and wstETH contracts independently derive the same ETH-per-share value. Any divergence signals an oracle or accounting split.
- **Check D (15%):** When unfinalizedStETH exceeds 15% of total pooled ETH, the protocol faces structural liquidity pressure — users are exiting faster than the queue can process.

---

## V3 vs V2

| Feature | V2 | V3 |
|---------|----|----|
| Check A confirmation | immediate (single block) | sustained (mid + current) |
| Check C threshold | 50 bps | 30 bps (tightened) |
| Withdrawal queue monitoring | ❌ | ✅ Check D + Alert C |
| Contracts monitored | 2 | 3 |
| False positive resistance | threshold-based | sustained multi-sample |

---

## Snapshot Data

Each block sample collects a complete protocol state snapshot:

```solidity
struct LidoSnapshot {
    uint256 totalPooledEther;       // Total ETH controlled by Lido protocol
    uint256 totalShares;            // Total stETH shares outstanding
    uint256 wstEthRate;             // ETH redeemable per 1e18 wstETH (via wstETH contract)
    uint256 stEthInternalRate;      // ETH per 1e18 shares (via stETH contract — for cross-check)
    uint256 rateConsistencyBps;     // |wstEthRate - stEthInternalRate| / stEthInternalRate * BPS
    uint256 bufferedEther;          // ETH buffered awaiting beacon chain deposit
    uint256 unfinalizedStETH;       // stETH value pending withdrawal finalization
    uint256 pendingRequests;        // lastRequestId - lastFinalizedRequestId
    bool valid;                     // false if any external call reverted
}
```

All external calls are wrapped in `try/catch`. Any call failure marks the snapshot invalid and skips the analysis — the trap will not fire on incomplete data.

---

## Response Payload

Single entrypoint for all anomaly types:

```solidity
function handleAnomaly(uint8 anomalyId, uint256 a, uint256 b, uint256 c) external
```

| ID | Anomaly | a | b | c |
|----|---------|---|---|---|
| 1 | Pooled ETH Collapse | currentPooled | oldestPooled | dropBps |
| 2 | wstETH Rate Drop | currentRate | oldestRate | dropBps |
| 3 | Rate Consistency Breach | consistencyBps | wstEthRate | stEthInternalRate |
| 4 | Withdrawal Queue Stress | unfinalizedStETH | totalPooled | queueBps |
| 10 | Alert: Pooled ETH Soft Drop | currentPooled | midPooled | dropBps |
| 11 | Alert: wstETH Rate Soft Drop | currentRate | midRate | dropBps |
| 12 | Alert: Queue Build-up | unfinalizedStETH | totalPooled | queueBps |

---

## Part of a Multi-Trap Mainnet Deployment

This repository is part of a broader Drosera security coverage for the Lido ecosystem:

| Repo | Coverage |
|------|----------|
| **lido-sentinel-mainnet** (this repo) | Lido core protocol accounting health |
| [aegis-v3-sentinel-mainnet](https://github.com/DAOmindbreaker/aegis-v3-sentinel-mainnet) | Lido V3 stVaults ecosystem + Governance + Aegis V4 IDT |

---

## Stack

- [Drosera Network](https://drosera.io) — decentralized trap execution & attestation
- Foundry — compilation & testing
- Solidity ^0.8.20

---

## Author

**admirjae** — Drosera Mainnet Operator

- 𝕏 [@admirjae](https://x.com/admirjae)
- Operator: [`0x689Ad0f9cBa2dA64039cF894E9fB3Aa6266861D8`](https://etherscan.io/address/0x689Ad0f9cBa2dA64039cF894E9fB3Aa6266861D8)
- GitHub: [@DAOmindbreaker](https://github.com/DAOmindbreaker)
