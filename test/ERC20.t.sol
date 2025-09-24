// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20} from "../src/ERC20.sol";
import {console} from "forge-std/console.sol";

contract ERC20Harness is ERC20 {
    address internal _owner;

    constructor() ERC20("Test Token", "TTK", 18) {
        _owner = msg.sender;
        _mint(msg.sender, 21_000_000 * 10 ** 18);
    }

    error OnlyOwnerCanDoThat();

    modifier onlyOwner() {
        if (msg.sender != _owner) {
            revert OnlyOwnerCanDoThat();
        }
        _;
    }

    function mint(address to, uint256 value) external onlyOwner {
        _mint(to, value);
    }

    function burn(address from, uint256 value) external onlyOwner {
        _burn(from, value);
    }
}

contract ERC20Handler is Test {
    ERC20Harness public token;
    address[] public actors;
    address public owner;

    constructor() {
        owner = address(this);
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("john"));
        actors.push(makeAddr("johanna"));
        actors.push(makeAddr("kira"));
        token = new ERC20Harness();
        for (uint256 i = 0; i < actors.length; i++) {
            token.transfer(actors[i], 1_000 * 10 ** 18);
        }
    }

    /// @notice Returns the sum of balances tracked by this handler (owner and all actors).
    /// @dev If you add/remove actors or move tokens to addresses outside this set,
    ///      update this function; otherwise the total-supply invariant may appear to fail.
    /// @return sumB The total tracked balance.
    function getSumBalances() public view returns (uint256 sumB) {
        sumB = token.balanceOf(owner);
        for (uint256 i = 0; i < actors.length; i++) {
            sumB += token.balanceOf(actors[i]);
        }
    }

    function approve(uint256 actorNumber, uint256 value) public returns (bool) {
        actorNumber = bound(actorNumber, 0, actors.length - 1);
        value = bound(value, 0, type(uint256).max);
        vm.prank(owner);
        bool ret = token.approve(actors[actorNumber], value);
        assertTrue(ret);
        return true;
    }

    function transfer(uint256 actorNumber, uint256 value) public returns (bool) {
        actorNumber = bound(actorNumber, 0, actors.length - 1);
        value = bound(value, 0, token.balanceOf(owner));
        vm.prank(owner);
        bool ret = token.transfer(actors[actorNumber], value);
        assertTrue(ret);
        return true;
    }

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

        value = bound(value, 0, token.balanceOf(from));
        if (value == 0) {
            return true;
        }
        uint256 allowance = token.allowance(from, spender);
        if (allowance < value) {
            // case we need to set to 0 first
            if (allowance != 0) {
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

    function burn(uint256 actorNumber, uint256 value) public returns (bool) {
        actorNumber = bound(actorNumber, 0, actors.length - 1);
        // bound value so it doesn't exceed target balance (optional)
        value = bound(value, 0, token.balanceOf(actors[actorNumber]));
        // calling token.burn from this contract -> msg.sender == address(this) (the owner)
        token.burn(actors[actorNumber], value);
        return true;
    }

    function mint(uint256 actorNumber, uint256 value) public returns (bool) {
        actorNumber = bound(actorNumber, 0, actors.length - 1);
        // bound value so it doesn't exceed target balance (optional)
        value = bound(value, 1, 21_000_000 * 10 ** 18);
        // calling token.burn from this contract -> msg.sender == address(this) (the owner)
        token.mint(actors[actorNumber], value);
        return true;
    }
}

contract ERC20Test is StdInvariant, Test {
    ERC20Handler ercH;

    function setUp() public {
        ercH = new ERC20Handler();
        targetContract(address(ercH));
    }

    function invariant_sumBalances_is_totalSupply() public view {
        assertEq(ercH.getSumBalances(), ercH.token().totalSupply());
    }
}
