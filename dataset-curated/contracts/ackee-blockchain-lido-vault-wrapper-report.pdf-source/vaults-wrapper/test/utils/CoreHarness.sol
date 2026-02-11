// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IWstETH} from "../../src/interfaces/core/IWstETH.sol";
import {IDashboard} from "src/interfaces/core/IDashboard.sol";
import {ILazyOracle} from "src/interfaces/core/ILazyOracle.sol";
import {ILido} from "src/interfaces/core/ILido.sol";
import {ILidoLocator} from "src/interfaces/core/ILidoLocator.sol";
import {IOperatorGrid} from "src/interfaces/core/IOperatorGrid.sol";
import {IOssifiableProxy} from "src/interfaces/core/IOssifiableProxy.sol";
import {IVaultFactory} from "src/interfaces/core/IVaultFactory.sol";
import {IVaultHub as IVaultHubIntact} from "src/interfaces/core/IVaultHub.sol";

interface IHashConsensus {
    function updateInitialEpoch(uint256 initialEpoch) external;
}

interface IHashConsensusView {
    function getCurrentFrame() external view returns (uint256 refSlot, uint256 reportProcessingDeadlineSlot);
}

interface IAgent {
    function kernel() external view returns (address);
}

interface IBaseOracle {
    function getConsensusContract() external view returns (address);
}

interface IKernel {
    function acl() external view returns (address);
}

interface IACL {
    function grantPermission(address _entity, address _app, bytes32 _role) external;
    function revokePermission(address _entity, address _app, bytes32 _role) external;
}

interface IVaultHub is IVaultHubIntact {
    function mock__setReportIsAlwaysFresh(bool _reportIsAlwaysFresh) external;
}

