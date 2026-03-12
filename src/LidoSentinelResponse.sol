// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  Lido Sentinel Response
 * @author DAOmindbreaker
 * @notice On-chain response contract for the LidoProtocolAnomalySentinel Drosera Trap.
 *         Receives structured anomaly reports from the Trap and emits fully typed
 *         events so that any off-chain indexer, alert system, or governance module
 *         can react to Lido protocol anomalies in real time.
 *
 * @dev    Three response entry-points map 1-to-1 with the three detection checks
 *         in LidoProtocolAnomalySentinel:
 *           - recordPooledEthCollapse()   → Check A (anomaly type 1)
 *           - recordWstEthRateDrop()      → Check B (anomaly type 2)
 *           - recordShareRatioDeviation() → Check C (anomaly type 3)
 *
 *         All values use the same units as the Trap:
 *           - ETH amounts  : wei (1e18)
 *           - Rates        : scaled 1e18
 *           - Deviations   : basis points (10 000 = 100%)
 */

contract LidoSentinelResponse {

    // ─────────────────────────────────────────
    //  State
    // ─────────────────────────────────────────

    /// @notice Address of the authorised LidoProtocolAnomalySentinel Trap
    address public immutable authorisedTrap;

    /// @notice Deployer / admin
    address public immutable admin;

    /// @notice Monotonically increasing counter — unique ID per anomaly report
    uint256 public anomalyCount;

    // ─────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────

    /**
     * @notice Emitted when a pooled ETH collapse is detected (Check A)
     * @param id             Unique anomaly report ID
     * @param currentValue   Current totalPooledEther (wei)
     * @param baselineValue  Oldest sample totalPooledEther (wei)
     * @param dropBps        Drop magnitude in basis points
     * @param timestamp      Block timestamp of detection
     */
    event PooledEthCollapse(
        uint256 indexed id,
        uint256 currentValue,
        uint256 baselineValue,
        uint256 dropBps,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a sustained wstETH redemption rate drop is detected (Check B)
     * @param id             Unique anomaly report ID
     * @param currentRate    Current wstETH rate (ETH per 1e18 shares)
     * @param baselineRate   Oldest sample wstETH rate
     * @param dropBps        Drop magnitude in basis points
     * @param timestamp      Block timestamp of detection
     */
    event WstEthRateDrop(
        uint256 indexed id,
        uint256 currentRate,
        uint256 baselineRate,
        uint256 dropBps,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a sustained share ratio deviation is detected (Check C)
     * @param id               Unique anomaly report ID
     * @param currentRatioBps  Current shareRatioBps
     * @param baselineRatioBps Oldest sample shareRatioBps
     * @param deviationBps     Absolute deviation in basis points
     * @param timestamp        Block timestamp of detection
     */
    event ShareRatioDeviation(
        uint256 indexed id,
        uint256 currentRatioBps,
        uint256 baselineRatioBps,
        uint256 deviationBps,
        uint256 timestamp
    );

    /// @notice Emitted when an unauthorised caller attempts to submit a report
    event UnauthorisedCall(address indexed caller, uint256 timestamp);

    // ─────────────────────────────────────────
    //  Errors
    // ─────────────────────────────────────────

    /// @dev Reverts when caller is not the authorised Trap contract
    error NotAuthorisedTrap(address caller);

    /// @dev Reverts when payload values are invalid
    error InvalidPayload();

    // ─────────────────────────────────────────
    //  Modifier
    // ─────────────────────────────────────────

    modifier onlyTrap() {
        _onlyTrap();
        _;
    }

    function _onlyTrap() internal {
        if (msg.sender != authorisedTrap) {
            emit UnauthorisedCall(msg.sender, block.timestamp);
            revert NotAuthorisedTrap(msg.sender);
        }
    }

    // ─────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────

    /**
     * @param _authorisedTrap Address of the LidoProtocolAnomalySentinel Trap
     */
    constructor(address _authorisedTrap) {
        require(_authorisedTrap != address(0), "LidoSentinelResponse: zero address");
        authorisedTrap = _authorisedTrap;
        admin          = msg.sender;
    }

    // ─────────────────────────────────────────
    //  Response functions
    // ─────────────────────────────────────────

    /**
     * @notice Called by Trap when Check A fires — pooled ETH collapse
     * @param currentValue   Current totalPooledEther (wei)
     * @param baselineValue  Oldest sample totalPooledEther (wei)
     * @param dropBps        Drop magnitude in basis points
     */
    function recordPooledEthCollapse(
        uint256 currentValue,
        uint256 baselineValue,
        uint256 dropBps
    ) external onlyTrap {
        if (currentValue == 0 || baselineValue == 0) revert InvalidPayload();
        uint256 id = ++anomalyCount;
        emit PooledEthCollapse(id, currentValue, baselineValue, dropBps, block.timestamp);
    }

    /**
     * @notice Called by Trap when Check B fires — wstETH rate drop
     * @param currentRate   Current wstETH redemption rate
     * @param baselineRate  Oldest sample wstETH rate
     * @param dropBps       Drop magnitude in basis points
     */
    function recordWstEthRateDrop(
        uint256 currentRate,
        uint256 baselineRate,
        uint256 dropBps
    ) external onlyTrap {
        if (currentRate == 0 || baselineRate == 0) revert InvalidPayload();
        uint256 id = ++anomalyCount;
        emit WstEthRateDrop(id, currentRate, baselineRate, dropBps, block.timestamp);
    }

    /**
     * @notice Called by Trap when Check C fires — share ratio deviation
     * @param currentRatioBps   Current shareRatioBps
     * @param baselineRatioBps  Oldest sample shareRatioBps
     * @param deviationBps      Absolute deviation in basis points
     */
    function recordShareRatioDeviation(
        uint256 currentRatioBps,
        uint256 baselineRatioBps,
        uint256 deviationBps
    ) external onlyTrap {
        if (currentRatioBps == 0 || baselineRatioBps == 0) revert InvalidPayload();
        uint256 id = ++anomalyCount;
        emit ShareRatioDeviation(
            id,
            currentRatioBps,
            baselineRatioBps,
            deviationBps,
            block.timestamp
        );
    }

    // ─────────────────────────────────────────
    //  View helpers
    // ─────────────────────────────────────────

    /// @notice Returns total number of anomaly reports recorded
    function totalAnomalies() external view returns (uint256) {
        return anomalyCount;
    }

    /// @notice Returns authorised trap address
    function getAuthorisedTrap() external view returns (address) {
        return authorisedTrap;
    }
}
