// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ForkTestBase, GenericERC20FixedSupply, GenericERC20} from "test/fork/ForkTestBase.t.sol";

interface IWETH {
    function deposit() external payable;
}

/**
 * @title Wrapped Eth Fork Testing
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
abstract contract WETHForkTest is ForkTestBase {
    IERC20 weth;
    bool ethMainnet;

    function setUp() public virtual {
        _setUp(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), "ETHEREUM_RPC_KEY");
    }

    function _setUp(address wethAddress, string memory key) internal {
        uint256 fork = vm.createFork(vm.envString(key));
        vm.selectFork(fork);

        if (wethAddress == address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)) {
            weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
            ethMainnet = true;
            vm.rollFork(19976520);
            vm.startPrank(address(weth));
            IWETH(address(weth)).deposit{value: 1e6 ether}();
            weth.transfer(address(this), 1e5 * ERC20_DECIMALS);
        } else {
            weth = IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
            vm.startPrank(address(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8));
            weth.transfer(address(this), 1e22);
        }

        admin = address(this);
        yToken = GenericERC20(address(weth));
        pool = _setupPoolForkTest(address(this), address(weth), 0, false);

        weth.approve(address(pool), 1e5 * ERC20_DECIMALS);
        _yToken = IERC20(pool.yToken());
        xToken = GenericERC20FixedSupply(address(pool.xToken()));
        withStableCoin = false;
        wEth = true;
    }

    function testMoreThanApprovedForWETH() public startAsAdmin {
        _yToken.approve(address(this), ERC20_DECIMALS);
        _yToken.approve(address(pool), ERC20_DECIMALS);

        _yToken.balanceOf(address(admin));
        (uint expected, , ) = pool.simSwap(address(_yToken), 1e2 * ERC20_DECIMALS);
        if (ethMainnet) {
            vm.expectRevert();
        } else {
            vm.expectRevert("ERC20: transfer amount exceeds allowance");
        }
        pool.swap(address(_yToken), 1e2 * ERC20_DECIMALS, expected, msg.sender, getValidExpiration());
    }

    function testNotEnoughCollateralWETH() public startAsAdmin {
        _yToken.approve(address(this), 1e7 * ERC20_DECIMALS);
        _yToken.approve(address(pool), 1e7 * ERC20_DECIMALS);

        vm.startPrank(admin);
        uint balance = _yToken.balanceOf(address(admin));
        _yToken.transfer(address(alice), balance - 1);
        (uint expected, , ) = pool.simSwap(address(_yToken), 1e3 * ERC20_DECIMALS);
        if (ethMainnet) {
            vm.expectRevert();
        } else {
            vm.expectRevert("ERC20: transfer amount exceeds balance");
        }
        pool.swap(address(_yToken), 1e6 * ERC20_DECIMALS, expected, msg.sender, getValidExpiration());
    }
}