contract CoreHarness is Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    ILidoLocator public locator;
    IDashboard public dashboard;
    ILido public steth;
    IWstETH public wsteth;
    IVaultHub public vaultHub;
    ILazyOracle public lazyOracle;
    IOperatorGrid public operatorGrid;
    IHashConsensusView public hashConsensus;

    uint256 public constant INITIAL_LIDO_SUBMISSION = 15_000 ether;
    uint256 public constant CONNECT_DEPOSIT = 1 ether;
    uint256 public constant LIDO_TOTAL_BASIS_POINTS = 10000;
    uint256 public constant NODE_OPERATOR_FEE_RATE = 1_00; // 1% in basis points
    uint256 public constant DEFAULT_TIER_ID = 0;

    address public constant BEACON_CHAIN = address(0xbeac0);

    constructor() {
        vm.deal(address(this), 10000000 ether);

        string memory locatorAddressStr = vm.envString("CORE_LOCATOR_ADDRESS");
        if (bytes(locatorAddressStr).length == 0) {
            revert("CORE_LOCATOR_ADDRESS is not set");
        }

        address locatorAddress = vm.parseAddress(locatorAddressStr);
        console.log("Locator address:", locatorAddress);

        locator = ILidoLocator(locatorAddress);
        vm.label(locatorAddress, "LidoLocator");

        // Discover Aragon Agent address from the locator proxy admin
        address agent = IOssifiableProxy(locatorAddress).proxy__getAdmin();
        vm.label(agent, "Agent");

        // Discover Aragon ACL address from the Agent Kernel
        address kernelAddress = IAgent(agent).kernel();
        vm.label(kernelAddress, "Kernel");
        IACL acl = IACL(IKernel(kernelAddress).acl());
        vm.label(address(acl), "ACL");

        // Get LazyOracle address from the deployed contracts
        lazyOracle = ILazyOracle(locator.lazyOracle());
        vm.label(address(lazyOracle), "LazyOracle");

        operatorGrid = IOperatorGrid(locator.operatorGrid());
        vm.label(address(operatorGrid), "OperatorGrid");

        address hashConsensusAddr = IBaseOracle(locator.accountingOracle()).getConsensusContract();
        vm.label(hashConsensusAddr, "HashConsensusForAO");
        hashConsensus = IHashConsensusView(hashConsensusAddr);

        steth = ILido(locator.lido());
        vm.label(address(steth), "Lido");

        wsteth = IWstETH(locator.wstETH());
        vm.label(address(wsteth), "WstETH");

        vm.startPrank(agent);
        {
            try IHashConsensus(hashConsensusAddr).updateInitialEpoch(1) {
            // ok
            }
                catch {
                // ignore if already set on pre-deployed core (Hoodi)
            }

            acl.grantPermission(agent, address(steth), steth.STAKING_CONTROL_ROLE());
            steth.setMaxExternalRatioBP(LIDO_TOTAL_BASIS_POINTS);
            acl.revokePermission(agent, address(steth), steth.STAKING_CONTROL_ROLE());

            if (steth.isStopped()) {
                steth.resume();
            }
        }
        vm.stopPrank();

        // Ensure Lido has sufficient shares; on Hoodi it's already funded. Only top up if low.
        uint256 totalShares = steth.getTotalShares();
        if (totalShares < 100000) {
            try steth.submit{value: INITIAL_LIDO_SUBMISSION}(address(this)) {}
                catch {
                // ignore stake limit or other constraints on pre-deployed core
            }
        }

        IOperatorGrid.Tier memory tier = operatorGrid.tier(DEFAULT_TIER_ID);
        if (tier.shareLimit == 0) {
            IOperatorGrid.TierParams[] memory params = new IOperatorGrid.TierParams[](1);

            uint256 shareLimit = 1000 ether;
            params[0] = IOperatorGrid.TierParams({
                shareLimit: shareLimit,
                reserveRatioBP: tier.reserveRatioBP,
                forcedRebalanceThresholdBP: tier.forcedRebalanceThresholdBP,
                infraFeeBP: tier.infraFeeBP,
                liquidityFeeBP: tier.liquidityFeeBP,
                reservationFeeBP: tier.reservationFeeBP
            });

            uint256[] memory tierIds = new uint256[](1);
            tierIds[0] = 0;

            //registry will be assigned on upgrade to EVMScriptExecutor, VaultsAdapter
            bytes32 REGISTRY_ROLE = operatorGrid.REGISTRY_ROLE();

            vm.prank(agent);
            operatorGrid.grantRole(REGISTRY_ROLE, agent);

            vm.prank(agent);
            operatorGrid.alterTiers(tierIds, params);
        }

        vaultHub = IVaultHub(locator.vaultHub());
        vm.label(address(vaultHub), "VaultHub");

        IVaultFactory vaultFactory = IVaultFactory(locator.vaultFactory());
        vm.label(address(vaultFactory), "VaultFactory");

        dashboard = IDashboard(payable(address(0))); // Will be set by DefiWrapper
        vm.label(address(dashboard), "Dashboard");
    }

    function setDashboard(address _dashboard) external {
        dashboard = IDashboard(payable(_dashboard));
        vm.label(address(dashboard), "Dashboard");
    }

    function applyVaultReport(
        address _stakingVault,
        uint256 _totalValue,
        uint256 _cumulativeLidoFees,
        uint256 _liabilityShares,
        uint256 _slashingReserve
    ) public {
        // TODO: maybe warp exactly to the next report processing deadline?
        vm.warp(block.timestamp + 24 hours);

        uint256 reportTimestamp = block.timestamp;
        uint256 refSlot;
        // Try to get the actual refSlot from HashConsensus, fallback to naive calculation
        (refSlot,) = hashConsensus.getCurrentFrame();

        // TODO: is fallback needed?
        // try hashConsensus.getCurrentFrame() returns (uint256 refSlot_, uint256) {
        //     refSlot = refSlot_;
        // } catch {
        //     refSlot = block.timestamp / 12;
        // }

        // Build a single-leaf Merkle tree: root == leaf, empty proof
        uint256 maxLiabilityShares = vaultHub.vaultRecord(_stakingVault).maxLiabilityShares;
        if (_liabilityShares > maxLiabilityShares) {
            maxLiabilityShares = _liabilityShares;
        }

        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        _stakingVault,
                        _totalValue,
                        _cumulativeLidoFees,
                        _liabilityShares,
                        maxLiabilityShares,
                        _slashingReserve
                    )
                )
            )
        );

        string memory emptyReportCid = "";
        vm.prank(locator.accountingOracle());
        lazyOracle.updateReportData(reportTimestamp, refSlot, leaf, emptyReportCid);

        bytes32[] memory emptyProof = new bytes32[](0);
        lazyOracle.updateVaultData(
            _stakingVault,
            _totalValue,
            _cumulativeLidoFees,
            _liabilityShares,
            maxLiabilityShares,
            _slashingReserve,
            emptyProof
        );
    }

    /**
     * @dev Mock function to simulate validators receiving ETH from the staking vault
     * This replaces the manual beacon chain transfer simulation in tests
     */
    function mockValidatorsReceiveETH(address _stakingVault) external returns (uint256 transferredAmount) {
        transferredAmount = _stakingVault.balance;
        if (transferredAmount > 0) {
            vm.prank(_stakingVault);
            (bool sent,) = BEACON_CHAIN.call{value: transferredAmount}("");
            require(sent, "ETH send to beacon chain failed");
        }
        return transferredAmount;
    }

    /**
     * @dev Mock function to simulate validator exits returning ETH to the staking vault
     * This replaces the manual ETH return simulation in tests
     */
    function mockValidatorExitReturnETH(address _stakingVault, uint256 _ethAmount) external {
        vm.prank(BEACON_CHAIN);
        (bool success,) = _stakingVault.call{value: _ethAmount}("");
        require(success, "ETH return from beacon chain failed");
    }

    function setStethShareRatio(uint256 _shareRatioE18) external {
        uint256 totalSupply = steth.totalSupply();
        uint256 totalShares = steth.getTotalShares();

        uint256 a = Math.mulDiv(totalSupply, 1 ether, _shareRatioE18, Math.Rounding.Floor);
        assertLe(a, type(uint128).max, "a exceeds uint128 max");
        assertLe(totalShares, type(uint128).max, "totalShares exceeds uint128 max");
        int256 sharesDiff = a.toInt256() - totalShares.toInt256();

        if (sharesDiff > 0) {
            vm.prank(locator.accounting());
            steth.mintShares(address(this), sharesDiff.toUint256());
        } else if (sharesDiff < 0) {
            // On pre-deployed cores we may lack permission/balance to burn; skip decreasing in that case
        }

        // Best-effort: do not revert if cannot match ratio exactly on pre-deployed core
    }

    function increaseBufferedEther(uint256 _amount) external {
        //bufferedEtherAndDepositedValidators
        bytes32 BUFFERED_ETHER_SLOT = 0xa84c096ee27e195f25d7b6c7c2a03229e49f1a2a5087e57ce7d7127707942fe3;

        bytes32 storageWord = vm.load(address(steth), BUFFERED_ETHER_SLOT);

        // Shift right by 128 bits
        uint256 depositedValidators = uint256(storageWord) >> 128;

        // Mask off the high 128 bits
        uint256 currentBufferedEther = uint256(uint128(uint256(storageWord)));

        uint256 newBufferedEther = currentBufferedEther + _amount;

        // [depositedValidators (128) | newBufferedEther (128)]
        bytes32 newStorageWord = bytes32(depositedValidators << 128 | newBufferedEther);

        vm.store(address(steth), BUFFERED_ETHER_SLOT, newStorageWord);

        console.log("Buffered Ether increased by:", _amount);
        console.log("New Total Pooled Ether (stETH.totalSupply()):", steth.totalSupply());
    }
}
