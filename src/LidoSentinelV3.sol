// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

/**
 * @title  Lido Protocol Anomaly Sentinel — v3
 * @author DAOmindbreaker
 * @notice Drosera Trap monitoring Lido protocol internal health metrics.
 *         Triggers on sustained anomalous accounting behavior across
 *         consecutive block samples.
 *
 * @dev    V3 improvements over V2:
 *         - Check A now requires mid-snapshot confirmation (sustained collapse)
 *         - Check C threshold tightened: 50 bps → 30 bps
 *         - Check D (id=4): Withdrawal queue stress detection
 *           Monitors unbufferedEther vs buffered ratio — signals illiquidity
 *         - Alert C (id=12): Early warning for withdrawal queue build-up
 *         - Snapshot struct extended with withdrawal queue data
 *
 * @dev    All checks encode to:
 *           abi.encode(uint8 checkId, uint256 a, uint256 b, uint256 c)
 *         Matching TOML: response_function = "handleAnomaly(uint8,uint256,uint256,uint256)"
 *
 * Contracts monitored (Ethereum Mainnet):
 *   stETH            : 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
 *   wstETH           : 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
 *   WithdrawalQueue  : 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1
 */

interface IStETH {
    function getTotalPooledEther() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    function getBufferedEther() external view returns (uint256);
}

interface IWstETH {
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
}

interface IWithdrawalQueue {
    function unfinalizedStETH() external view returns (uint256);
    function getLastFinalizedRequestId() external view returns (uint256);
    function getLastRequestId() external view returns (uint256);
}

struct LidoSnapshot {
    uint256 totalPooledEther;
    uint256 totalShares;
    uint256 wstEthRate;
    uint256 stEthInternalRate;
    uint256 rateConsistencyBps;
    uint256 bufferedEther;
    uint256 unfinalizedStETH;
    uint256 pendingRequests;       // lastRequestId - lastFinalizedRequestId
    bool valid;
}

