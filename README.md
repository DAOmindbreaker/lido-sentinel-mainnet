# Lido Protocol Anomaly Sentinel

> A production-ready Drosera Trap that monitors Lido protocol internal health metrics on Ethereum Mainnet and triggers automated on-chain responses when anomalous accounting behavior is detected across consecutive block samples.

---

## Overview

This repository contains the contracts that work together as a complete Drosera Trap system:

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

## What This Trap Monitors

This Trap monitors **Lido protocol-level accounting state** — not market prices. It detects on-chain anomalies that indicate potential protocol health issues before they manifest in market prices.

> For market depeg detection, a DEX/oracle-based Trap would be required. This Trap is intentionally scoped to protocol-level accounting health.

### Contracts Monitored (Ethereum Mainnet)

| Contract | Address |
|---|---|
| stETH | [`0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`](https://etherscan.io/address/0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) |
| wstETH | [`0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`](https://etherscan.io/address/0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) |
| WithdrawalQueue (V3) | [`0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1`](https://etherscan.io/address/0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1) |

---

## Detection Logic

### V3 — Hard Triggers (`shouldRespond`)

Analyzes 3 consecutive block snapshots. All checks require **sustained** anomalies across multiple samples to eliminate false positives.

| Check | Signal | Threshold | Confirmation |
|-------|--------|-----------|--------------|
| A | Pooled ETH collapse | > 5% drop | current + mid both drop |
| B | wstETH redemption rate drop | > 3% drop | current + mid both drop |
| C | stETH/wstETH rate inconsistency | > 30 bps delta | current + mid both breach |
| D 🆕 | Withdrawal queue stress | unfinalizedStETH > 15% of pooled | current + mid both breach |

### V3 — Early Warnings (`shouldAlert`)

| Alert | Signal | Threshold |
|-------|--------|-----------|
| A | Pooled ETH soft drop | > 2% |
| B | wstETH rate soft drop | > 1% |
| C 🆕 | Withdrawal queue build-up | > 8% of pooled |

---

## V3 vs V2 Improvements

| Feature | V2 | V3 |
|---------|----|----|
| Check A confirmation | immediate trigger | sustained (mid required) |
| Check C threshold | 50 bps | 30 bps (tightened) |
| Withdrawal queue monitoring | ❌ | ✅ Check D + Alert C |
| False positive resistance | basic | improved |

---

## Response Payload Encoding

All checks encode to a single entrypoint:

```solidity
function handleAnomaly(uint8 anomalyId, uint256 a, uint256 b, uint256 c) external
```

| ID | Check | a | b | c |
|----|-------|---|---|---|
| 1 | Pooled ETH Collapse | currentPooled | oldestPooled | dropBps |
| 2 | wstETH Rate Drop | currentRate | oldestRate | dropBps |
| 3 | Rate Consistency Breach | consistencyBps | wstEthRate | stEthInternalRate |
| 4 | Withdrawal Queue Stress | unfinalizedStETH | totalPooled | queueBps |
| 10 | Alert: Pooled ETH Soft Drop | currentPooled | midPooled | dropBps |
| 11 | Alert: wstETH Rate Soft Drop | currentRate | midRate | dropBps |
| 12 | Alert: Queue Build-up | unfinalizedStETH | totalPooled | queueBps |

---

## Snapshot Data Collected

```solidity
struct LidoSnapshot {
    uint256 totalPooledEther;       // Total ETH in Lido protocol
    uint256 totalShares;            // Total stETH shares outstanding
    uint256 wstEthRate;             // ETH per 1e18 wstETH shares
    uint256 stEthInternalRate;      // ETH per 1e18 stETH shares (cross-check)
    uint256 rateConsistencyBps;     // Delta between wstETH and stETH rates
    uint256 bufferedEther;          // ETH buffered awaiting deposit
    uint256 unfinalizedStETH;       // stETH pending withdrawal finalization
    uint256 pendingRequests;        // Pending withdrawal request count
    bool valid;
}
```

---

## Stack

- [Drosera Network](https://drosera.io) — decentralized trap execution & attestation
- Foundry — compilation & testing
- Solidity ^0.8.20

---

## Author

**admirjae** — Drosera Mainnet Operator

- 𝕏 [@admirjae](https://x.com/admirjae)
- Operator: `0x689Ad0f9cBa2dA64039cF894E9fB3Aa6266861D8`
- GitHub: [@DAOmindbreaker](https://github.com/DAOmindbreaker)
