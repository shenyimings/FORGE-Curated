// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { CallType, ERC7579Utils, ExecType, Mode } from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Execution, IERC7579Execution, IERC7579Module } from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import { Test } from "forge-std/Test.sol";

import { Permit3ApproverModule } from "../../src/modules/Permit3ApproverModule.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockSmartAccount is IERC7579Execution {
    mapping(address => bool) public installedModules;

    function installModule(uint256, address module, bytes calldata data) external {
        installedModules[module] = true;
        IERC7579Module(module).onInstall(data);
    }

    function uninstallModule(uint256, address module, bytes calldata data) external {
        installedModules[module] = false;
        IERC7579Module(module).onUninstall(data);
    }

    function execute(bytes32, bytes calldata) external payable {
        revert("Not implemented - use executeFromExecutor");
    }

    function executeFromExecutor(
        bytes32 mode,
        bytes calldata executionCalldata
    ) external payable returns (bytes[] memory returnData) {
        require(installedModules[msg.sender], "Module not installed");

        // Decode the mode
        CallType callType = CallType.wrap(bytes1(mode));
        ExecType execType = ExecType.wrap(bytes1(mode << 8));

        // Handle batch execution
        if (callType == ERC7579Utils.CALLTYPE_BATCH) {
            Execution[] memory executions = ERC7579Utils.decodeBatch(executionCalldata);
            returnData = new bytes[](executions.length);

            for (uint256 i = 0; i < executions.length; i++) {
                (bool success, bytes memory result) =
                    executions[i].target.call{ value: executions[i].value }(executions[i].callData);
                if (execType == ERC7579Utils.EXECTYPE_DEFAULT) {
                    require(success, "Execution failed");
                }
                returnData[i] = result;
            }
        } else {
            revert("Unsupported call type");
        }
    }
}

contract Permit3ApproverModuleTest is Test {
    Permit3ApproverModule public module;
    MockSmartAccount public smartAccount;
    MockERC20 public token1;
    MockERC20 public token2;
    address public constant PERMIT3 = address(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    function setUp() public {
        module = new Permit3ApproverModule(PERMIT3);
        smartAccount = new MockSmartAccount();
        token1 = new MockERC20();
        token2 = new MockERC20();
    }

    function testModuleConstants() public view {
        assertEq(module.MODULE_TYPE(), 2);
        assertEq(module.name(), "Permit3ApproverModule");
        assertEq(module.version(), "1.0.0");
        assertEq(module.PERMIT3(), PERMIT3);
    }

    function testModuleType() public view {
        assertTrue(module.isModuleType(2)); // Executor type
        assertFalse(module.isModuleType(1)); // Not validator
        assertFalse(module.isModuleType(3)); // Not hook
        assertFalse(module.isModuleType(4)); // Not fallback
    }

    function testSupportsInterface() public view {
        assertTrue(module.supportsInterface(type(IERC7579Module).interfaceId));
    }

    function testInstallModule() public {
        smartAccount.installModule(2, address(module), "");
        assertTrue(smartAccount.installedModules(address(module)));
    }

    function testUninstallModule() public {
        smartAccount.installModule(2, address(module), "");
        smartAccount.uninstallModule(2, address(module), "");
        assertFalse(smartAccount.installedModules(address(module)));
    }

    function testExecuteApprovals() public {
        // Install module
        smartAccount.installModule(2, address(module), "");

        // Prepare tokens to approve
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        // Get execution data
        bytes memory execData = module.getExecutionData(tokens);

        // Execute through module (which will call executeFromExecutor on the smart account)
        module.execute(address(smartAccount), execData);

        // Check approvals
        assertEq(token1.allowance(address(smartAccount), PERMIT3), type(uint256).max);
        assertEq(token2.allowance(address(smartAccount), PERMIT3), type(uint256).max);
    }

    function testExecuteEncoding() public {
        // Install module
        smartAccount.installModule(2, address(module), "");

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        bytes memory execData = abi.encode(tokens);

        // Test that execute properly encodes and calls executeFromExecutor
        // We'll verify this by checking the execution happens correctly
        module.execute(address(smartAccount), execData);

        // If the encoding was correct, approvals should be set
        assertEq(token1.allowance(address(smartAccount), PERMIT3), type(uint256).max);
        assertEq(token2.allowance(address(smartAccount), PERMIT3), type(uint256).max);
    }

    function testExecuteNoTokens() public {
        smartAccount.installModule(2, address(module), "");

        address[] memory tokens = new address[](0);
        bytes memory execData = abi.encode(tokens);

        vm.expectRevert(Permit3ApproverModule.NoTokensProvided.selector);
        module.execute(address(smartAccount), execData);
    }

    function testExecuteZeroAddressToken() public {
        smartAccount.installModule(2, address(module), "");

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(0);
        bytes memory execData = abi.encode(tokens);

        vm.expectRevert(abi.encodeWithSelector(Permit3ApproverModule.ZeroAddress.selector, "token"));
        module.execute(address(smartAccount), execData);
    }

    function testConstructorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Permit3ApproverModule.ZeroAddress.selector, "permit3"));
        new Permit3ApproverModule(address(0));
    }

    function testGetExecutionData() public view {
        address[] memory tokens = new address[](3);
        tokens[0] = address(0x1);
        tokens[1] = address(0x2);
        tokens[2] = address(0x3);

        bytes memory data = module.getExecutionData(tokens);
        address[] memory decoded = abi.decode(data, (address[]));

        assertEq(decoded.length, 3);
        assertEq(decoded[0], address(0x1));
        assertEq(decoded[1], address(0x2));
        assertEq(decoded[2], address(0x3));
    }
}
