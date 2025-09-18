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
    address internal _owner;

    uint256 public ghostSupply;
    mapping(address => uint256) ghostBalanceOf;
    mapping(address => mapping(address => uint256)) ghostAllowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    uint256 public sumBalances;
    uint256 public transferFromCalls;

    constructor() {
        token = new ERC20Harness();
        _owner = msg.sender;
        ghostSupply = token.totalSupply();
        ghostBalanceOf[address(this)] += token.totalSupply();
        sumBalances += token.totalSupply();
    }

    function give(address to, uint256 amount) external {
        // if (msg.sender != _owner) return;
        uint256 maxGive = type(uint256).max - ghostSupply;
        if (maxGive == 0) {
            return;
        }
        amount = bound(amount, 1, maxGive);
        // vm.prank(_owner);
        token.mint(to, amount);
        ghostSupply += amount;
        ghostBalanceOf[to] += amount;
        sumBalances += amount;
    }

    function take(address from, uint256 amount) external {
        // if (msg.sender != _owner) return;
        uint256 max = ghostBalanceOf[from];
        if (max == 0) return;
        amount = bound(amount, 1, max);
        // vm.prank(_owner);
        token.burn(from, amount);
        ghostBalanceOf[from] -= amount;
        ghostSupply -= amount;
        sumBalances -= amount;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        vm.expectEmit(true, true, false, true);
        emit Approval(msg.sender, spender, value);
        vm.prank(msg.sender);
        bool ret = token.approve(spender, value);
        assertTrue(ret);
        ghostAllowance[msg.sender][spender] = value;
        assertEq(
            token.allowance(msg.sender, spender),
            ghostAllowance[msg.sender][spender]
        );
        return true;
    }

    function transfer(address to, uint256 value) public returns (bool) {
        if (ghostBalanceOf[msg.sender] == 0) {
            return true;
        }
        // make sure the token call won't revert by bounding to the actual token balance
        uint256 bal = token.balanceOf(msg.sender);
        if (bal == 0) return true;
        // bound by the real token balance of 'from' to avoid unexpected reverts/logs
        uint256 balFrom = token.balanceOf(msg.sender);
        if (balFrom == 0) return true;
        value = bound(value, 1, balFrom);

        vm.expectEmit(true, true, false, true);
        emit Transfer(msg.sender, to, value);
        vm.prank(msg.sender);
        bool ret = token.transfer(to, value);
        ghostBalanceOf[msg.sender] -= value;
        ghostBalanceOf[to] += value;
        assertTrue(ret);
        assertEq(token.balanceOf(msg.sender), ghostBalanceOf[msg.sender]);
        assertEq(token.balanceOf(to), ghostBalanceOf[to]);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public returns (bool) {
        if (from == address(0) || from == to) return true;

        // real token balance of 'from'
        uint256 balFrom = token.balanceOf(from);
        if (balFrom == 0) return true;

        // ensure there's an allowance for msg.sender; if not, create one by impersonating `from`
        if (ghostAllowance[from][msg.sender] == 0) {
            // grant allowance equal to the balance to make transferFrom possible
            uint256 grant = balFrom;
            vm.prank(from);
            bool ok = token.approve(msg.sender, grant);
            assertTrue(ok);
            ghostAllowance[from][msg.sender] = grant;
        }

        // bound by both balance and allowance
        uint256 maxAllowed = ghostAllowance[from][msg.sender];
        uint256 max = balFrom < maxAllowed ? balFrom : maxAllowed;
        if (max == 0) return true;
        value = bound(value, 1, max);

        vm.expectEmit(true, true, false, true);
        emit Transfer(from, to, value);
        vm.prank(msg.sender);
        bool ret = token.transferFrom(from, to, value);
        assertTrue(ret);

        if (ghostAllowance[from][msg.sender] != type(uint256).max) {
            ghostAllowance[from][msg.sender] -= value;
        }
        ghostBalanceOf[from] -= value;
        ghostBalanceOf[to] += value;
        assertEq(
            token.allowance(from, msg.sender),
            ghostAllowance[from][msg.sender]
        );
        assertEq(token.balanceOf(from), ghostBalanceOf[from]);
        assertEq(token.balanceOf(to), ghostBalanceOf[to]);
        transferFromCalls++;
        return true;
    }
}

contract ERC20Test is StdInvariant, Test {
    ERC20Handler internal ercH;
    function setUp() public {
        ercH = new ERC20Handler();
        targetContract(address(ercH));
        // targetSender(address(this));
    }

    function invariant_sum_balances_is_total_supply() public view {
        assertEq(
            ercH.token().totalSupply(),
            ercH.sumBalances(),
            "supply mismatch"
        );
    }

    // Runs after the invariant fuzzing completes.
    function afterInvariant() public view {
        console.log("transferFromCalls", ercH.transferFromCalls());
    }
}

/*
Questions:
1. How do I use the handler in the invariant test?
2. Should the handler be test?
3. Can I actually use the sumBalances or just in every transfer?
4. How do I check it with multiple addresses?
5. Approval checks pending (I know)
*/

// contract ERC20Handler is Test {
//     uint8 public decimals = 18;
//     string public name = "ERCHandler";
//     string public symbol = "EH";

//     // mapping(address => uint256) _balanceOf;
//     uint256 public sumBalances;

//     uint256 public constant INITIAL_SUPPLY = 1_000_000;

//     ERC20 token;
//     constructor() {
//         token = new ERC20(name, symbol, decimals, INITIAL_SUPPLY);
//         // _mint(msg.sender, INITIAL_SUPPLY * 10 ** decimals);
//         sumBalances = INITIAL_SUPPLY;
//         // _balanceOf[msg.sender] = INITIAL_SUPPLY;
//     }

//     function approve(address spender, uint256 value) public returns (bool) {
//         return token.approve(spender, value);
//     }

//     function transfer(address to, uint256 value) public returns (bool) {
//         uint256 sumBalancesBefore = token.balanceOf(msg.sender) +
//             token.balanceOf(to);
//         uint256 totalSupplyBefore = token.totalSupply();
//         bool ok = token.transfer(to, value);
//         assertEq(
//             token.balanceOf(msg.sender) + token.balanceOf(to),
//             sumBalancesBefore
//         );
//     }

//     function transferFrom(
//         address from,
//         address to,
//         uint256 value
//     ) public returns (bool) {
//         uint256 sumBalancesBefore = token.balanceOf(from) + token.balanceOf(to);
//         uint256 totalSupplyBefore = token.totalSupply();
//         bool ok = token.transferFrom(from, to, value);
//         assertEq(
//             token.balanceOf(from) + token.balanceOf(to),
//             sumBalancesBefore
//         );
//     }
// }
