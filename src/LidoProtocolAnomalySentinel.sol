// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

/**
 * @title  Lido Protocol Anomaly Sentinel — v2
 * @author DAOmindbreaker
 * @notice Drosera Trap that monitors Lido protocol internal health metrics
 *         and triggers when anomalous accounting behavior is detected across
 *         multiple consecutive block samples.
 *
 * @dev    This Trap monitors Lido-internal accounting state — NOT market prices.
 *         It detects on-chain anomalies such as:
 *           Check A (id=1) — Pooled ETH collapse (CRITICAL)
 *           Check B (id=2) — wstETH redemption rate drop (HIGH)
 *           Check C (id=3) — stETH/wstETH rate consistency breach (HIGH)
 *
 * @dev    v2 improvements:
 *         - Single handleAnomaly(uint8,uint256,uint256,uint256) entrypoint
 *           so TOML wiring matches all check payloads correctly
 *         - Authorization model fixed — no msg.sender check, Drosera protocol submits
 *         - shouldAlert() added — 2 early warning signals before hard triggers
 *         - Check C rewritten — monitors stETH/wstETH rate consistency instead
 *           of shareRatioBps which is not a reliable anomaly signal
 *         - Mainnet-ready — just swap addresses in constants
 *
 * @dev    All checks encode to:
 *           abi.encode(uint8 checkId, uint256 a, uint256 b, uint256 c)
 *         Matching TOML: response_function = "handleAnomaly(uint8,uint256,uint256,uint256)"
 *
 * Use Case: Liquid Restaking — Mitigating Depegs (dev.drosera.io/use-cases)
 *
 * Contracts monitored:
 *   Testnet (Hoodi):
 *     stETH  : 0x3508A952176b3c15387C97BE809eaffB1982176a
 *     wstETH : 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4
 *
 *   Mainnet (Ethereum):
 *     stETH  : 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
 *     wstETH : 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
 */

// ─────────────────────────────────────────────
//  External interfaces
// ─────────────────────────────────────────────

interface IStETH {
    /// @notice Total ETH held by Lido protocol (rebases upward over time)
    function getTotalPooledEther() external view returns (uint256);
    /// @notice Total stETH shares in existence
    function getTotalShares() external view returns (uint256);
    /// @notice ETH value of a given amount of shares
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
}

interface IWstETH {
    /// @notice ETH redeemable per 1e18 wstETH shares (redemption rate)
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    /// @notice wstETH per stETH (how many wstETH you get for 1e18 stETH)
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
}

// ─────────────────────────────────────────────
//  Data structures
// ─────────────────────────────────────────────

/// @notice Snapshot of Lido protocol state at a given block sample
struct LidoSnapshot {
    /// @notice Total ETH pooled in Lido (wei)
    uint256 totalPooledEther;
    /// @notice Total stETH shares outstanding
    uint256 totalShares;
    /// @notice wstETH redemption rate: ETH per 1e18 wstETH shares (scaled 1e18)
    uint256 wstEthRate;
    /// @notice stETH internal rate: ETH per 1e18 stETH shares via stETH contract (scaled 1e18)
    /// @dev    Used for Check C — cross-check stETH vs wstETH rate consistency
    uint256 stEthInternalRate;
    /// @notice Rate consistency delta in basis points (|wstEthRate - stEthInternalRate| / stEthInternalRate * BPS)
    uint256 rateConsistencyBps;
    /// @notice True if all external calls succeeded
    bool valid;
}

// ─────────────────────────────────────────────
//  Trap contract
// ─────────────────────────────────────────────

