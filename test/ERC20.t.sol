// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20} from "../src/ERC20.sol";
import {console} from "forge-std/console.sol"; // kept for ad‑hoc debugging; remove if unused

/// High-level overview
/// - We use a Harness that exposes mint/burn to an owner (the handler) for testing.
/// - We use a Handler as the single "system under test" entry point. Foundry's
///   invariant engine will randomly sequence calls to its public functions
///   (approve, transfer, transferFrom, mint, burn) to explore state space.
/// - Invariant: The sum of balances we track (owner + actors) must always equal totalSupply.
///   This is the conservation law for ERC20 under mint/burn/transfer.
///
/// Important: The invariant assumes a "closed world": tokens must not escape the set
/// {owner + actors}. If you add a function that transfers to any other address, also add
/// that address to the tracked set in getSumBalances() or the invariant will (correctly)
/// report a failure due to untracked balances.

contract ERC20Harness is ERC20 {
    /// The test-only "owner" allowed to mint/burn. This is set to the Handler.
    address internal _owner;

    /// Deploy a token with 21M initial supply minted to the owner (the Handler).
    constructor() ERC20("Test Token", "TTK", 18) {
        _owner = msg.sender;
        _mint(msg.sender, 21_000_000 * 10 ** 18);
    }

    /// Custom revert for owner checks to keep bytecode small and explicit.
    error OnlyOwnerCanDoThat();

    /// Restrict test-only mint/burn to the Handler.
    modifier onlyOwner() {
        if (msg.sender != _owner) {
            revert OnlyOwnerCanDoThat();
        }
        _;
    }

    /// Test-only: mint new tokens to arbitrary recipient (owner-gated).
    function mint(address to, uint256 value) external onlyOwner {
        _mint(to, value);
    }

    /// Test-only: burn tokens from arbitrary holder (owner-gated).
    function burn(address from, uint256 value) external onlyOwner {
        _burn(from, value);
    }
}

