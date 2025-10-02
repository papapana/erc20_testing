# ERC-20 Invariant Testing (Foundry)

Goal: demonstrate invariant testing for an ERC-20 with a conservation law:
sum(balances of tracked holders) == totalSupply at all times.

This repository shows a minimal, practical setup using:

- a Harness contract that exposes mint/burn in a controlled way,
- a Handler that acts as the single fuzz entry point and orchestrates actions
  across a fixed set of actors to keep the system “closed,” and
- invariants that assert conservation of supply and safety constraints.

## Why a harness and a handler?

- Harness: adds test-only surface (owner-gated mint/burn) to the ERC-20 so the
  invariant engine can explore supply changes safely without opening up those functions
  in production code.
- Handler: is the only “user” the invariant fuzzer calls. It owns the token in tests,
  seeds a small set of sample accounts (actors), and exposes public methods for
  approve, transfer, transferFrom, mint, burn. This keeps tokens inside a tracked set
  (closed-world), so the supply conservation invariant is meaningful and debuggable.

## Project layout

- Token implementation
  - [src/ERC20.sol](src/ERC20.sol)
- Invariant testing
  - [test/ERC20.t.sol](test/ERC20.t.sol)
    - [`ERC20Harness`](test/ERC20.t.sol): test-only ERC-20 with owner-gated mint/burn
    - [`ERC20Handler`](test/ERC20.t.sol): fuzz entry points + tracked actors
    - Invariants: `invariant_sumBalances_is_totalSupply`, `invariant_zeroAddress_has_no_balance`

## The core invariant

Conservation of supply:

- sum(balances of tracked holders) == totalSupply

The tracked set is the Handler (owner) plus a fixed set of actors created via `makeAddr(...)`.
The handler seeds each actor with an initial balance from the owner so tokens remain inside
the tracked set unless you explicitly expand it.

Key pieces (see [test/ERC20.t.sol](test/ERC20.t.sol)):

- The harness mints an initial supply to the owner and exposes owner-gated mint/burn.

```solidity
contract ERC20Harness is ERC20 {
    address internal _owner;

    constructor() ERC20("Test Token", "TTK", 18) {
        _owner = msg.sender;
        _mint(msg.sender, 21_000_000 * 10 ** 18);
    }

    error OnlyOwnerCanDoThat();
    modifier onlyOwner() {
        if (msg.sender != _owner) revert OnlyOwnerCanDoThat();
        _;
    }

    function mint(address to, uint256 value) external onlyOwner { _mint(to, value); }
    function burn(address from, uint256 value) external onlyOwner { _burn(from, value); }
}
```

- The handler acts as owner, defines sample accounts, seeds balances, and exposes fuzzable actions.

```solidity
contract ERC20Handler is Test {
    ERC20Harness public token;
    address public owner;
    address[] public actors;

    constructor() {
        owner = address(this);
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("alice"));
        // ... more named actors ...

        token = new ERC20Harness();

        // Seed each actor while keeping tokens inside {owner + actors}.
        for (uint256 i = 0; i < actors.length; i++) {
            token.transfer(actors[i], 1_000 * 10 ** 18);
        }
    }

    function getSumBalances() public view returns (uint256 sumB) {
        sumB = token.balanceOf(owner);
        for (uint256 i = 0; i < actors.length; i++) {
            sumB += token.balanceOf(actors[i]);
        }
    }

    // Fuzz entry points: approve, transfer, transferFrom, mint, burn.
    // Each bounds inputs so fuzzing explores valid state without spurious reverts.
}
```

- Invariants assert the conservation law and basic safety:

```solidity
contract ERC20Test is StdInvariant, Test {
    ERC20Handler ercH;

    function setUp() public {
        ercH = new ERC20Handler();
        targetContract(address(ercH)); // all public funcs of handler are fuzzed
    }

    function invariant_sumBalances_is_totalSupply() public view {
        assertEq(ercH.getSumBalances(), ercH.token().totalSupply());
    }

    function invariant_zeroAddress_has_no_balance() public view {
        assertEq(ercH.token().balanceOf(address(0)), 0);
    }
}
```

## Closed-world assumption

The invariant is only correct if tokens cannot “escape” the tracked set. This repo enforces that by:

- Using a fixed actor set created in the handler.
- Seeding those actors from the owner and only transferring among them.
- Computing the sum over `{owner + actors}` in `getSumBalances()`.

If you add any flow that can send tokens outside this set (e.g., random addresses),
also add those addresses to the tracked set or adjust how `getSumBalances()` is computed.
Otherwise, the invariant will (correctly) fail due to untracked balances.

## Running the tests

- Run all tests (Mac):

```bash
forge test -vv
```

- Focus on invariant output:

```bash
forge test --mt invariant_ -vv
```

- Run a single test file:

```bash
forge test --match-path test/ERC20.t.sol -vv
```

## Tips when extending

- Keep the tracked set closed, or update `getSumBalances()` accordingly.
- Bound fuzz inputs to avoid meaningless reverts and increase state coverage.
- Keep owner-only test hooks (mint/burn) in the harness, not in production code.
- Add secondary invariants as you extend:
  - Allowance correctness after transferFrom
  - No balance underflows
  - Total supply changes only via mint/burn

## References

- Token implementation: [src/ERC20.sol](src/ERC20.sol)
- Test suite and invariants: [test/ERC20.t.sol](test/ERC20.t.sol)
