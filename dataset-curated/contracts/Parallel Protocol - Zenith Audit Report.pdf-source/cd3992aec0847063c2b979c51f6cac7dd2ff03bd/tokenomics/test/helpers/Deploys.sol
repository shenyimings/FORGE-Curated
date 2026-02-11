// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from "@forge-std/Test.sol";

import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import { AccessManager, IAccessManaged } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MainFeeDistributor } from "contracts/fees/MainFeeDistributor.sol";
import { SideChainFeeCollector } from "contracts/fees/SideChainFeeCollector.sol";
import { FeeCollectorCore } from "contracts/fees/FeeCollectorCore.sol";

import { sPRL1 } from "contracts/sPRL/sPRL1.sol";
import { sPRL2 } from "contracts/sPRL/sPRL2.sol";

import { RewardMerkleDistributor } from "contracts/rewardMerkleDistributor/RewardMerkleDistributor.sol";

import { IBalancerV3Router } from "contracts/interfaces/IBalancerV3Router.sol";
import { IWrappedNative } from "contracts/interfaces/IWrappedNative.sol";
import {
    IAuraBoosterLite,
    IAuraRewardPool,
    IVirtualBalanceRewardPool,
    IAuraStashToken
} from "contracts/interfaces/IAura.sol";

import { TimeLockPenaltyERC20Mock } from "test/mocks/TimeLockPenaltyERC20Mock.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";
import { WrappedNativeMock } from "test/mocks/WrapperNativeMock.sol";
import { ReenteringMockToken } from "test/mocks/ReenteringMockToken.sol";
import { BridgeableTokenMock } from "test/mocks/BridgeableTokenMock.sol";
import {
    AuraBoosterLiteMock,
    AuraRewardPoolMock,
    VirtualBalanceRewardPoolMock,
    AuraStashTokenMock
} from "test/mocks/AuraMock.sol";
import { BalancerV3RouterMock } from "test/mocks/BalancerV3RouterMock.sol";

import { SigUtils } from "./SigUtils.sol";

