// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {EVCUtil} from "../lib/ethereum-vault-connector/src/utils/EVCUtil.sol";
import "./helpers/IntegrationTest.sol";

contract EulerEarnFactoryTest is IntegrationTest {
    function testFactoryAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, (address(0))));
        new EulerEarnFactory(address(0), address(evc), address(permit2), address(perspective));

        vm.expectRevert(EVCUtil.EVC_InvalidAddress.selector);
        new EulerEarnFactory(admin, address(0), address(permit2), address(perspective));

        new EulerEarnFactory(admin, address(evc), address(0), address(perspective));

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        new EulerEarnFactory(admin, address(evc), address(permit2), address(0));
    }

    function testCreateEulerEarn(
        address initialOwner,
        uint256 initialTimelock,
        string memory name,
        string memory symbol,
        bytes32 salt
    ) public {
        vm.assume(address(initialOwner) != address(0));
        initialTimelock = _boundInitialTimelock(initialTimelock);

        bytes32 initCodeHash = hashInitCode(
            type(EulerEarn).creationCode,
            abi.encode(initialOwner, address(evc), address(permit2), initialTimelock, address(loanToken), name, symbol)
        );
        address expectedAddress = computeCreate2Address(salt, initCodeHash, address(eeFactory));

        vm.expectEmit(address(eeFactory));
        emit EventsLib.CreateEulerEarn(
            expectedAddress, address(this), initialOwner, initialTimelock, address(loanToken), name, symbol, salt
        );

        IEulerEarn eulerEarn =
            eeFactory.createEulerEarn(initialOwner, initialTimelock, address(loanToken), name, symbol, salt);

        assertEq(expectedAddress, address(eulerEarn), "computeCreate2Address");

        assertTrue(eeFactory.isVault(address(eulerEarn)), "isVault");

        assertEq(eulerEarn.owner(), initialOwner, "owner");
        assertEq(address(eulerEarn.EVC()), address(evc), "evc");
        assertEq(eulerEarn.timelock(), initialTimelock, "timelock");
        assertEq(eulerEarn.asset(), address(loanToken), "asset");
        assertEq(eulerEarn.name(), name, "name");
        assertEq(eulerEarn.symbol(), symbol, "symbol");
    }

    function testSupportedPerspective() public {
        assertEq(eeFactory.supportedPerspective(), address(perspective));

        address newPerspective = makeAddr("new perspective");
        vm.expectRevert();
        vm.prank(makeAddr("not admin"));
        eeFactory.setPerspective(newPerspective);

        vm.startPrank(admin);

        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        eeFactory.setPerspective(address(0));

        eeFactory.setPerspective(newPerspective);
        assertEq(eeFactory.supportedPerspective(), newPerspective);
    }

    function testIsStrategyAllowed() public {
        address newStrategy = makeAddr("new strategy");

        assertFalse(eeFactory.isStrategyAllowed(newStrategy));

        perspective.perspectiveVerify(newStrategy);

        assertTrue(eeFactory.isStrategyAllowed(newStrategy));
    }

    function testGetVaults() public {
        EulerEarnFactory factory = new EulerEarnFactory(admin, address(evc), address(permit2), address(perspective));

        uint256 amountVaults = 10;
        address[] memory vaultsList = new address[](amountVaults);

        for (uint256 i; i < amountVaults; i++) {
            address vault = address(
                factory.createEulerEarn(
                    OWNER, TIMELOCK, address(loanToken), "EulerEarn Vault", "EEV", bytes32(uint256(i))
                )
            );
            vaultsList[i] = vault;
        }

        uint256 len = factory.getVaultListLength();

        assertEq(len, amountVaults);

        address[] memory listVaultsTest;
        address[] memory listFactory;

        // get all vaults
        uint256 startIndex = 0;
        uint256 endIndex = type(uint256).max;

        listFactory = factory.getVaultListSlice(startIndex, endIndex);

        listVaultsTest = vaultsList;

        assertEq(listFactory, listVaultsTest);

        //test getvaultsList(3, 10) - get [3,10) slice
        startIndex = 3;
        endIndex = 10;

        listFactory = factory.getVaultListSlice(startIndex, endIndex);

        listVaultsTest = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            listVaultsTest[i - startIndex] = vaultsList[i];
        }

        assertEq(listFactory, listVaultsTest);

        vm.expectRevert(ErrorsLib.BadQuery.selector);
        factory.getVaultListSlice(endIndex, startIndex);

        vm.expectRevert(ErrorsLib.BadQuery.selector);
        factory.getVaultListSlice(startIndex, endIndex + 1);
    }
}