/// Stateful fuzzing handler used by Foundry's invariant testing.
/// Foundry will generate random sequences of calls to these public functions.
/// The handler takes both the "owner" role (for mint/burn, approve, transfer)
/// and orchestrates actor-to-actor approvals and transferFrom flows.
contract ERC20Handler is Test {
    ERC20Harness public token;

    /// The "owner" of the token in this scenario, i.e., this handler contract.
    address public owner;

    /// The actor set forms our closed-world of token holders.
    address[] public actors;

    constructor() {
        owner = address(this);

        // Small, fixed set of named actors for readability in traces.
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("john"));
        actors.push(makeAddr("johanna"));
        actors.push(makeAddr("kira"));

        // Deploy the harness. It mints 21M tokens to `owner` (this handler).
        token = new ERC20Harness();

        // Seed each actor with an initial balance from the owner's supply.
        // Note: This keeps all balances inside {owner + actors}.
        for (uint256 i = 0; i < actors.length; i++) {
            token.transfer(actors[i], 1_000 * 10 ** 18);
        }
    }

    /// Returns the sum of balances tracked by this handler (owner and all actors).
    /// If you widen the address universe (e.g., transfer to new addresses),
    /// update this function to include them; otherwise the total-supply invariant
    /// will appear to fail due to untracked balances.
    function getSumBalances() public view returns (uint256 sumB) {
        sumB = token.balanceOf(owner);
        for (uint256 i = 0; i < actors.length; i++) {
            sumB += token.balanceOf(actors[i]);
        }
    }

    /// Owner approves an actor to spend on its behalf.
    /// We bound value to uint256 max to reach the infinite-allowance path too.
    function approve(uint256 actorNumber, uint256 value) public returns (bool) {
        actorNumber = bound(actorNumber, 0, actors.length - 1);
        value = bound(value, 0, type(uint256).max);

        vm.prank(owner); // msg.sender == owner
        bool ret = token.approve(actors[actorNumber], value);
        assertTrue(ret);
        return true;
    }

    /// Owner transfers tokens directly to an actor.
    /// Value is bounded to the owner's current balance to avoid spurious reverts.
    function transfer(uint256 actorNumber, uint256 value) public returns (bool) {
        actorNumber = bound(actorNumber, 0, actors.length - 1);
        value = bound(value, 0, token.balanceOf(owner));

        vm.prank(owner); // msg.sender == owner
        bool ret = token.transfer(actors[actorNumber], value);
        assertTrue(ret);
        return true;
    }

    /// Actor `spender` pulls tokens from actor `from` and sends to actor `to`.
    /// We manage allowances by resetting to zero first if needed, then setting exact value.
    /// This covers both the exact-allowance and infinite-allowance code paths.
    function transferFrom(uint256 spenderActorNumber, uint256 fromActorNumber, uint256 toActorNumber, uint256 value)
        public
        returns (bool)
    {
        spenderActorNumber = bound(spenderActorNumber, 0, actors.length - 1);
        fromActorNumber = bound(fromActorNumber, 0, actors.length - 1);
        toActorNumber = bound(toActorNumber, 0, actors.length - 1);

        address spender = actors[spenderActorNumber];
        address from = actors[fromActorNumber];
        address to = actors[toActorNumber];

        // Keep the execution meaningful: don't exceed balance and skip no-ops.
        value = bound(value, 0, token.balanceOf(from));
        if (value == 0) return true;

        uint256 current = token.allowance(from, spender);

        // Pattern: some ERC20s require setting allowance to 0 before changing it.
        // Using this pattern increases cross-compatibility of the test.
        if (current < value) {
            if (current != 0) {
                vm.prank(from);
                token.approve(spender, 0);
            }
            vm.prank(from);
            token.approve(spender, value);
        }

        vm.prank(spender);
        bool ret = token.transferFrom(from, to, value);
        assertTrue(ret);
        return true;
    }

    /// Owner burns tokens from an actor.
    /// Value is bounded to the target's balance to avoid underflow reverts.
    function burn(uint256 actorNumber, uint256 value) public returns (bool) {
        actorNumber = bound(actorNumber, 0, actors.length - 1);
        value = bound(value, 0, token.balanceOf(actors[actorNumber]));

        // msg.sender == address(this) == owner, so burn is authorized.
        token.burn(actors[actorNumber], value);
        return true;
    }

    /// Owner mints tokens to an actor.
    /// Value is bounded to a reasonable range to exercise totalSupply growth.
    function mint(uint256 actorNumber, uint256 value) public returns (bool) {
        actorNumber = bound(actorNumber, 0, actors.length - 1);
        value = bound(value, 1, 21_000_000 * 10 ** 18);

        // msg.sender == address(this) == owner, so mint is authorized.
        token.mint(actors[actorNumber], value);
        return true;
    }
}

/// Invariant test suite.
/// Foundry's StdInvariant will repeatedly call the handler's public methods
/// in random sequences and check the invariant after each sequence.
contract ERC20Test is StdInvariant, Test {
    ERC20Handler ercH;

    function setUp() public {
        ercH = new ERC20Handler();

        // Register the handler as the "target contract" for invariant testing.
        // All of its public functions become fuzzable entry points.
        targetContract(address(ercH));
    }

    /// Conservation of supply invariant:
    /// The sum of balances we track (owner + all actors) must always equal totalSupply.
    /// Mint and burn adjust totalSupply, and transfers only move value within the set,
    /// so equality must hold if no tokens escape the tracked set.
    function invariant_sumBalances_is_totalSupply() public view {
        assertEq(ercH.getSumBalances(), ercH.token().totalSupply());
    }

    /// Zero address must never hold tokens.
    /// Our ERC20 forbids transfers/mints to address(0), and burn does not credit it.
    function invariant_zeroAddress_has_no_balance() public view {
        assertEq(ercH.token().balanceOf(address(0)), 0);
    }
}
