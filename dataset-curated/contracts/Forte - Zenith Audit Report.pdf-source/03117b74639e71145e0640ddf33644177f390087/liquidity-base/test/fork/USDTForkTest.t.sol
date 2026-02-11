/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ForkTestBase, GenericERC20FixedSupply, GenericERC20} from "test/fork/ForkTestBase.t.sol";

// Interface for interacting with USDT
interface IUSDT {
    function owner() external returns (address);
    function issue(uint amount) external;
    function transfer(address _to, uint _value) external;
    function transferFrom(address from, address to, uint value) external;
    function approve(address _spender, uint _value) external;
    function allowance(address _owner, address _spender) external returns (uint remaining);
    function balanceOf(address _owner) external returns (uint balance);
}

/**
 * @title USDT Fork Testing
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
abstract contract USDTForkTest is ForkTestBase {
    IUSDT _usdt;
    bool ethMainnet;

    function _setUp(address usdtAddress, string memory key) internal {
        _usdt = IUSDT(usdtAddress);
        uint256 fork = vm.createFork(vm.envString(key));
        vm.selectFork(fork);
        // Checking whether its Ethereum mainnet or Polygon as they have differeing USDT contracts deployed
        if (usdtAddress == address(0xdAC17F958D2ee523a2206206994597C13D831ec7)) ethMainnet = true;
        if (ethMainnet) {
            vm.startPrank(_usdt.owner());
            _usdt.issue(1e12 * STABLECOIN_DEC);
            _usdt.transfer(address(this), 1e12 * STABLECOIN_DEC);
        } else {
            // At this block number it is guaranteed that the addresses used have the needed amount of USDT
            vm.rollFork(57571223);
            vm.startPrank(address(0xF977814e90dA44bFA03b6295A0616a897441aceC));
            _usdt.transfer(address(this), _usdt.balanceOf(address(0xF977814e90dA44bFA03b6295A0616a897441aceC)));
        }

        admin = address(this);
        yToken = GenericERC20(address(_usdt));
        pool = _setupPoolForkTest(address(this), address(_usdt), 0, true);
        _usdt.approve(address(this), 1e9 * STABLECOIN_DEC);
        _usdt.approve(address(pool), 1e9 * STABLECOIN_DEC);
        _yToken = IERC20(pool.yToken());
        xToken = GenericERC20FixedSupply(address(pool.xToken()));
        withStableCoin = true;
    }

    function testMoreThanApprovedForUSDT() public startAsAdmin {
        IUSDT(address(_yToken)).approve(address(this), 0);
        IUSDT(address(_yToken)).approve(address(pool), 0);
        IUSDT(address(_yToken)).approve(address(this), STABLECOIN_DEC);
        IUSDT(address(_yToken)).approve(address(pool), STABLECOIN_DEC);

        vm.startPrank(admin);
        _yToken.balanceOf(address(admin));

        (uint expected, , ) = pool.simSwap(address(_yToken), STABLECOIN_DEC + 1);
        if (ethMainnet) {
            vm.expectRevert();
        } else {
            vm.expectRevert("ERC20: transfer amount exceeds allowance");
        }

        pool.swap(address(_yToken), STABLECOIN_DEC + 1, expected);
    }

    function testNotEnoughCollateralUSDT() public startAsAdmin {
        if (ethMainnet) vm.startPrank(_usdt.owner());
        IUSDT(address(_yToken)).approve(address(this), 1e14 * STABLECOIN_DEC);
        IUSDT(address(_yToken)).approve(address(pool), 1e14 * STABLECOIN_DEC);
        vm.startPrank(admin);
        uint balance = _yToken.balanceOf(address(admin));

        IUSDT(address(_yToken)).transfer(address(alice), balance - 1);
        (uint expected, , ) = pool.simSwap(address(_yToken), 1e3 * STABLECOIN_DEC);

        if (ethMainnet) {
            vm.expectRevert();
        } else {
            vm.expectRevert("ERC20: transfer amount exceeds balance");
        }

        pool.swap(address(_yToken), 1e3 * STABLECOIN_DEC, expected);
    }
}
