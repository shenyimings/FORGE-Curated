// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@arbitrum/nitro-contracts-1.2.1/src/bridge/IBridge.sol";
import "@arbitrum/nitro-contracts-1.2.1/src/bridge/IInbox.sol";
import "@arbitrum/nitro-contracts-1.2.1/src/bridge/IOutbox.sol";
import "@arbitrum/nitro-contracts-1.2.1/src/bridge/ISequencerInbox.sol";
import "@arbitrum/nitro-contracts-1.2.1/src/rollup/IRollupAdmin.sol";
import "@arbitrum/nitro-contracts-1.2.1/src/rollup/IRollupLogic.sol";

interface ISeqInboxPostUpgradeInit {
    function postUpgradeInit() external;
}

interface IChallengeManagerUpgradeInit {
    function postUpgradeInit(address _newOsp) external;
    function osp() external returns (address);
}

/// @notice Upgrades an Arbitrum orbit chain to nitro-contract 1.2.1 from 1.1.0 or 1.1.1
/// @dev    Does NOT support versions besides 1.1.0 or 1.1.1, inclduing their beta versions
///         Modified from
///         https://github.com/ArbitrumFoundation/governance/blob/a5375eea133e1b88df2116ed510ab2e3c07293d3/src/gov-action-contracts/AIPs/ArbOS20/ArbOS20Action.sol
contract NitroContracts1Point2Point1UpgradeAction {
    address public immutable newSequencerInboxImpl;
    address public immutable newChallengeManagerImpl;
    address public immutable newOsp;
    bytes32 public immutable newWasmModuleRoot;

    constructor(
        bytes32 _newWasmModuleRoot,
        address _newSequencerInboxImpl,
        address _newChallengeMangerImpl,
        address _newOsp
    ) {
        require(_newWasmModuleRoot != bytes32(0), "_newWasmModuleRoot is empty");
        newWasmModuleRoot = _newWasmModuleRoot;

        require(Address.isContract(_newSequencerInboxImpl), "_newSequencerInboxImpl is not a contract");
        newSequencerInboxImpl = _newSequencerInboxImpl;

        require(Address.isContract(_newChallengeMangerImpl), "_newChallengeMangerImpl is not a contract");
        newChallengeManagerImpl = _newChallengeMangerImpl;

        require(Address.isContract(address(_newOsp)), "_newOsp is not a contract");
        newOsp = _newOsp;
    }

    function perform(IRollupCore rollup, ProxyAdmin proxyAdmin) public {
        IRollupAdmin(address(rollup)).setWasmModuleRoot(newWasmModuleRoot);

        // verify:
        require(rollup.wasmModuleRoot() == newWasmModuleRoot, "wasm module root not set");

        TransparentUpgradeableProxy sequencerInbox =
            TransparentUpgradeableProxy(payable(address(rollup.sequencerInbox())));
        (, uint256 futureBlocksBefore,,) = ISequencerInbox(address(sequencerInbox)).maxTimeVariation();
        proxyAdmin.upgradeAndCall(
            sequencerInbox, newSequencerInboxImpl, abi.encodeCall(ISeqInboxPostUpgradeInit.postUpgradeInit, ())
        );

        // verify
        require(
            proxyAdmin.getProxyImplementation(sequencerInbox) == newSequencerInboxImpl,
            "new seq inbox implementation set"
        );
        (, uint256 futureBlocksAfter,,) = ISequencerInbox(address(sequencerInbox)).maxTimeVariation();
        require(futureBlocksBefore != 0 && futureBlocksBefore == futureBlocksAfter, "maxTimeVariation not set");

        // set the new challenge manager impl
        TransparentUpgradeableProxy challengeManager =
            TransparentUpgradeableProxy(payable(address(rollup.challengeManager())));
        proxyAdmin.upgradeAndCall(
            challengeManager,
            newChallengeManagerImpl,
            abi.encodeCall(IChallengeManagerUpgradeInit.postUpgradeInit, (newOsp))
        );

        require(
            proxyAdmin.getProxyImplementation(challengeManager) == newChallengeManagerImpl,
            "new challenge manager implementation set"
        );
        require(IChallengeManagerUpgradeInit(address(challengeManager)).osp() == newOsp, "new OSP not set");
    }
}
