// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LidoSentinelResponse.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        new LidoSentinelResponse(0x85E9047F1FCB5C4A14D99Ff7e702605db1D975AB);
        vm.stopBroadcast();
    }
}
