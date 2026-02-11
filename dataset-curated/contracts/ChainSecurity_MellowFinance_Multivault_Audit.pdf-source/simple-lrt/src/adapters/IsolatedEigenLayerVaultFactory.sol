// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {EigenLayerWithdrawalQueue} from "../queues/EigenLayerWithdrawalQueue.sol";

import "./IsolatedEigenLayerVault.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract IsolatedEigenLayerVaultFactory is IIsolatedEigenLayerVaultFactory {
    /// @inheritdoc IIsolatedEigenLayerVaultFactory
    address public immutable delegation;
    /// @inheritdoc IIsolatedEigenLayerVaultFactory
    address public immutable isolatedVaultSingleton;
    /// @inheritdoc IIsolatedEigenLayerVaultFactory
    address public immutable withdrawalQueueSingleton;
    /// @inheritdoc IIsolatedEigenLayerVaultFactory
    address public immutable proxyAdmin;

    /// @inheritdoc IIsolatedEigenLayerVaultFactory
    mapping(address isolatedVault => Data) public instances;
    /// @inheritdoc IIsolatedEigenLayerVaultFactory
    mapping(bytes32 key => address isolatedVault) public isolatedVaults;

    constructor(
        address delegation_,
        address isolatedVaultSingleton_,
        address withdrawalQueueSingleton_,
        address proxyAdmin_
    ) {
        delegation = delegation_;
        isolatedVaultSingleton = isolatedVaultSingleton_;
        withdrawalQueueSingleton = withdrawalQueueSingleton_;
        proxyAdmin = proxyAdmin_;
    }

    /// @inheritdoc IIsolatedEigenLayerVaultFactory
    function key(address owner, address strategy, address operator) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, strategy, operator));
    }

    /// @inheritdoc IIsolatedEigenLayerVaultFactory
    function getOrCreate(address owner, address strategy, address operator, bytes calldata data)
        external
        returns (address isolatedVault, address withdrawalQueue)
    {
        bytes32 key_ = key(owner, strategy, operator);
        isolatedVault = isolatedVaults[key_];
        if (isolatedVault != address(0)) {
            return (isolatedVault, instances[isolatedVault].withdrawalQueue);
        }

        isolatedVault = address(
            new TransparentUpgradeableProxy{salt: key_}(
                isolatedVaultSingleton,
                proxyAdmin,
                abi.encodeCall(IsolatedEigenLayerVault.initialize, (owner))
            )
        );
        (ISignatureUtils.SignatureWithExpiry memory signature, bytes32 salt) =
            abi.decode(data, (ISignatureUtils.SignatureWithExpiry, bytes32));
        IIsolatedEigenLayerVault(isolatedVault).delegateTo(delegation, operator, signature, salt);
        withdrawalQueue = address(
            new TransparentUpgradeableProxy{salt: key_}(
                withdrawalQueueSingleton,
                proxyAdmin,
                abi.encodeCall(
                    EigenLayerWithdrawalQueue.initialize, (isolatedVault, strategy, operator)
                )
            )
        );

        instances[isolatedVault] = Data(owner, strategy, operator, withdrawalQueue);
        isolatedVaults[key_] = isolatedVault;
        emit Created(owner, strategy, operator, data, isolatedVault, withdrawalQueue);
    }
}
