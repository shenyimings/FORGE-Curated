// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsHelper } from "@layerzerolabs/test-devtools-evm-foundry/contracts/OptionsHelper.sol";

import { PRL } from "contracts/principal/PRL.sol";
import { PrincipalMigrationContract } from "contracts/principal/PrincipalMigrationContract.sol";
import { LockBox } from "contracts/principal/LockBox.sol";

import { PeripheralMigrationContract } from "contracts/peripheral/PeripheralMigrationContract.sol";
import { PeripheralPRL } from "contracts/peripheral/PeripheralPRL.sol";

import { ERC20Mock } from "contracts/mocks/ERC20Mock.sol";

import { SigUtils } from "./SigUtils.sol";

abstract contract Deploys is TestHelperOz5 {
    SigUtils internal sigUtils;

    PRL internal prl;
    ERC20Mock internal mimo;

    LockBox internal lockBox;
    PrincipalMigrationContract internal principalMigrationContract;

    PeripheralMigrationContract internal peripheralMigrationContractA;
    PeripheralMigrationContract internal peripheralMigrationContractB;
    PeripheralPRL internal peripheralPRLA;
    PeripheralPRL internal peripheralPRLB;

    function _deployERC20Mock(string memory name, string memory symbol, uint8 decimals) internal returns (ERC20Mock) {
        ERC20Mock token = new ERC20Mock(name, symbol, decimals);
        vm.label({ account: address(token), newLabel: name });
        return token;
    }

    function _deployPRL(uint256 totalSupply) internal returns (PRL) {
        PRL _prl = new PRL(totalSupply);
        vm.label({ account: address(_prl), newLabel: "PRL Token" });
        return _prl;
    }

    function _deployLockBox(address _prlToken, address _endpoint, address _owner) internal returns (LockBox) {
        LockBox _lockBox = LockBox(_deployOApp(type(LockBox).creationCode, abi.encode(_prlToken, _endpoint, _owner)));
        vm.label({ account: address(_lockBox), newLabel: "LockBox" });
        return _lockBox;
    }

    function _deployPeripheralPRL(
        address _endpoint,
        address _owner,
        string memory _label
    )
        internal
        returns (PeripheralPRL)
    {
        PeripheralPRL _peripheralPRL =
            PeripheralPRL(_deployOApp(type(PeripheralPRL).creationCode, abi.encode(_endpoint, _owner)));
        vm.label({ account: address(_peripheralPRL), newLabel: _label });
        return _peripheralPRL;
    }

    function _deployPeripheralMigrationContract(
        address _mimoToken,
        address _endpoint,
        address _owner,
        uint32 _mainEid,
        string memory _label
    )
        internal
        returns (PeripheralMigrationContract)
    {
        PeripheralMigrationContract _peripheralMigrationContract = PeripheralMigrationContract(
            _deployOApp(
                type(PeripheralMigrationContract).creationCode, abi.encode(_mimoToken, _endpoint, _owner, _mainEid)
            )
        );
        vm.label({ account: address(_peripheralMigrationContract), newLabel: _label });

        return _peripheralMigrationContract;
    }

    function _deployPrincipalMigrationContract(
        address _prlToken,
        address _mimoToken,
        address _lockBox,
        address _endpoint,
        address _owner
    )
        internal
        returns (PrincipalMigrationContract)
    {
        address deployedAddress = _deployOApp(
            type(PrincipalMigrationContract).creationCode,
            abi.encode(_prlToken, _mimoToken, _lockBox, _endpoint, _owner)
        );
        PrincipalMigrationContract _principalMigrationContract = PrincipalMigrationContract(payable(deployedAddress));
        vm.label({ account: address(_principalMigrationContract), newLabel: "PrincipalMigrationContract" });

        return _principalMigrationContract;
    }
}
