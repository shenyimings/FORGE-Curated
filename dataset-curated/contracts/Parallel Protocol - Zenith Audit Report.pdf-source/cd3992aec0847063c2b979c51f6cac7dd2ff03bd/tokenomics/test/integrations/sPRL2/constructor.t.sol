// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Base.t.sol";

contract SPRL2_Constructor_Integrations_Test is Base_Test {
    function test_SPRL2_Constructor() external {
        sprl2 = new sPRL2(
            address(auraBpt),
            users.daoTreasury.addr,
            address(accessManager),
            DEFAULT_PENALTY_PERCENTAGE,
            DEFAULT_TIME_LOCK_DURATION,
            IBalancerV3Router(address(balancerV3RouterMock)),
            IAuraBoosterLite(address(auraBoosterLiteMock)),
            IAuraRewardPool(address(auraRewardPoolMock)),
            IERC20(address(bpt)),
            IERC20(address(prl)),
            IWrappedNative(address(weth))
        );
        assertEq(sprl2.authority(), address(accessManager));
        assertEq(address(sprl2.underlying()), address(auraBpt));
        assertEq(sprl2.timeLockDuration(), DEFAULT_TIME_LOCK_DURATION);
        assertEq(sprl2.startPenaltyPercentage(), DEFAULT_PENALTY_PERCENTAGE);
        assertEq(sprl2.unlockingAmount(), 0);
        assertEq(sprl2.feeReceiver(), users.daoTreasury.addr);
        assertEq(sprl2.name(), "Stake 20WETH-80PRL Aura Deposit Vault");
        assertEq(sprl2.symbol(), "sPRL2");
        assertEq(address(sprl2.BALANCER_ROUTER()), address(balancerV3RouterMock));
        assertEq(address(sprl2.AURA_BOOSTER_LITE()), address(auraBoosterLiteMock));
        assertEq(address(sprl2.AURA_VAULT()), address(auraRewardPoolMock));
        assertEq(address(sprl2.BPT()), address(bpt));
        assertEq(address(sprl2.PRL()), address(prl));
        assertEq(address(sprl2.WETH()), address(weth));
    }
}
