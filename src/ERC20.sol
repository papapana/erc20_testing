// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract ERC20 {
    // solhint-disable-next-line screaming-snake-case-immutable
    uint8 public immutable decimals;
    string public name;
    string public symbol;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        require(spender != address(0), "spender cannot be address 0");
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) public returns (bool) {
        require(to != address(0), "cannot send to address 0");
        require(balanceOf[msg.sender] >= value, "insufficient balance");
        balanceOf[msg.sender] -= value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(from != address(0), "from cannot be address 0");
        require(to != address(0), "to cannot be address 0");
        require(balanceOf[from] >= value, "insufficient balance");
        require(allowance[from][msg.sender] >= value, "insufficient allowance");
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        balanceOf[from] -= value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
        return true;
    }

    function _mint(address to, uint256 value) internal virtual {
        require(to != address(0), "cannot mint to address 0");
        totalSupply += value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal virtual {
        require(from != address(0), "cannot burn from address 0");
        balanceOf[from] -= value;
        unchecked {
            totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }
}
