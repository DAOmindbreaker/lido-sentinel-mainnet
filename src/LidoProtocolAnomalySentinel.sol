// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

/**
 * @title  Lido Protocol Anomaly Sentinel
 * @author DAOmindbreaker
 * @notice Drosera Trap that monitors Lido protocol internal health metrics
 *         on Hoodi testnet and triggers when anomalous accounting behavior
 *         is detected across multiple consecutive block samples.
 *
 * @dev    This Trap monitors Lido-internal accounting state — NOT market prices.
 *         It detects on-chain anomalies such as:
 *           1. Abnormal drops in total pooled ETH (Check A)
 *           2. Sustained wstETH redemption rate drops (Check B)
 *           3. Share supply anomalies relative to pooled ETH (Check C)
 *
 *         For market depeg detection, a DEX/oracle-based Trap would be needed.
 *         This Trap is intentionally scoped to protocol-level accounting health.
 *
 * Use Case: Liquid Restaking — Mitigating Depegs (dev.drosera.io/use-cases)
 *
 * Contracts monitored (Lido official on Hoodi testnet):
 *   stETH  : 0x3508A952176b3c15387C97BE809eaffB1982176a
 *   wstETH : 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4
 */

// ─────────────────────────────────────────────
//  External interfaces
// ─────────────────────────────────────────────

interface IStETH {
    /// @notice Total ETH held by Lido protocol (rebases upward over time)
    function getTotalPooledEther() external view returns (uint256);
    /// @notice Total stETH shares in existence
    function getTotalShares() external view returns (uint256);
}

interface IWstETH {
    /// @notice ETH redeemable per 1e18 wstETH shares (redemption rate)
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
}

// ─────────────────────────────────────────────
//  Data structures
// ─────────────────────────────────────────────

/// @notice Snapshot of Lido protocol state at a given block sample
struct LidoSnapshot {
    /// @notice Total ETH pooled in Lido (in wei)
    uint256 totalPooledEther;
    /// @notice Total stETH shares outstanding
    uint256 totalShares;
    /// @notice wstETH redemption rate: ETH per 1e18 shares (scaled 1e18)
    uint256 wstEthRate;
    /// @notice Share-to-pooled ratio in basis points (10000 = 1.0000)
    uint256 shareRatioBps;
    /// @notice True if all external calls succeeded
    bool valid;
}

// ─────────────────────────────────────────────
//  Trap contract
// ─────────────────────────────────────────────

contract LidoProtocolAnomalySentinel is ITrap {

    // ── Constants ────────────────────────────

    /// @notice Lido stETH proxy on Hoodi testnet
    address public constant STETH  = 0x3508A952176b3c15387C97BE809eaffB1982176a;

    /// @notice Lido wstETH on Hoodi testnet
    address public constant WSTETH = 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4;

    /// @notice Minimum pooled ETH required before monitoring is meaningful
    uint256 public constant MIN_POOLED_ETH = 1 ether;

    /// @notice Basis points denominator (10 000 bps = 100%)
    uint256 public constant BPS_DENOM = 10_000;

    /// @notice Alert if totalPooledEther drops by more than 5% (500 bps)
    uint256 public constant POOLED_DROP_BPS = 500;

    /// @notice Alert if wstETH redemption rate drops by more than 3% (300 bps)
    uint256 public constant RATE_DROP_BPS = 300;

    /// @notice Alert if share ratio deviates by more than 10% (1000 bps)
    uint256 public constant RATIO_DEVIATION_BPS = 1_000;

    // ── collect() ────────────────────────────

    /**
     * @notice Collects a LidoSnapshot from both stETH and wstETH contracts.
     * @dev    Uses try/catch on every external call so that a revert in the
     *         monitored contracts never causes collect() itself to revert.
     *         If any call fails the snapshot is marked invalid (valid = false)
     *         and shouldRespond() will safely skip it.
     * @return ABI-encoded LidoSnapshot struct
     */
    function collect() external view returns (bytes memory) {
        LidoSnapshot memory snap;

        // ── Fetch totalPooledEther ───────────
        try IStETH(STETH).getTotalPooledEther() returns (uint256 pooled) {
            snap.totalPooledEther = pooled;
        } catch {
            snap.valid = false;
            return abi.encode(snap);
        }

        // ── Fetch totalShares ────────────────
        try IStETH(STETH).getTotalShares() returns (uint256 shares) {
            snap.totalShares = shares;
        } catch {
            snap.valid = false;
            return abi.encode(snap);
        }

        // ── Fetch wstETH redemption rate ─────
        try IWstETH(WSTETH).getPooledEthByShares(1e18) returns (uint256 rate) {
            snap.wstEthRate = rate;
        } catch {
            snap.valid = false;
            return abi.encode(snap);
        }

        // ── Derive share ratio in bps ────────
        if (snap.totalPooledEther > 0) {
            snap.shareRatioBps =
                (snap.totalShares * BPS_DENOM) / snap.totalPooledEther;
        }

        snap.valid = true;
        return abi.encode(snap);
    }

    // ── shouldRespond() ──────────────────────

    /**
     * @notice Analyses 3 consecutive LidoSnapshots for sustained anomalies.
     * @dev    Three independent checks run in order of severity:
     *
     *         Check A — Pooled ETH collapse
     *           Immediate trigger if totalPooledEther drops > POOLED_DROP_BPS
     *           versus the oldest sample. No mid-sample confirmation needed
     *           because a 5%+ drop is already extreme.
     *
     *         Check B — wstETH redemption rate drop
     *           Triggers if rate drops > RATE_DROP_BPS from oldest to current
     *           AND the mid-sample also shows a drop (sustained, not a spike).
     *
     *         Check C — Share ratio deviation
     *           Triggers if shareRatioBps deviates > RATIO_DEVIATION_BPS in
     *           BOTH mid and current samples (sustained divergence).
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

        // Skip if any snapshot failed to collect
        if (!current.valid || !mid.valid || !oldest.valid) {
            return (false, bytes(""));
        }

        // Skip if pooled ETH is below meaningful threshold
        if (current.totalPooledEther < MIN_POOLED_ETH ||
            oldest.totalPooledEther  < MIN_POOLED_ETH) {
            return (false, bytes(""));
        }

        // ── Check A: Pooled ETH collapse ─────
        if (current.totalPooledEther < oldest.totalPooledEther) {
            uint256 dropBps =
                ((oldest.totalPooledEther - current.totalPooledEther)
                    * BPS_DENOM) / oldest.totalPooledEther;

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
        if (oldest.wstEthRate > 0 &&
            current.wstEthRate < oldest.wstEthRate) {

            uint256 rateDropBps =
                ((oldest.wstEthRate - current.wstEthRate)
                    * BPS_DENOM) / oldest.wstEthRate;

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

        // ── Check C: Share ratio deviation ───
        if (oldest.shareRatioBps > 0) {
            uint256 currentDev = current.shareRatioBps > oldest.shareRatioBps
                ? current.shareRatioBps - oldest.shareRatioBps
                : oldest.shareRatioBps - current.shareRatioBps;

            uint256 midDev = mid.shareRatioBps > oldest.shareRatioBps
                ? mid.shareRatioBps - oldest.shareRatioBps
                : oldest.shareRatioBps - mid.shareRatioBps;

            if (currentDev >= RATIO_DEVIATION_BPS &&
                midDev    >= RATIO_DEVIATION_BPS) {
                return (true, abi.encode(
                    uint8(3),
                    current.shareRatioBps,
                    oldest.shareRatioBps,
                    currentDev
                ));
            }
        }

        return (false, bytes(""));
    }
}
