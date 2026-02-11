// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IEulerEarn} from "./interfaces/IEulerEarn.sol";
import {IEulerEarnFactory} from "./interfaces/IEulerEarnFactory.sol";
import {IPerspective} from "./interfaces/IPerspective.sol";

import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

import {EulerEarn} from "./EulerEarn.sol";

import {Ownable, Context} from "openzeppelin-contracts/access/Ownable.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

/// @title EulerEarnFactory
/// @author Forked with gratitude from Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@morpho.org
/// @custom:contact security@euler.xyz
/// @notice This contract allows to create EulerEarn vaults, and to index them easily.
contract EulerEarnFactory is Ownable, EVCUtil, IEulerEarnFactory {
    /* IMMUTABLES */

    /// @dev The address of the Permit2 contract.
    address public immutable permit2Address;

    /* STORAGE */

    /// @inheritdoc IEulerEarnFactory
    mapping(address => bool) public isVault;

    /// @dev The list of all the vaults created by the factory.
    address[] public vaultList;

    /// @dev The perspective contract that is used to verify the strategies.
    IPerspective internal perspective;

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    /// @param _owner The owner of the factory contract.
    /// @param _evc The address of the EVC contract.
    /// @param _permit2 The address of the Permit2 contract.
    /// @param _perspective The address of the supported perspective contract.
    constructor(address _owner, address _evc, address _permit2, address _perspective) Ownable(_owner) EVCUtil(_evc) {
        if (_perspective == address(0)) revert ErrorsLib.ZeroAddress();

        permit2Address = _permit2;
        perspective = IPerspective(_perspective);
    }

    /* EXTERNAL */

    /// @inheritdoc IEulerEarnFactory
    function supportedPerspective() external view returns (address) {
        return address(perspective);
    }

    /// @inheritdoc IEulerEarnFactory
    function getVaultListLength() external view returns (uint256) {
        return vaultList.length;
    }

    /// @inheritdoc IEulerEarnFactory
    function getVaultListSlice(uint256 start, uint256 end) external view returns (address[] memory list) {
        if (end == type(uint256).max) end = vaultList.length;
        if (end < start || end > vaultList.length) revert ErrorsLib.BadQuery();

        list = new address[](end - start);
        for (uint256 i; i < end - start; ++i) {
            list[i] = vaultList[start + i];
        }
    }

    /// @inheritdoc IEulerEarnFactory
    function isStrategyAllowed(address id) external view returns (bool) {
        return perspective.isVerified(id) || isVault[id];
    }

    /// @inheritdoc IEulerEarnFactory
    function setPerspective(address _perspective) public onlyEVCAccountOwner onlyOwner {
        if (_perspective == address(0)) revert ErrorsLib.ZeroAddress();

        perspective = IPerspective(_perspective);

        emit EventsLib.SetPerspective(_perspective);
    }

    /// @inheritdoc IEulerEarnFactory
    function createEulerEarn(
        address initialOwner,
        uint256 initialTimelock,
        address asset,
        string memory name,
        string memory symbol,
        bytes32 salt
    ) external returns (IEulerEarn eulerEarn) {
        eulerEarn = IEulerEarn(
            address(
                new EulerEarn{salt: salt}(
                    initialOwner, address(evc), permit2Address, initialTimelock, asset, name, symbol
                )
            )
        );

        isVault[address(eulerEarn)] = true;

        vaultList.push(address(eulerEarn));

        emit EventsLib.CreateEulerEarn(
            address(eulerEarn), _msgSender(), initialOwner, initialTimelock, asset, name, symbol, salt
        );
    }

    /// @notice Retrieves the message sender in the context of the EVC.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    /// either msg.sender or the account authenticated by the EVC.
    /// @return The address of the message sender.
    function _msgSender() internal view virtual override(EVCUtil, Context) returns (address) {
        return EVCUtil._msgSender();
    }
}
