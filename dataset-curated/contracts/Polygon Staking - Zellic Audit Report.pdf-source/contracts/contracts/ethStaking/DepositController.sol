// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IDepositContract.sol";
import "./interfaces/IEthStakingStrategy.sol";
import "./interfaces/INWLOperatorController.sol";
import "./interfaces/IWLOperatorController.sol";

/**
 * @title Deposit Controller
 * @notice Initiates ETH deposits and handles pre-deposit security checks
 */
contract DepositController is Ownable {
    uint256 public constant PUBKEY_LENGTH = 48;

    IDepositContract public depositContract;
    IEthStakingStrategy public ethStakingStrategy;
    INWLOperatorController public nwlOperatorController;
    IWLOperatorController public wlOperatorController;

    constructor(
        address _depositContract,
        address _ethStakingStrategy,
        address _nwlOperatorController,
        address _wlOperatorController
    ) {
        depositContract = IDepositContract(_depositContract);
        ethStakingStrategy = IEthStakingStrategy(_ethStakingStrategy);
        nwlOperatorController = INWLOperatorController(_nwlOperatorController);
        wlOperatorController = IWLOperatorController(_wlOperatorController);
    }

    /**
     * @notice initiates ether deposit
     * @dev params should be passed along from getNextValidators
     * @param _depositRoot deposit contract deposit root at time of key verification
     * @param _nwlStateHash current state hash of nwl operator controller at time of key verification
     * @param _wlStateHash current state hash of wl operator controller at time of key verification
     * @param _nwlTotalValidatorCount sum of all validators to assign non-whitelisted operators
     * @param _wlTotalValidatorCount sum of all validators to assign whitelisted operators
     * @param _wlOperatorIds ids of whitelisted operators that should be assigned validators
     * @param _wlValidatorCounts number of validators to assign each whitelisted operator
     */
    function depositEther(
        bytes32 _depositRoot,
        bytes32 _nwlStateHash,
        bytes32 _wlStateHash,
        uint256 _nwlTotalValidatorCount,
        uint256 _wlTotalValidatorCount,
        uint256[] calldata _wlOperatorIds,
        uint256[] calldata _wlValidatorCounts
    ) external onlyOwner {
        bytes32 depositRoot = depositContract.get_deposit_root();
        bytes32 nwlStateHash = nwlOperatorController.currentStateHash();
        bytes32 wlStateHash = wlOperatorController.currentStateHash();

        require(_depositRoot == depositRoot, "depositRoot has changed");
        require(_nwlStateHash == nwlStateHash, "nwlStateHash has changed");
        require(_wlStateHash == wlStateHash, "wlStateHash has changed");

        ethStakingStrategy.depositEther(
            _nwlTotalValidatorCount,
            _wlTotalValidatorCount,
            _wlOperatorIds,
            _wlValidatorCounts
        );
    }

    /**
     * @notice returns next set of validators and current state of contracts
     * @dev returned keys should be verified off-chain, then depositEther should be called
     * @param _totalValidatorCount total number of validators to assign
     * @return depositRoot deposit contract deposit root
     * @return nwlStateHash current state hash of nwl operator controller
     * @return wlStateHash current state hash of wl operator controller
     * @return nwlTotalValidatorCount sum of all validators to assign non-whitelisted operators
     * @return wlTotalValidatorCount sum of all validators to assign whitelisted operators
     * @return wlOperatorIds ids of whitelisted operators that should be assigned validators
     * @return wlValidatorCounts number of validators to assign each whitelisted operator
     * @return nwlKeys nwl validator keys to be assigned
     * @return wlKeys wl validator keys to be assigned
     */
    function getNextValidators(
        uint256 _totalValidatorCount
    )
        external
        view
        returns (
            bytes32 depositRoot,
            bytes32 nwlStateHash,
            bytes32 wlStateHash,
            uint256 nwlTotalValidatorCount,
            uint256 wlTotalValidatorCount,
            uint256[] memory wlOperatorIds,
            uint256[] memory wlValidatorCounts,
            bytes memory nwlKeys,
            bytes memory wlKeys
        )
    {
        uint256 nwlQueueLength = nwlOperatorController.queueLength();
        uint256 wlQueueLength = wlOperatorController.queueLength();

        require(
            _totalValidatorCount <= nwlQueueLength + wlQueueLength,
            "not enough validators in queue"
        );

        depositRoot = depositContract.get_deposit_root();
        nwlStateHash = nwlOperatorController.currentStateHash();
        wlStateHash = wlOperatorController.currentStateHash();

        nwlTotalValidatorCount = nwlQueueLength >= _totalValidatorCount
            ? _totalValidatorCount
            : nwlQueueLength;
        if (nwlTotalValidatorCount > 0) {
            nwlKeys = nwlOperatorController.getNextValidators(nwlTotalValidatorCount);
        }

        if (nwlTotalValidatorCount < _totalValidatorCount) {
            (wlOperatorIds, wlValidatorCounts, wlTotalValidatorCount, wlKeys) = wlOperatorController
                .getNextValidators(_totalValidatorCount - nwlTotalValidatorCount);
        }
    }
}
