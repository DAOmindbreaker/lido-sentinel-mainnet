// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

contract BalanceMonitorTrap is ITrap {
    // Wallet yang dimonitor
    address public constant MONITORED_WALLET = 0x689Ad0f9cBa2dA64039cF894E9fB3Aa6266861D8;
    // Threshold — trigger kalau balance di bawah 0.01 ETH
    uint256 public constant THRESHOLD = 0.01 ether;

    function collect() external view returns (bytes memory) {
        uint256 balance = MONITORED_WALLET.balance;
        return abi.encode(balance);
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        uint256 balance = abi.decode(data[0], (uint256));
        if (balance < THRESHOLD) {
            return (true, abi.encode(balance));
        }
        return (false, bytes(""));
    }
}
