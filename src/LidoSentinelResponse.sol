// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  Lido Sentinel Response — v2
 * @author DAOmindbreaker
 * @notice On-chain response contract for LidoProtocolAnomalySentinel.
 *
 * @dev    Single entrypoint handleAnomaly(uint8,uint256,uint256,uint256)
 *         receives all check payloads from the trap via Drosera protocol.
 *
 *         Anomaly ID mapping:
 *           1  = Pooled ETH Collapse     (CRITICAL)
 *           2  = wstETH Rate Drop        (HIGH)
 *           3  = Rate Consistency Breach (HIGH)
 *           10 = Pooled ETH Soft Drop    (ALERT)
 *           11 = wstETH Rate Soft Drop   (ALERT)
 *
 * @dev    Authorization:
 *         Drosera protocol submits the on-chain callback — the caller is NOT
 *         the trap contract itself. No msg.sender restriction is applied.
 *         Access control can be layered on top if needed for production.
 */
contract LidoSentinelResponse {

    // ── Events ───────────────────────────────

    /// @notice Emitted when pooled ETH drops > 5% (Check A)
    event PooledEthCollapse(
        uint256 indexed blockNumber,
        uint256 currentPooled,
        uint256 oldestPooled,
        uint256 dropBps
    );

    /// @notice Emitted when wstETH redemption rate drops > 3% sustained (Check B)
    event WstEthRateDrop(
        uint256 indexed blockNumber,
        uint256 currentRate,
        uint256 oldestRate,
        uint256 dropBps
    );

    /// @notice Emitted when stETH/wstETH rates diverge > 50 bps sustained (Check C)
    event RateConsistencyBreach(
        uint256 indexed blockNumber,
        uint256 consistencyBps,
        uint256 wstEthRate,
        uint256 stEthInternalRate
    );

    /// @notice Emitted when pooled ETH drops > 2% (Alert A — early warning)
    event PooledEthSoftDrop(
        uint256 indexed blockNumber,
        uint256 currentPooled,
        uint256 midPooled,
        uint256 dropBps
    );

    /// @notice Emitted when wstETH rate drops > 1% (Alert B — early warning)
    event WstEthRateSoftDrop(
        uint256 indexed blockNumber,
        uint256 currentRate,
        uint256 midRate,
        uint256 dropBps
    );

    /// @notice Forward-compatible catch-all for unknown anomaly IDs
    event UnknownAnomalySignal(
        uint256 indexed blockNumber,
        uint8   anomalyId,
        uint256 a,
        uint256 b,
        uint256 c
    );

    // ── State ────────────────────────────────

    /// @notice Total anomaly events recorded (includes alerts)
    uint256 public totalAnomalies;

    /// @notice Last block number an anomaly was recorded
    uint256 public lastAnomalyBlock;

    /// @notice Last anomaly ID that triggered a response
    uint8 public lastAnomalyId;

    // ── Response entrypoint ──────────────────

    /**
     * @notice Single entrypoint for all LidoProtocolAnomalySentinel responses.
     * @dev    Called by Drosera protocol when shouldRespond() or shouldAlert() returns true.
     *         The anomalyId discriminant routes to the appropriate event.
     *
     *         Payload encoding per check:
     *           id=1:  (currentPooled, oldestPooled, dropBps)
     *           id=2:  (currentRate, oldestRate, dropBps)
     *           id=3:  (rateConsistencyBps, wstEthRate, stEthInternalRate)
     *           id=10: (currentPooled, midPooled, dropBps)
     *           id=11: (currentRate, midRate, dropBps)
     *
     * @param anomalyId  Discriminant identifying which check triggered (1–3, 10–11)
     * @param a          First payload value
     * @param b          Second payload value
     * @param c          Third payload value
     */
    function handleAnomaly(
        uint8   anomalyId,
        uint256 a,
        uint256 b,
        uint256 c
    ) external {
        unchecked { ++totalAnomalies; }
        lastAnomalyBlock = block.number;
        lastAnomalyId    = anomalyId;

        if (anomalyId == 1) {
            // Pooled ETH Collapse — a=currentPooled, b=oldestPooled, c=dropBps
            emit PooledEthCollapse(block.number, a, b, c);

        } else if (anomalyId == 2) {
            // wstETH Rate Drop — a=currentRate, b=oldestRate, c=dropBps
            emit WstEthRateDrop(block.number, a, b, c);

        } else if (anomalyId == 3) {
            // Rate Consistency Breach — a=consistencyBps, b=wstEthRate, c=stEthInternalRate
            emit RateConsistencyBreach(block.number, a, b, c);

        } else if (anomalyId == 10) {
            // Pooled ETH Soft Drop (Alert) — a=currentPooled, b=midPooled, c=dropBps
            emit PooledEthSoftDrop(block.number, a, b, c);

        } else if (anomalyId == 11) {
            // wstETH Rate Soft Drop (Alert) — a=currentRate, b=midRate, c=dropBps
            emit WstEthRateSoftDrop(block.number, a, b, c);

        } else {
            // Forward-compatible catch-all
            emit UnknownAnomalySignal(block.number, anomalyId, a, b, c);
        }
    }

    // ── View helpers ─────────────────────────

    /// @notice Returns true if any anomaly has ever been recorded
    function hasRecordedAnomaly() external view returns (bool) {
        return totalAnomalies > 0;
    }
}
