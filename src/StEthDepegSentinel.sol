// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

/**
 * @title stETH Depeg Sentinel
 * @notice Drosera Trap that monitors Lido wstETH/stETH ratio on Hoodi testnet
 * @dev Triggers an alert if the ETH-per-wstETH rate drops more than 5%
 *      compared to the previous block sample — indicating a potential depeg event.
 *
 * Use Case Reference: Liquid Restaking — Mitigating Depegs (Drosera Docs)
 * Lido wstETH on Hoodi: 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4
 */

interface IWstETH {
    /// @notice Returns how much ETH is pooled per given amount of shares
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
    /// @notice Returns total wstETH supply
    function totalSupply() external view returns (uint256);
}

contract StEthDepegSentinel is ITrap {

    /// @notice wstETH contract address on Hoodi testnet (Lido official)
    address public constant WSTETH = 0x7E99eE3C66636DE415D2d7C880938F2f40f94De4;

    /// @notice Depeg threshold — trigger if rate drops below 95% of previous rate (5% drop)
    uint256 public constant DEPEG_THRESHOLD = 95;

    /**
     * @notice Collects current wstETH/ETH rate and total supply
     * @return Encoded (ethPerWstEth, totalSupply)
     */
    function collect() external view returns (bytes memory) {
        IWstETH wsteth = IWstETH(WSTETH);
        // How much ETH can be redeemed for 1 wstETH (1e18 shares)
        uint256 ethPerWstEth = wsteth.getPooledEthByShares(1e18);
        uint256 totalSupply = wsteth.totalSupply();
        return abi.encode(ethPerWstEth, totalSupply);
    }

    /**
     * @notice Compares current rate vs previous rate to detect depeg
     * @dev Requires at least 2 data points for comparison
     * @return (true, encodedData) if depeg detected, (false, "") otherwise
     */
    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        // Need at least 2 blocks to compare
        if (data.length < 2) return (false, bytes(""));

        (uint256 currentRate,) = abi.decode(data[0], (uint256, uint256));
        (uint256 previousRate,) = abi.decode(data[1], (uint256, uint256));

        if (previousRate == 0) return (false, bytes(""));

        // Calculate ratio as percentage
        uint256 ratio = (currentRate * 100) / previousRate;

        // Alert if rate dropped more than 5%
        if (ratio < DEPEG_THRESHOLD) {
            return (true, abi.encode(currentRate, previousRate));
        }

        return (false, bytes(""));
    }
}
