// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  Lido Sentinel Response — v3
 * @author DAOmindbreaker
 * @notice Response contract for LidoSentinelV3.
 *
 * @dev    Anomaly ID mapping:
 *           1  = Pooled ETH Collapse         (CRITICAL)
 *           2  = wstETH Rate Drop            (HIGH)
 *           3  = Rate Consistency Breach     (HIGH)
 *           4  = Withdrawal Queue Stress     (HIGH)
 *           10 = Pooled ETH Soft Drop        (ALERT)
 *           11 = wstETH Rate Soft Drop       (ALERT)
 *           12 = Withdrawal Queue Build-up   (ALERT)
 */
contract LidoSentinelV3Response {

    // ── Events ───────────────────────────────
    event PooledEthCollapse(uint256 indexed blockNumber, uint256 currentPooled, uint256 oldestPooled, uint256 dropBps);
    event WstEthRateDrop(uint256 indexed blockNumber, uint256 currentRate, uint256 oldestRate, uint256 dropBps);
    event RateConsistencyBreach(uint256 indexed blockNumber, uint256 consistencyBps, uint256 wstEthRate, uint256 stEthInternalRate);
    event WithdrawalQueueStress(uint256 indexed blockNumber, uint256 unfinalizedStETH, uint256 totalPooled, uint256 queueBps);
    event PooledEthSoftDrop(uint256 indexed blockNumber, uint256 currentPooled, uint256 midPooled, uint256 dropBps);
    event WstEthRateSoftDrop(uint256 indexed blockNumber, uint256 currentRate, uint256 midRate, uint256 dropBps);
    event WithdrawalQueueBuildUp(uint256 indexed blockNumber, uint256 unfinalizedStETH, uint256 totalPooled, uint256 queueBps);
    event UnknownAnomalySignal(uint256 indexed blockNumber, uint8 anomalyId, uint256 a, uint256 b, uint256 c);

    // ── State ────────────────────────────────
    uint256 public totalAnomalies;
    uint256 public lastAnomalyBlock;
    uint8   public lastAnomalyId;

    // ── Entrypoint ───────────────────────────
    function handleAnomaly(uint8 anomalyId, uint256 a, uint256 b, uint256 c) external {
        unchecked { ++totalAnomalies; }
        lastAnomalyBlock = block.number;
        lastAnomalyId    = anomalyId;

        if      (anomalyId == 1)  emit PooledEthCollapse(block.number, a, b, c);
        else if (anomalyId == 2)  emit WstEthRateDrop(block.number, a, b, c);
        else if (anomalyId == 3)  emit RateConsistencyBreach(block.number, a, b, c);
        else if (anomalyId == 4)  emit WithdrawalQueueStress(block.number, a, b, c);
        else if (anomalyId == 10) emit PooledEthSoftDrop(block.number, a, b, c);
        else if (anomalyId == 11) emit WstEthRateSoftDrop(block.number, a, b, c);
        else if (anomalyId == 12) emit WithdrawalQueueBuildUp(block.number, a, b, c);
        else                      emit UnknownAnomalySignal(block.number, anomalyId, a, b, c);
    }

    function hasRecordedAnomaly() external view returns (bool) {
        return totalAnomalies > 0;
    }
}
