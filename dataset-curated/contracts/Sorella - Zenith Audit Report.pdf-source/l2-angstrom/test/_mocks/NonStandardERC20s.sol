// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @author philogy <https://github.com/philogy>
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 allowed) public {
        allowance[msg.sender][spender] = allowed;
    }

    function transfer(address to, uint256 amount) public {
        require(amount <= balanceOf[msg.sender]);
        unchecked {
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount;
        }
    }

    function transferFrom(address from, address to, uint256 amount) public {
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount);
            unchecked {
                allowance[from][msg.sender] -= amount;
            }
        }
        require(amount <= balanceOf[from]);
        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
    }
}

/// @author philogy <https://github.com/philogy>
contract RevertsTrueToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 allowed) public returns (bool) {
        allowance[msg.sender][spender] = allowed;
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _require(amount <= balanceOf[msg.sender]);
        unchecked {
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            _require(amount <= allowance[from][msg.sender]);
            unchecked {
                allowance[from][msg.sender] -= amount;
            }
        }
        _require(amount <= balanceOf[from]);
        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
        return true;
    }

    function _require(bool cond) internal pure virtual {
        if (!cond) {
            assembly ("memory-safe") {
                mstore(0x00, true)
                revert(0x00, 0x20)
            }
        }
    }
}

/// @author philogy <https://github.com/philogy>
contract ReturnStatusToken is RevertsTrueToken {
    function _require(bool cond) internal pure override {
        if (!cond) {
            assembly ("memory-safe") {
                mstore(0x00, false)
                return(0x00, 0x20)
            }
        }
    }
}

/// @author philogy <https://github.com/philogy>
contract RevertsEmptyToken is RevertsTrueToken {
    function _require(bool cond) internal pure override {
        require(cond);
    }
}