contract LidoProtocolAnomalySentinel is ITrap {

    // ── Constants ────────────────────────────

    /// @notice Lido stETH proxy
    /// @dev    Mainnet: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
    ///         Hoodi:   0x3508A952176b3c15387C97BE809eaffB1982176a
    address public constant STETH  = 0x3508A952176b3c15387C97BE809eaffB1982176a;

    /// @notice Lido wstETH
    /// @dev    Mainnet: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
    ///         Hoodi:   0x7E99eE3C66636DE415D2d7C880938F2f40f94De4
    address public constant WSTETH = 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4;

    /// @notice Minimum pooled ETH before monitoring is meaningful
    uint256 public constant MIN_POOLED_ETH = 1 ether;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOM = 10_000;

    /// @notice Check A: trigger if totalPooledEther drops > 5% (500 bps)
    uint256 public constant POOLED_DROP_BPS = 500;

    /// @notice Check A alert: trigger alert if drop > 2% (200 bps)
    uint256 public constant POOLED_DROP_ALERT_BPS = 200;

    /// @notice Check B: trigger if wstETH rate drops > 3% (300 bps) sustained
    uint256 public constant RATE_DROP_BPS = 300;

    /// @notice Check B alert: trigger alert if wstETH rate drops > 1% (100 bps)
    uint256 public constant RATE_DROP_ALERT_BPS = 100;

    /// @notice Check C: trigger if stETH/wstETH rate inconsistency > 50 bps
    /// @dev    stETH and wstETH should always agree on redemption rate.
    ///         Any deviation > 0.5% signals accounting manipulation or oracle failure.
    uint256 public constant RATE_CONSISTENCY_BPS = 50;

    // ── collect() ────────────────────────────

    /**
     * @notice Collects a LidoSnapshot from stETH and wstETH contracts.
     * @dev    Every external call wrapped in try/catch. Any critical failure
     *         marks the snapshot invalid and shouldRespond() safely skips it.
     *
     *         Check C data: stETH.getPooledEthByShares(1e18) gives the ETH
     *         value of 1e18 stETH shares via stETH's own accounting.
     *         wstETH.getPooledEthByShares(1e18) gives the same via wstETH.
     *         Both should return identical values — any delta signals inconsistency.
     *
     * @return ABI-encoded LidoSnapshot struct
     */
    function collect() external view returns (bytes memory) {
        LidoSnapshot memory snap;

        // ── Total pooled ETH ─────────────────
        try IStETH(STETH).getTotalPooledEther() returns (uint256 pooled) {
            snap.totalPooledEther = pooled;
        } catch {
            snap.valid = false;
            return abi.encode(snap);
        }

        // ── Total shares ─────────────────────
        try IStETH(STETH).getTotalShares() returns (uint256 shares) {
            snap.totalShares = shares;
        } catch {
            snap.valid = false;
            return abi.encode(snap);
        }

        // ── wstETH redemption rate ───────────
        try IWstETH(WSTETH).getPooledEthByShares(1e18) returns (uint256 rate) {
            snap.wstEthRate = rate;
        } catch {
            snap.valid = false;
            return abi.encode(snap);
        }

        // ── stETH internal rate (for Check C) ─
        // stETH.getPooledEthByShares(1e18) returns ETH per 1e18 shares
        // Must match wstETH rate — deviation = accounting inconsistency
        try IStETH(STETH).getPooledEthByShares(1e18) returns (uint256 internalRate) {
            snap.stEthInternalRate = internalRate;
        } catch {
            snap.valid = false;
            return abi.encode(snap);
        }

        // ── Derive rate consistency delta ────
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

    /**
     * @notice Analyses 3 consecutive LidoSnapshots for sustained anomalies.
     * @dev    All checks encode to handleAnomaly(uint8,uint256,uint256,uint256).
     *
     *         Check A (id=1) — Pooled ETH Collapse (CRITICAL)
     *           Immediate trigger if totalPooledEther drops > POOLED_DROP_BPS
     *           vs oldest. No mid confirmation — 5%+ drop is already extreme.
     *           Payload: (1, currentPooled, oldestPooled, dropBps)
     *
     *         Check B (id=2) — wstETH Rate Drop (HIGH)
     *           Rate drops > RATE_DROP_BPS from oldest to current AND
     *           mid also shows a drop (sustained, not a spike).
     *           Payload: (2, currentRate, oldestRate, dropBps)
     *
     *         Check C (id=3) — Rate Consistency Breach (HIGH)
     *           stETH and wstETH disagree on redemption rate by > RATE_CONSISTENCY_BPS
     *           in both current and mid snapshots (sustained inconsistency).
     *           Payload: (3, rateConsistencyBps, wstEthRate, stEthInternalRate)
     *
     * @param  data  ABI-encoded LidoSnapshot array (index 0 = newest)
     * @return (true, encodedPayload) if anomaly detected; (false, "") otherwise
     */
    function shouldRespond(
        bytes[] calldata data
    ) external pure returns (bool, bytes memory) {

        if (data.length < 3) return (false, bytes(""));

        LidoSnapshot memory current = abi.decode(data[0], (LidoSnapshot));
        LidoSnapshot memory mid     = abi.decode(data[1], (LidoSnapshot));
        LidoSnapshot memory oldest  = abi.decode(data[2], (LidoSnapshot));

        if (!current.valid || !mid.valid || !oldest.valid) {
            return (false, bytes(""));
        }

        if (current.totalPooledEther < MIN_POOLED_ETH ||
            oldest.totalPooledEther  < MIN_POOLED_ETH) {
            return (false, bytes(""));
        }

        // ── Check A: Pooled ETH collapse ─────
        if (current.totalPooledEther < oldest.totalPooledEther) {
            uint256 dropBps =
                ((oldest.totalPooledEther - current.totalPooledEther) * BPS_DENOM)
                    / oldest.totalPooledEther;

            if (dropBps >= POOLED_DROP_BPS) {
                return (true, abi.encode(
                    uint8(1),
                    current.totalPooledEther,
                    oldest.totalPooledEther,
                    dropBps
                ));
            }
        }

        // ── Check B: wstETH rate drop ─────────
        if (oldest.wstEthRate > 0 && current.wstEthRate < oldest.wstEthRate) {
            uint256 rateDropBps =
                ((oldest.wstEthRate - current.wstEthRate) * BPS_DENOM)
                    / oldest.wstEthRate;

            bool midAlsoDropped = mid.wstEthRate < oldest.wstEthRate;

            if (rateDropBps >= RATE_DROP_BPS && midAlsoDropped) {
                return (true, abi.encode(
                    uint8(2),
                    current.wstEthRate,
                    oldest.wstEthRate,
                    rateDropBps
                ));
            }
        }

        // ── Check C: Rate consistency breach ──
        // stETH and wstETH must agree on redemption rate.
        // Sustained divergence signals accounting manipulation or oracle failure.
        bool currentInconsistent = current.rateConsistencyBps >= RATE_CONSISTENCY_BPS;
        bool midInconsistent     = mid.rateConsistencyBps     >= RATE_CONSISTENCY_BPS;

        if (currentInconsistent && midInconsistent) {
            return (true, abi.encode(
                uint8(3),
                current.rateConsistencyBps,
                current.wstEthRate,
                current.stEthInternalRate
            ));
        }

        return (false, bytes(""));
    }

    // ── shouldAlert() ─────────────────────────

    /**
     * @notice Early warning system — fires before shouldRespond() thresholds.
     * @dev    Alert payloads use IDs 10-11.
     *
     *         Alert A (id=10) — Pooled ETH soft drop (> 2%, below 5% trigger)
     *           Early signal before Check A hard trigger.
     *           Payload: (10, currentPooled, midPooled, dropBps)
     *
     *         Alert B (id=11) — wstETH rate soft drop (> 1%, below 3% trigger)
     *           Early signal before Check B hard trigger.
     *           Payload: (11, currentRate, midRate, dropBps)
     *
     * @param  data  ABI-encoded LidoSnapshot array (index 0 = newest)
     * @return (true, encodedPayload) if alert condition; (false, "") otherwise
     */
    function shouldAlert(
        bytes[] calldata data
    ) external pure returns (bool, bytes memory) {

        if (data.length < 2) return (false, bytes(""));

        LidoSnapshot memory current = abi.decode(data[0], (LidoSnapshot));
        LidoSnapshot memory mid     = abi.decode(data[1], (LidoSnapshot));

        if (!current.valid || !mid.valid) return (false, bytes(""));

        // ── Alert A: Pooled ETH soft drop ────
        if (current.totalPooledEther < mid.totalPooledEther &&
            mid.totalPooledEther > 0) {

            uint256 dropBps =
                ((mid.totalPooledEther - current.totalPooledEther) * BPS_DENOM)
                    / mid.totalPooledEther;

            if (dropBps >= POOLED_DROP_ALERT_BPS) {
                return (true, abi.encode(
                    uint8(10),
                    current.totalPooledEther,
                    mid.totalPooledEther,
                    dropBps
                ));
            }
        }

        // ── Alert B: wstETH rate soft drop ───
        if (mid.wstEthRate > 0 && current.wstEthRate < mid.wstEthRate) {
            uint256 alertDropBps =
                ((mid.wstEthRate - current.wstEthRate) * BPS_DENOM)
                    / mid.wstEthRate;

            if (alertDropBps >= RATE_DROP_ALERT_BPS) {
                return (true, abi.encode(
                    uint8(11),
                    current.wstEthRate,
                    mid.wstEthRate,
                    alertDropBps
                ));
            }
        }

        return (false, bytes(""));
    }
}
