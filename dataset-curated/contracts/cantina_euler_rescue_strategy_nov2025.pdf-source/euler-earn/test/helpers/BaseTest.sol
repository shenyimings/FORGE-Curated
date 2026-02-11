// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {MathLib, WAD} from "./MathLib.sol";

import "../../src/interfaces/IEulerEarn.sol";

import "../../src/libraries/ConstantsLib.sol";
import {ErrorsLib} from "../../src/libraries/ErrorsLib.sol";
import {EventsLib} from "../../src/libraries/EventsLib.sol";

import {IPerspective} from "../../src/interfaces/IPerspective.sol";
import {PerspectiveMock} from "../mocks/PerspectiveMock.sol";

import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {EVaultMock} from "../mocks/EVaultMock.sol";

import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import {IERC20, ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {
    EVaultTestBase,
    IEVault,
    IRMTestDefault,
    Base,
    Dispatch
} from "../../lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import "../../lib/euler-vault-kit/src/EVault/shared/Constants.sol";

import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/console2.sol";

uint256 constant BLOCK_TIME = 1;
uint256 constant MIN_TEST_ASSETS = 1e9;
uint256 constant MAX_TEST_ASSETS = 1e28;
uint136 constant CAP = type(uint112).max;
uint256 constant NB_MARKETS = ConstantsLib.MAX_QUEUE_LENGTH + 1;

contract BaseTest is EVaultTestBase {
    address internal OWNER = makeAddr("Owner");
    address internal SUPPLIER = makeAddr("Supplier");
    address internal BORROWER = makeAddr("Borrower");
    address internal REPAYER = makeAddr("Repayer");
    address internal ONBEHALF = makeAddr("OnBehalf");
    address internal RECEIVER = makeAddr("Receiver");
    address internal ALLOCATOR = makeAddr("Allocator");
    address internal CURATOR = makeAddr("Curator");
    address internal GUARDIAN = makeAddr("Guardian");
    address internal FEE_RECIPIENT = makeAddr("FeeRecipient");
    address internal SKIM_RECIPIENT = makeAddr("SkimRecipient");

    ERC20Mock internal loanToken = new ERC20Mock("loan", "B");
    ERC20Mock internal collateralToken = new ERC20Mock("collateral", "C");

    IERC4626[] internal allMarkets;
    IERC4626 internal idleVault;
    IERC4626 internal collateralVault;

    PerspectiveMock internal perspective;

    function setUp() public virtual override {
        super.setUp();

        vm.label(address(loanToken), "Loan");
        vm.label(address(collateralToken), "Collateral");

        perspective = new PerspectiveMock();

        _etchEVaultOverrides();

        IEVault eVault;
        eVault = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(loanToken), address(oracle), unitOfAccount))
        );
        eVault.setHookConfig(address(0), 0);

        idleVault = _toIERC4626(eVault);
        vm.label(address(idleVault), "IdleVault");
        perspective.perspectiveVerify(address(idleVault));

        eVault = IEVault(
            factory.createProxy(
                address(0), true, abi.encodePacked(address(collateralToken), address(oracle), unitOfAccount)
            )
        );
        eVault.setHookConfig(address(0), 0);

        collateralVault = _toIERC4626(eVault);

        for (uint256 i; i < NB_MARKETS; ++i) {
            uint16 ltv = 0.8e4 / (uint16(i) + 1);

            eVault = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(loanToken), address(oracle), unitOfAccount)
                )
            );
            eVault.setHookConfig(address(0), 0);
            eVault.setInterestRateModel(address(new IRMTestDefault()));
            eVault.setMaxLiquidationDiscount(0.2e4);

            eVault.setLTV(address(collateralVault), ltv, ltv, 0);

            perspective.perspectiveVerify(address(eVault));

            allMarkets.push(_toIERC4626(eVault));

            vm.prank(SUPPLIER);
            loanToken.approve(address(eVault), type(uint256).max);

            vm.prank(REPAYER);
            loanToken.approve(address(eVault), type(uint256).max);
        }

        vm.startPrank(BORROWER);
        collateralToken.approve(address(collateralVault), type(uint256).max);
        evc.enableCollateral(BORROWER, address(collateralVault));

        vm.stopPrank();

        allMarkets.push(idleVault); // Must be pushed last.

        oracle.setPrice(address(loanToken), unitOfAccount, 1e18);
        oracle.setPrice(address(collateralToken), unitOfAccount, 1e18);
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * BLOCK_TIME); // Block speed should depend on test network.
    }

    /// @dev Bounds the fuzzing input to a realistic number of blocks.
    function _boundBlocks(uint256 blocks) internal pure returns (uint256) {
        return bound(blocks, 2, type(uint24).max);
    }

    /// @dev Bounds the fuzzing input to a non-zero address.
    /// @dev This function should be used in place of `vm.assume` in invariant test handler functions:
    /// https://github.com/foundry-rs/foundry/issues/4190.
    function _boundAddressNotZero(address input) internal pure virtual returns (address) {
        return address(uint160(bound(uint256(uint160(input)), 1, type(uint160).max)));
    }

    /// @dev Returns a random market params from the list of markets enabled on Blue (except the idle market).
    function _randomMarket(uint256 seed) internal view returns (IERC4626) {
        return allMarkets[seed % (allMarkets.length - 1)];
    }

    function _randomCandidate(address[] memory candidates, uint256 seed) internal pure returns (address) {
        if (candidates.length == 0) return address(0);

        return candidates[seed % candidates.length];
    }

    function _removeAll(address[] memory inputs, address removed) internal pure returns (address[] memory result) {
        result = new address[](inputs.length);

        uint256 nbAddresses;
        for (uint256 i; i < inputs.length; ++i) {
            address input = inputs[i];

            if (input != removed) {
                result[nbAddresses] = input;
                ++nbAddresses;
            }
        }

        assembly {
            mstore(result, nbAddresses)
        }
    }

    function _randomNonZero(address[] memory users, uint256 seed) internal pure returns (address) {
        users = _removeAll(users, address(0));

        return _randomCandidate(users, seed);
    }

    function _toIERC4626(IEVault vault) internal pure returns (IERC4626) {
        return IERC4626(address(vault));
    }

    function _toEVault(IERC4626 vault) internal pure returns (IEVault) {
        return IEVault(address(vault));
    }

    function _toEVaultMock(IERC4626 vault) internal pure returns (EVaultMock) {
        return EVaultMock(address(vault));
    }

    function _expectedSupplyAssets(IERC4626 _market, address _user) internal view virtual returns (uint256 assets) {
        assets = _market.convertToAssets(_market.balanceOf(_user));
    }

    function _etchEVaultOverrides() internal {
        integrations =
            Base.Integrations(address(evc), address(protocolConfig), sequenceRegistry, balanceTracker, permit2);
        modules = Dispatch.DeployedModules({
            initialize: initializeModule,
            token: tokenModule,
            vault: vaultModule,
            borrowing: borrowingModule,
            liquidation: liquidationModule,
            riskManager: riskManagerModule,
            balanceForwarder: balanceForwarderModule,
            governance: governanceModule
        });
        address mockImpl = address(new EVaultMock(integrations, modules));

        vm.etch(factory.implementation(), mockImpl.code);
    }
}