contract LidoSentinelV3 is ITrap {

    // ── Addresses ────────────────────────────
    address public constant STETH           = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant WSTETH          = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    // ── Constants ────────────────────────────
    uint256 public constant MIN_POOLED_ETH          = 1 ether;
    uint256 public constant BPS_DENOM               = 10_000;

    /// Check A: pooled ETH collapse > 5% sustained (both current & mid drop)
    uint256 public constant POOLED_DROP_BPS         = 500;
    /// Alert A: early warning > 2%
    uint256 public constant POOLED_DROP_ALERT_BPS   = 200;

    /// Check B: wstETH rate drop > 3% sustained
    uint256 public constant RATE_DROP_BPS           = 300;
    /// Alert B: early warning > 1%
    uint256 public constant RATE_DROP_ALERT_BPS     = 100;

    /// Check C: stETH/wstETH rate inconsistency > 30 bps sustained (tightened from 50)
    uint256 public constant RATE_CONSISTENCY_BPS    = 30;

    /// Check D: unfinalized stETH > 15% of totalPooledEther sustained
    uint256 public constant QUEUE_STRESS_BPS        = 1_500;
    /// Alert C: early warning > 8%
    uint256 public constant QUEUE_STRESS_ALERT_BPS  = 800;

    // ── collect() ────────────────────────────

    function collect() external view returns (bytes memory) {
        LidoSnapshot memory snap;

        try IStETH(STETH).getTotalPooledEther() returns (uint256 v) {
            snap.totalPooledEther = v;
        } catch { snap.valid = false; return abi.encode(snap); }

        try IStETH(STETH).getTotalShares() returns (uint256 v) {
            snap.totalShares = v;
        } catch { snap.valid = false; return abi.encode(snap); }

        try IWstETH(WSTETH).getPooledEthByShares(1e18) returns (uint256 v) {
            snap.wstEthRate = v;
        } catch { snap.valid = false; return abi.encode(snap); }

        try IStETH(STETH).getPooledEthByShares(1e18) returns (uint256 v) {
            snap.stEthInternalRate = v;
        } catch { snap.valid = false; return abi.encode(snap); }

        try IStETH(STETH).getBufferedEther() returns (uint256 v) {
            snap.bufferedEther = v;
        } catch { snap.valid = false; return abi.encode(snap); }

        try IWithdrawalQueue(WITHDRAWAL_QUEUE).unfinalizedStETH() returns (uint256 v) {
            snap.unfinalizedStETH = v;
        } catch { snap.valid = false; return abi.encode(snap); }

        try IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastRequestId() returns (uint256 last) {
            try IWithdrawalQueue(WITHDRAWAL_QUEUE).getLastFinalizedRequestId() returns (uint256 fin) {
                snap.pendingRequests = last > fin ? last - fin : 0;
            } catch { snap.valid = false; return abi.encode(snap); }
        } catch { snap.valid = false; return abi.encode(snap); }

        // Rate consistency delta
        if (snap.stEthInternalRate > 0) {
            uint256 delta = snap.wstEthRate > snap.stEthInternalRate
                ? snap.wstEthRate - snap.stEthInternalRate
                : snap.stEthInternalRate - snap.wstEthRate;
            snap.rateConsistencyBps = (delta * BPS_DENOM) / snap.stEthInternalRate;
        }

        snap.valid = true;
        return abi.encode(snap);
    }

    // ── shouldRespond() ──────────────────────

    function shouldRespond(
        bytes[] calldata data
    ) external pure returns (bool, bytes memory) {

        if (data.length < 3) return (false, bytes(""));

        LidoSnapshot memory current = abi.decode(data[0], (LidoSnapshot));
        LidoSnapshot memory mid     = abi.decode(data[1], (LidoSnapshot));
        LidoSnapshot memory oldest  = abi.decode(data[2], (LidoSnapshot));

        if (!current.valid || !mid.valid || !oldest.valid) return (false, bytes(""));

        if (current.totalPooledEther < MIN_POOLED_ETH ||
            oldest.totalPooledEther  < MIN_POOLED_ETH) return (false, bytes(""));

        // ── Check A: Pooled ETH collapse (sustained — both current & mid drop) ──
        if (current.totalPooledEther < oldest.totalPooledEther &&
            mid.totalPooledEther     < oldest.totalPooledEther) {
            uint256 dropBps =
                ((oldest.totalPooledEther - current.totalPooledEther) * BPS_DENOM)
                    / oldest.totalPooledEther;
            if (dropBps >= POOLED_DROP_BPS) {
                return (true, abi.encode(uint8(1), current.totalPooledEther, oldest.totalPooledEther, dropBps));
            }
        }

        // ── Check B: wstETH rate drop (sustained) ────────────────────────────────
        if (oldest.wstEthRate > 0 && current.wstEthRate < oldest.wstEthRate) {
            uint256 rateDropBps =
                ((oldest.wstEthRate - current.wstEthRate) * BPS_DENOM)
                    / oldest.wstEthRate;
            bool midAlsoDropped = mid.wstEthRate < oldest.wstEthRate;
            if (rateDropBps >= RATE_DROP_BPS && midAlsoDropped) {
                return (true, abi.encode(uint8(2), current.wstEthRate, oldest.wstEthRate, rateDropBps));
            }
        }

        // ── Check C: Rate consistency breach (tightened 30 bps, sustained) ───────
        if (current.rateConsistencyBps >= RATE_CONSISTENCY_BPS &&
            mid.rateConsistencyBps     >= RATE_CONSISTENCY_BPS) {
            return (true, abi.encode(uint8(3), current.rateConsistencyBps, current.wstEthRate, current.stEthInternalRate));
        }

        // ── Check D: Withdrawal queue stress (unfinalized > 15% of pooled, sustained) ─
        if (current.totalPooledEther > 0 && oldest.totalPooledEther > 0) {
            uint256 currentQueueBps =
                (current.unfinalizedStETH * BPS_DENOM) / current.totalPooledEther;
            uint256 midQueueBps =
                mid.totalPooledEther > 0
                    ? (mid.unfinalizedStETH * BPS_DENOM) / mid.totalPooledEther
                    : 0;
            if (currentQueueBps >= QUEUE_STRESS_BPS && midQueueBps >= QUEUE_STRESS_BPS) {
                return (true, abi.encode(uint8(4), current.unfinalizedStETH, current.totalPooledEther, currentQueueBps));
            }
        }

        return (false, bytes(""));
    }

    // ── shouldAlert() ─────────────────────────

    function shouldAlert(
        bytes[] calldata data
    ) external pure returns (bool, bytes memory) {

        if (data.length < 2) return (false, bytes(""));

        LidoSnapshot memory current = abi.decode(data[0], (LidoSnapshot));
        LidoSnapshot memory mid     = abi.decode(data[1], (LidoSnapshot));

        if (!current.valid || !mid.valid) return (false, bytes(""));

        // ── Alert A: Pooled ETH soft drop > 2% ───────────────────────────────────
        if (current.totalPooledEther < mid.totalPooledEther && mid.totalPooledEther > 0) {
            uint256 dropBps =
                ((mid.totalPooledEther - current.totalPooledEther) * BPS_DENOM)
                    / mid.totalPooledEther;
            if (dropBps >= POOLED_DROP_ALERT_BPS) {
                return (true, abi.encode(uint8(10), current.totalPooledEther, mid.totalPooledEther, dropBps));
            }
        }

        // ── Alert B: wstETH rate soft drop > 1% ──────────────────────────────────
        if (mid.wstEthRate > 0 && current.wstEthRate < mid.wstEthRate) {
            uint256 alertDropBps =
                ((mid.wstEthRate - current.wstEthRate) * BPS_DENOM)
                    / mid.wstEthRate;
            if (alertDropBps >= RATE_DROP_ALERT_BPS) {
                return (true, abi.encode(uint8(11), current.wstEthRate, mid.wstEthRate, alertDropBps));
            }
        }

        // ── Alert C: Withdrawal queue build-up > 8% ──────────────────────────────
        if (current.totalPooledEther > 0) {
            uint256 queueBps =
                (current.unfinalizedStETH * BPS_DENOM) / current.totalPooledEther;
            if (queueBps >= QUEUE_STRESS_ALERT_BPS) {
                return (true, abi.encode(uint8(12), current.unfinalizedStETH, current.totalPooledEther, queueBps));
            }
        }

        return (false, bytes(""));
    }
}
