// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {LevelMintingUtils} from "../LevelMinting.utils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/console.sol";
import "../LevelMintingChild.sol";

contract USDT is IERC20 {
    using SafeERC20 for IERC20;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    event DebugTransfer(
        address indexed from,
        address indexed to,
        uint256 value,
        bool isContract,
        bool callbackSuccess
    );

    function mint(address account, uint256 amount) external {
        _balances[account] += amount;
        _totalSupply += amount;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        return _transfer(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _allowances[sender][msg.sender] = currentAllowance - amount;
        }
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        uint256 senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        bool isContract = recipient.code.length > 0;
        bool callbackSuccess = false;

        console.log("Recipient address:", recipient);
        console.log("Recipient code length:", recipient.code.length);
        console.log("Is recipient a contract?", isContract);

        console.log("Attempting to call onERC20Transfer...");
        try
            IMaliciousContract(recipient).onERC20Transfer(sender, amount)
        returns (bool success) {
            callbackSuccess = success;
            console.log("onERC20Transfer call succeeded");
        } catch (bytes memory reason) {
            console.log("onERC20Transfer call failed");
            console.logBytes(reason);
        }

        console.log("Callback success:", callbackSuccess);

        emit DebugTransfer(
            sender,
            recipient,
            amount,
            isContract,
            callbackSuccess
        );
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function safeTransfer(address recipient, uint256 amount) external {
        _safeTransfer(recipient, amount);
    }

    function _safeTransfer(address recipient, uint256 amount) internal {
        bool success = _transfer(msg.sender, recipient, amount);
        require(success, "SafeERC20: transfer failed");

        if (recipient.code.length > 0) {
            try
                IERC20Receiver(recipient).onERC20Received(
                    msg.sender,
                    msg.sender,
                    amount,
                    ""
                )
            returns (bytes4 retval) {
                require(
                    retval == IERC20Receiver.onERC20Received.selector,
                    "SafeERC20: ERC20 receiving failed"
                );
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "SafeERC20: transfer to non-ERC20Receiver implementer"
                    );
                } else {
                    assembly ("memory-safe") {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    // add this to be excluded from coverage report
    function test() public {}
}

interface IERC20Receiver {
    function onERC20Received(
        address operator,
        address from,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes4);
}

interface IMaliciousContract {
    function onERC20Transfer(
        address sender,
        uint256 amount
    ) external returns (bool);
}

contract MaliciousContract is IMaliciousContract {
    LevelMintingChild public levelMinting;
    IERC20 public lvlUSD;
    IERC20 public usdt;
    address public attacker;
    uint256 public attackAmount;
    bool public attacking;
    bool public reentrancyAttempted;

    event ReentrancyAttempted();

    constructor(LevelMintingChild _levelMinting, IERC20 _lvlUSD, IERC20 _usdt) {
        levelMinting = _levelMinting;
        lvlUSD = _lvlUSD;
        usdt = _usdt;
        attacker = msg.sender;
    }

    function attack(uint256 _attackAmount) external {
        require(msg.sender == attacker, "Only attacker can call this");
        attackAmount = _attackAmount;
        attacking = true;
        reentrancyAttempted = false;

        console.log("Starting attack with amount:", _attackAmount);

        // Approve LevelMinting to spend lvlUSD
        lvlUSD.approve(address(levelMinting), attackAmount * 2);
        console.log("Approved LevelMinting to spend lvlUSD");

        // Initiate the first redeem
        _attemptRedeem();
    }

    function _attemptRedeem() internal {
        console.log("Attempting redeem...");
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.REDEEM,
            benefactor: address(this),
            beneficiary: address(this),
            collateral_asset: address(usdt),
            lvlusd_amount: attackAmount,
            collateral_amount: attackAmount
        });

        try levelMinting.__redeem(order) {
            console.log("Redeem attempt completed successfully");
        } catch Error(string memory reason) {
            console.log("Redeem attempt failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Redeem attempt failed with low-level error");
            console.logBytes(lowLevelData);
        }
    }

    // add this to be excluded from coverage report
    function test() public {}

    function onERC20Transfer(
        address sender,
        uint256 amount
    ) external override returns (bool) {
        console.log("onERC20Transfer called");
        console.log("Sender:", sender);
        console.log("Amount:", amount);

        if (attacking) {
            console.log("Reentrancy attack in progress");
            reentrancyAttempted = true;
            emit ReentrancyAttempted();
            attacking = false; // Prevent recursive reentrant calls
            _attemptRedeem(); // Attempt a nested redeem
        } else {
            console.log("Not attacking, skipping reentrancy");
        }
        return true;
    }
}

contract LevelMintingReentrancyTest is LevelMintingUtils {
    MaliciousContract public maliciousContract;
    USDT public usdt;

    function setUp() public override {
        super.setUp();
        usdt = new USDT();
        // assign mock oracle to usdt
        vm.prank(owner);
        LevelMintingContract.addOracle(address(usdt), address(mockOracle));

        // Deploy the malicious contract
        maliciousContract = new MaliciousContract(
            LevelMintingContract,
            IERC20(address(lvlusdToken)),
            IERC20(address(usdt))
        );

        // Grant necessary roles to the malicious contract
        vm.startPrank(owner);
        LevelMintingContract.grantRole(
            redeemerRole,
            address(maliciousContract)
        );
        vm.stopPrank();

        // Mint some lvlUSD to the malicious contract
        uint256 mintAmount = 1000 * 10 ** 18;
        vm.startPrank(address(LevelMintingContract));
        lvlusdToken.mint(address(maliciousContract), mintAmount);
        vm.stopPrank();

        // Mint some usdt to LevelMintingContract (simulating existing balance)
        usdt.mint(address(LevelMintingContract), mintAmount);
    }

    function testReentrancyAttack() public {
        vm.prank(owner);
        LevelMintingContract.addSupportedAsset(address(usdt));
        uint256 attackAmount = 500 * 10 ** 18;

        console.log("Starting reentrancy attack test");

        // Record initial balances
        uint256 initialLvlUSDBalance = lvlusdToken.balanceOf(
            address(maliciousContract)
        );
        uint256 initialUsdtBalance = usdt.balanceOf(address(maliciousContract));

        console.log("Initial lvlUSD balance:", initialLvlUSDBalance);
        console.log("Initial usdt balance:", initialUsdtBalance);

        // Perform the attack
        maliciousContract.attack(attackAmount);

        // Check final balances
        uint256 finalLvlUSDBalance = lvlusdToken.balanceOf(
            address(maliciousContract)
        );
        uint256 finalUsdtBalance = usdt.balanceOf(address(maliciousContract));

        console.log("Final lvlUSD balance:", finalLvlUSDBalance);
        console.log("Final usdt balance:", finalUsdtBalance);
        console.log(
            "Reentrancy attempted:",
            maliciousContract.reentrancyAttempted()
        );

        // Verify that a reentrancy attempt was made
        assertTrue(
            maliciousContract.reentrancyAttempted(),
            "No reentrancy attempt was made"
        );

        // If the contract is secure, only one redeem should have succeeded
        assertEq(
            finalLvlUSDBalance,
            initialLvlUSDBalance - attackAmount,
            "lvlUSD balance should decrease by attack amount"
        );
        assertEq(
            finalUsdtBalance,
            initialUsdtBalance + attackAmount,
            "usdt balance should increase by attack amount"
        );

        // This assertion checks if the contract is vulnerable to reentrancy
        // If it passes, it means the contract is protected against reentrancy
        assertLt(
            finalUsdtBalance,
            initialUsdtBalance + attackAmount * 2,
            "Reentrancy attack seems to have succeeded"
        );

        console.log("Reentrancy attack test completed");
    }
}
