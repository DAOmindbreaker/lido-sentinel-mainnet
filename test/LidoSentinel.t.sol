// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LidoProtocolAnomalySentinel.sol";
import "../src/LidoSentinelResponse.sol";

/**
 * @title  LidoProtocolAnomalySentinel Tests
 * @notice Fork tests against Ethereum Mainnet state
 * @dev    Run with: forge test --fork-url https://eth.llamarpc.com -vvv
 */
contract LidoSentinelTest is Test {
    LidoProtocolAnomalySentinel public trap;
    LidoSentinelResponse public response;

    function setUp() public {
        trap = new LidoProtocolAnomalySentinel();
        response = new LidoSentinelResponse();
    }

    // ═══════════════════════════════════════════
    //  Constants Verification
    // ═══════════════════════════════════════════

    function test_Constants() public view {
        assertEq(trap.STETH(), 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        assertEq(trap.WSTETH(), 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        assertEq(trap.MIN_POOLED_ETH(), 1 ether);
        assertEq(trap.BPS_DENOM(), 10_000);
        assertEq(trap.POOLED_DROP_BPS(), 500);
        assertEq(trap.RATE_DROP_BPS(), 300);
        assertEq(trap.RATE_CONSISTENCY_BPS(), 50);
        assertEq(trap.POOLED_DROP_ALERT_BPS(), 200);
        assertEq(trap.RATE_DROP_ALERT_BPS(), 100);
    }

    // ═══════════════════════════════════════════
    //  collect() Tests
    // ═══════════════════════════════════════════

    function test_Collect_ReturnsValidSnapshot() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory snap = abi.decode(data, (LidoSnapshot));

        assertTrue(snap.valid, "Snapshot should be valid");
        assertGt(snap.totalPooledEther, 0, "totalPooledEther should be > 0");
        assertGt(snap.totalShares, 0, "totalShares should be > 0");
        assertGt(snap.wstEthRate, 0, "wstEthRate should be > 0");
        assertGt(snap.stEthInternalRate, 0, "stEthInternalRate should be > 0");
    }

    function test_Collect_RatesAreConsistent() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory snap = abi.decode(data, (LidoSnapshot));

        // stETH and wstETH rates should be very close (within 1 bps normally)
        assertTrue(snap.rateConsistencyBps < 10, "Rate consistency should be < 10 bps under normal conditions");
    }

    function test_Collect_PooledEtherIsReasonable() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory snap = abi.decode(data, (LidoSnapshot));

        // Lido has $30B+ TVL, so totalPooledEther should be > 1M ETH
        assertGt(snap.totalPooledEther, 1_000_000 ether, "Lido should have > 1M ETH pooled");
    }

    // ═══════════════════════════════════════════
    //  shouldRespond() Tests
    // ═══════════════════════════════════════════

    function test_ShouldRespond_NormalConditions_ReturnsFalse() public {
        bytes memory data = trap.collect();
        bytes[] memory samples = new bytes[](3);
        samples[0] = data;
        samples[1] = data;
        samples[2] = data;

        (bool respond, bytes memory payload) = trap.shouldRespond(samples);
        assertFalse(respond, "Should not respond under normal conditions");
        assertEq(payload.length, 0, "Payload should be empty");
    }

    function test_ShouldRespond_InsufficientSamples_ReturnsFalse() public {
        bytes[] memory samples = new bytes[](2);
        samples[0] = trap.collect();
        samples[1] = trap.collect();

        (bool respond,) = trap.shouldRespond(samples);
        assertFalse(respond, "Should not respond with < 3 samples");
    }

    function test_ShouldRespond_InvalidSnapshot_ReturnsFalse() public {
        LidoSnapshot memory invalidSnap;
        invalidSnap.valid = false;

        bytes[] memory samples = new bytes[](3);
        samples[0] = abi.encode(invalidSnap);
        samples[1] = trap.collect();
        samples[2] = trap.collect();

        (bool respond,) = trap.shouldRespond(samples);
        assertFalse(respond, "Should not respond with invalid snapshot");
    }

    function test_ShouldRespond_CheckA_PooledEthCollapse() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory current = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory oldest = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory mid = abi.decode(data, (LidoSnapshot));

        // Simulate 6% drop (above 5% threshold)
        current.totalPooledEther = (oldest.totalPooledEther * 94) / 100;

        bytes[] memory samples = new bytes[](3);
        samples[0] = abi.encode(current);
        samples[1] = abi.encode(mid);
        samples[2] = abi.encode(oldest);

        (bool respond, bytes memory payload) = trap.shouldRespond(samples);
        assertTrue(respond, "Should respond to 6% pooled ETH drop");

        (uint8 checkId,,,) = abi.decode(payload, (uint8, uint256, uint256, uint256));
        assertEq(checkId, 1, "Check ID should be 1 (Pooled ETH Collapse)");
    }

    function test_ShouldRespond_CheckA_BelowThreshold_ReturnsFalse() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory current = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory oldest = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory mid = abi.decode(data, (LidoSnapshot));

        // Simulate 4% drop (below 5% threshold)
        current.totalPooledEther = (oldest.totalPooledEther * 96) / 100;

        bytes[] memory samples = new bytes[](3);
        samples[0] = abi.encode(current);
        samples[1] = abi.encode(mid);
        samples[2] = abi.encode(oldest);

        (bool respond,) = trap.shouldRespond(samples);
        assertFalse(respond, "Should not respond to 4% drop (below threshold)");
    }

    function test_ShouldRespond_CheckB_RateDrop() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory current = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory oldest = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory mid = abi.decode(data, (LidoSnapshot));

        // Simulate 4% rate drop sustained
        current.wstEthRate = (oldest.wstEthRate * 96) / 100;
        mid.wstEthRate = (oldest.wstEthRate * 98) / 100;

        bytes[] memory samples = new bytes[](3);
        samples[0] = abi.encode(current);
        samples[1] = abi.encode(mid);
        samples[2] = abi.encode(oldest);

        (bool respond, bytes memory payload) = trap.shouldRespond(samples);
        assertTrue(respond, "Should respond to sustained 4% rate drop");

        (uint8 checkId,,,) = abi.decode(payload, (uint8, uint256, uint256, uint256));
        assertEq(checkId, 2, "Check ID should be 2 (wstETH Rate Drop)");
    }

    function test_ShouldRespond_CheckB_NotSustained_ReturnsFalse() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory current = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory oldest = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory mid = abi.decode(data, (LidoSnapshot));

        // Rate drops in current but mid is higher than oldest (spike, not sustained)
        current.wstEthRate = (oldest.wstEthRate * 96) / 100;
        mid.wstEthRate = oldest.wstEthRate + 1; // mid NOT dropped

        bytes[] memory samples = new bytes[](3);
        samples[0] = abi.encode(current);
        samples[1] = abi.encode(mid);
        samples[2] = abi.encode(oldest);

        (bool respond,) = trap.shouldRespond(samples);
        assertFalse(respond, "Should not respond when drop is not sustained");
    }

    function test_ShouldRespond_CheckC_RateConsistencyBreach() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory current = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory oldest = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory mid = abi.decode(data, (LidoSnapshot));

        // Simulate rate inconsistency > 50 bps in both current and mid
        current.rateConsistencyBps = 100; // 1%
        mid.rateConsistencyBps = 75; // 0.75%

        bytes[] memory samples = new bytes[](3);
        samples[0] = abi.encode(current);
        samples[1] = abi.encode(mid);
        samples[2] = abi.encode(oldest);

        (bool respond, bytes memory payload) = trap.shouldRespond(samples);
        assertTrue(respond, "Should respond to sustained rate inconsistency");

        (uint8 checkId,,,) = abi.decode(payload, (uint8, uint256, uint256, uint256));
        assertEq(checkId, 3, "Check ID should be 3 (Rate Consistency Breach)");
    }

    function test_ShouldRespond_MinPooledEth_ReturnsFalse() public {
        LidoSnapshot memory snap;
        snap.valid = true;
        snap.totalPooledEther = 0.5 ether; // Below MIN_POOLED_ETH

        bytes[] memory samples = new bytes[](3);
        samples[0] = abi.encode(snap);
        samples[1] = abi.encode(snap);
        samples[2] = abi.encode(snap);

        (bool respond,) = trap.shouldRespond(samples);
        assertFalse(respond, "Should not respond when pooled ETH below minimum");
    }

    // ═══════════════════════════════════════════
    //  shouldAlert() Tests
    // ═══════════════════════════════════════════

    function test_ShouldAlert_NormalConditions_ReturnsFalse() public {
        bytes memory data = trap.collect();
        bytes[] memory samples = new bytes[](2);
        samples[0] = data;
        samples[1] = data;

        (bool alert,) = trap.shouldAlert(samples);
        assertFalse(alert, "Should not alert under normal conditions");
    }

    function test_ShouldAlert_InsufficientSamples_ReturnsFalse() public {
        bytes[] memory samples = new bytes[](1);
        samples[0] = trap.collect();

        (bool alert,) = trap.shouldAlert(samples);
        assertFalse(alert, "Should not alert with < 2 samples");
    }

    function test_ShouldAlert_AlertA_PooledSoftDrop() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory current = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory mid = abi.decode(data, (LidoSnapshot));

        // Simulate 3% drop (above 2% alert threshold, below 5% respond threshold)
        current.totalPooledEther = (mid.totalPooledEther * 97) / 100;

        bytes[] memory samples = new bytes[](2);
        samples[0] = abi.encode(current);
        samples[1] = abi.encode(mid);

        (bool alert, bytes memory payload) = trap.shouldAlert(samples);
        assertTrue(alert, "Should alert on 3% pooled ETH drop");

        (uint8 alertId,,,) = abi.decode(payload, (uint8, uint256, uint256, uint256));
        assertEq(alertId, 10, "Alert ID should be 10");
    }

    function test_ShouldAlert_AlertB_RateSoftDrop() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory current = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory mid = abi.decode(data, (LidoSnapshot));

        // Simulate 1.5% rate drop (above 1% alert, below 3% respond)
        current.wstEthRate = (mid.wstEthRate * 985) / 1000;

        bytes[] memory samples = new bytes[](2);
        samples[0] = abi.encode(current);
        samples[1] = abi.encode(mid);

        (bool alert, bytes memory payload) = trap.shouldAlert(samples);
        assertTrue(alert, "Should alert on 1.5% rate drop");

        (uint8 alertId,,,) = abi.decode(payload, (uint8, uint256, uint256, uint256));
        assertEq(alertId, 11, "Alert ID should be 11");
    }

    // ═══════════════════════════════════════════
    //  Response Contract Tests
    // ═══════════════════════════════════════════

    function test_Response_InitialState() public view {
        assertEq(response.totalAnomalies(), 0);
        assertEq(response.lastAnomalyBlock(), 0);
        assertEq(response.lastAnomalyId(), 0);
        assertFalse(response.hasRecordedAnomaly());
    }

    function test_Response_HandleAnomaly_CheckA() public {
        response.handleAnomaly(1, 1000 ether, 1100 ether, 909);

        assertEq(response.totalAnomalies(), 1);
        assertEq(response.lastAnomalyId(), 1);
        assertTrue(response.hasRecordedAnomaly());
    }

    function test_Response_HandleAnomaly_CheckB() public {
        response.handleAnomaly(2, 1.1e18, 1.15e18, 434);

        assertEq(response.totalAnomalies(), 1);
        assertEq(response.lastAnomalyId(), 2);
    }

    function test_Response_HandleAnomaly_CheckC() public {
        response.handleAnomaly(3, 75, 1.15e18, 1.14e18);

        assertEq(response.totalAnomalies(), 1);
        assertEq(response.lastAnomalyId(), 3);
    }

    function test_Response_HandleAnomaly_UnknownId() public {
        response.handleAnomaly(99, 1, 2, 3);

        assertEq(response.totalAnomalies(), 1);
        assertEq(response.lastAnomalyId(), 99);
    }

    function test_Response_MultipleAnomalies() public {
        response.handleAnomaly(1, 100, 200, 300);
        response.handleAnomaly(2, 400, 500, 600);
        response.handleAnomaly(3, 700, 800, 900);

        assertEq(response.totalAnomalies(), 3);
        assertEq(response.lastAnomalyId(), 3);
    }

    // ═══════════════════════════════════════════
    //  Priority Tests (Check ordering)
    // ═══════════════════════════════════════════

    function test_ShouldRespond_CheckA_HasPriority() public {
        bytes memory data = trap.collect();
        LidoSnapshot memory current = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory oldest = abi.decode(data, (LidoSnapshot));
        LidoSnapshot memory mid = abi.decode(data, (LidoSnapshot));

        // Trigger both Check A and Check B simultaneously
        current.totalPooledEther = (oldest.totalPooledEther * 94) / 100; // 6% drop
        current.wstEthRate = (oldest.wstEthRate * 96) / 100; // 4% rate drop
        mid.wstEthRate = (oldest.wstEthRate * 98) / 100;

        bytes[] memory samples = new bytes[](3);
        samples[0] = abi.encode(current);
        samples[1] = abi.encode(mid);
        samples[2] = abi.encode(oldest);

        (bool respond, bytes memory payload) = trap.shouldRespond(samples);
        assertTrue(respond);

        (uint8 checkId,,,) = abi.decode(payload, (uint8, uint256, uint256, uint256));
        assertEq(checkId, 1, "Check A should have priority over Check B");
    }
}
