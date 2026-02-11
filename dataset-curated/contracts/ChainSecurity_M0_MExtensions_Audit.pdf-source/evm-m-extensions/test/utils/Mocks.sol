// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ISwapFacility } from "../../src/swap/interfaces/ISwapFacility.sol";

contract MockM {
    uint128 public currentIndex;
    uint32 public earnerRate;
    uint128 public latestIndex;
    uint40 public latestUpdateTimestamp;

    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address account => bool isEarning) public isEarning;
    mapping(address => mapping(address => uint256)) public allowance;

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {}

    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) external {}

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        return true;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;

        return true;
    }

    function setBalanceOf(address account, uint256 balance) external {
        balanceOf[account] = balance;
    }

    function setCurrentIndex(uint128 currentIndex_) external {
        currentIndex = currentIndex_;
    }

    function setEarnerRate(uint256 earnerRate_) external {
        earnerRate = uint32(earnerRate_);
    }

    function setLatestIndex(uint128 latestIndex_) external {
        latestIndex = latestIndex_;
    }

    function setLatestUpdateTimestamp(uint256 timestamp) external {
        latestUpdateTimestamp = uint40(timestamp);
    }

    function setIsEarning(address account, bool isEarning_) external {
        isEarning[account] = isEarning_;
    }

    function startEarning() external {
        isEarning[msg.sender] = true;
    }

    function stopEarning(address account) external {
        isEarning[account] = false;
    }
}

contract MockRateOracle {
    uint32 public earnerRate;

    function setEarnerRate(uint32 rate) external {
        earnerRate = rate;
    }
}

contract MockRegistrar {
    bytes32 public constant EARNERS_LIST_NAME = "earners";

    mapping(bytes32 key => bytes32 value) internal _values;

    mapping(bytes32 listName => mapping(address account => bool contains)) public listContains;

    function get(bytes32 key) external view returns (bytes32 value) {
        return _values[key];
    }

    function set(bytes32 key, bytes32 value) external {
        _values[key] = value;
    }

    function setEarner(address account, bool contains) external {
        listContains[EARNERS_LIST_NAME][account] = contains;
    }
}

abstract contract MockERC20 {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
}

contract MockMExtension is MockERC20 {
    MockM public mToken;
    address public swapFacility;

    constructor(address mToken_, address swapFacility_) MockERC20("MockMExtension", "MME", 6) {
        mToken = MockM(mToken_);
        swapFacility = swapFacility_;
    }

    function wrap(address recipient, uint256 amount) external {
        uint256 startingBalance = mToken.balanceOf(address(this));
        mToken.transferFrom(msg.sender, address(this), amount);
        _mint(recipient, uint240(mToken.balanceOf(address(this)) - startingBalance));
    }

    function unwrap(address recipient, uint256 amount) external {
        _burn(ISwapFacility(swapFacility).msgSender(), amount);
        mToken.transfer(swapFacility, amount);
    }
}
