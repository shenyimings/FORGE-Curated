// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {LayoutV1} from "./LayoutV1.sol";
import {LayoutV2} from "./LayoutV2.sol";

contract LayoutTest is Test {
    address owner = vm.addr(0x1);
    address proxy;

    function setUp() public {
        proxy = Upgrades.deployTransparentProxy(
            "LayoutV1.sol",
            owner,
            abi.encodeCall(LayoutV1.initialize, ())
        );
    }

    function test_Upgrade() public {
        LayoutV1(proxy).setAccount(owner, LayoutV1.Account({
            balance: 10
        }));
        vm.startPrank(owner);
        Upgrades.upgradeProxy(proxy, "LayoutV2.sol", new bytes(0));
        vm.stopPrank();
        (uint balance, string memory name, uint points) = LayoutV2(proxy).accounts(owner);
        assertEq(balance, 10);
        assertEq(name, "");
        assertEq(points, 0);
        LayoutV2(proxy).setAccount(owner, LayoutV2.Account({
            balance: 100,
            name: "john",
            points: 10
        }));
        (balance, name, points) = LayoutV2(proxy).accounts(owner);
        assertEq(balance, 100);
        assertEq(name, "john");
        assertEq(points, 10);
    }
}