abstract contract Deploys is Test {
    SigUtils internal sigUtils;

    ERC20Mock internal par;
    ERC20Mock internal prl;
    ERC20Mock internal paUSD;

    ERC20Mock internal bpt;
    ERC20Mock internal auraBpt;
    ERC20Mock internal extraRewardToken;
    ERC20Mock internal rewardToken;

    WrappedNativeMock internal weth;

    BridgeableTokenMock internal bridgeableTokenMock;
    ReenteringMockToken internal reenterToken;
    BalancerV3RouterMock internal balancerV3RouterMock;

    AuraBoosterLiteMock internal auraBoosterLiteMock;
    AuraRewardPoolMock internal auraRewardPoolMock;
    VirtualBalanceRewardPoolMock internal virtualBalanceRewardPoolMock;
    AuraStashTokenMock internal auraStashTokenMock;

    RewardMerkleDistributor internal rewardMerkleDistributor;

    MainFeeDistributor internal mainFeeDistributor;
    SideChainFeeCollector internal sideChainFeeCollector;
    AccessManager internal accessManager;

    sPRL2 internal sprl2;
    sPRL1 internal sprl1;
    TimeLockPenaltyERC20Mock internal timeLockPenaltyERC20;

    function _deployAccessManager(address _initialAdmin) internal returns (AccessManager) {
        AccessManager _accessManager = new AccessManager(_initialAdmin);
        vm.label({ account: address(_accessManager), newLabel: "AccessManager" });
        return _accessManager;
    }

    function _deployBridgeableTokenMock(address _principalToken) internal returns (BridgeableTokenMock) {
        BridgeableTokenMock _bridgeableTokenMock =
            new BridgeableTokenMock(_principalToken, "BridgeableTokenMock", "BTM");
        vm.label({ account: address(_bridgeableTokenMock), newLabel: "BridgeableTokenMock" });
        return _bridgeableTokenMock;
    }

    function _deployERC20Mock(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        internal
        returns (ERC20Mock)
    {
        ERC20Mock _erc20 = new ERC20Mock(_name, _symbol, _decimals);
        vm.label({ account: address(_erc20), newLabel: _name });
        return _erc20;
    }

    function _deployWrappedNativeMock() internal returns (WrappedNativeMock) {
        WrappedNativeMock _wrappedNative = new WrappedNativeMock("Wrapped Native", "WNative", 18);
        vm.label({ account: address(_wrappedNative), newLabel: "WNative" });
        return _wrappedNative;
    }

    function _deployTimeLockPenaltyERC20(
        address _underlying,
        address _feeReceiver,
        address _accessManager,
        uint256 _penaltyPercentage,
        uint64 _timeLockDuration
    )
        internal
        returns (TimeLockPenaltyERC20Mock)
    {
        TimeLockPenaltyERC20Mock _timeLockPenaltyERC20 = new TimeLockPenaltyERC20Mock(
            "TimeLockPenaltyERC20",
            "TLPERC20",
            _underlying,
            _feeReceiver,
            _accessManager,
            _penaltyPercentage,
            _timeLockDuration
        );
        vm.label({ account: address(_timeLockPenaltyERC20), newLabel: "TimeLockPenaltyERC20" });
        return _timeLockPenaltyERC20;
    }

    function _deploySPRL1(
        address _underlying,
        address _feeReceiver,
        address _accessManager,
        uint256 _startPenaltyPercentage,
        uint64 _timeLockDuration
    )
        internal
        returns (sPRL1)
    {
        sPRL1 _sPRL1 = new sPRL1(_underlying, _feeReceiver, _accessManager, _startPenaltyPercentage, _timeLockDuration);
        vm.label({ account: address(_sPRL1), newLabel: "sPRL1" });
        return _sPRL1;
    }

    function _deploySPRL2(
        address _auraBpt,
        address _feeReceiver,
        address _accessManager,
        uint256 _startPenaltyPercentage,
        uint64 _timeLockDuration,
        IBalancerV3Router _balancerRouter,
        IAuraBoosterLite _auraBoosterLite,
        IAuraRewardPool _auraVault,
        IERC20 _balancerBPT,
        IERC20 _prl,
        IWrappedNative _weth
    )
        internal
        returns (sPRL2)
    {
        sPRL2 _sPRL2 = new sPRL2(
            _auraBpt,
            _feeReceiver,
            _accessManager,
            _startPenaltyPercentage,
            _timeLockDuration,
            _balancerRouter,
            _auraBoosterLite,
            _auraVault,
            _balancerBPT,
            _prl,
            _weth
        );
        vm.label({ account: address(_sPRL2), newLabel: "sPRL2" });
        return _sPRL2;
    }

    function _deployRewardMerkleDistributor(
        address _accessManager,
        address _token,
        address _expiredRewardsRecipient
    )
        internal
        returns (RewardMerkleDistributor)
    {
        RewardMerkleDistributor _rewardMerkleDistributor =
            new RewardMerkleDistributor(_accessManager, _token, _expiredRewardsRecipient);
        vm.label({ account: address(_rewardMerkleDistributor), newLabel: "RewardMerkleDistributor" });
        return _rewardMerkleDistributor;
    }

    function _deployBridgeableTokenMock(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        internal
        returns (ERC20Mock)
    {
        ERC20Mock _erc20 = new ERC20Mock(_name, _symbol, _decimals);
        vm.label({ account: address(_erc20), newLabel: _name });
        return _erc20;
    }

    function _deployMainFeeDistributor(
        address _accessManager,
        address _bridgeableToken,
        address _feeToken
    )
        internal
        returns (MainFeeDistributor)
    {
        MainFeeDistributor _mainFeeDistributor = new MainFeeDistributor(_accessManager, _bridgeableToken, _feeToken);
        vm.label({ account: address(_mainFeeDistributor), newLabel: "MainFeeDistributor" });
        return _mainFeeDistributor;
    }

    function _deploySideChainFeeCollector(
        address _accessManager,
        uint32 _lzEidReceiver,
        address _bridgeableToken,
        address _destinationReceiver,
        address _feeToken
    )
        internal
        returns (SideChainFeeCollector)
    {
        SideChainFeeCollector _sideChainSideChainFeeCollector = new SideChainFeeCollector(
            _accessManager, _lzEidReceiver, _bridgeableToken, _destinationReceiver, _feeToken
        );
        vm.label({ account: address(_sideChainSideChainFeeCollector), newLabel: "SideChainFeeCollector" });
        return _sideChainSideChainFeeCollector;
    }

    function _deployBalancerAndAuraMock(
        address[2] memory _tokens,
        address _bpt,
        address _auraBpt,
        address _rewardToken,
        address _extraReward
    )
        internal
    {
        balancerV3RouterMock = new BalancerV3RouterMock(_tokens, _bpt);
        vm.label({ account: address(balancerV3RouterMock), newLabel: "BalancerV3RouterMock" });

        auraStashTokenMock = new AuraStashTokenMock(_extraReward);
        vm.label({ account: address(auraStashTokenMock), newLabel: "AuraStashTokenMock" });

        virtualBalanceRewardPoolMock = new VirtualBalanceRewardPoolMock(address(auraStashTokenMock));
        vm.label({ account: address(virtualBalanceRewardPoolMock), newLabel: "VirtualBalanceRewardPoolMock" });

        auraBoosterLiteMock = new AuraBoosterLiteMock(_bpt, _auraBpt);
        vm.label({ account: address(auraBoosterLiteMock), newLabel: "AuraBoosterLiteMock" });

        address[] memory _extraRewards = new address[](1);
        _extraRewards[0] = address(virtualBalanceRewardPoolMock);
        auraRewardPoolMock = new AuraRewardPoolMock(_rewardToken, _extraRewards, address(auraBoosterLiteMock));
        vm.label({ account: address(auraRewardPoolMock), newLabel: "AuraRewardPoolMock" });
    }
}
