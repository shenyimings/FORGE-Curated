// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";

import "../core/base/Strategy.sol";
import "./interfaces/IWrappedETH.sol";
import "./interfaces/IWLOperatorController.sol";
import "./interfaces/INWLOperatorController.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IRewardsReceiver.sol";

/**
 * @title ETH Staking Strategy
 * @notice Handles Ethereum staking deposits/withdrawals
 */
contract EthStakingStrategy is Strategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant PUBKEY_LENGTH = 48;
    uint256 public constant SIGNATURE_LENGTH = 96;

    uint256 public constant DEPOSIT_AMOUNT = 32 ether;
    uint256 internal constant DEPOSIT_AMOUNT_UNIT = 1 gwei;

    uint256 internal constant BASIS_POINTS = 10000;

    IDepositContract public depositContract;
    IWLOperatorController public wlOperatorController;
    INWLOperatorController public nwlOperatorController;
    IRewardsReceiver public rewardsReceiver;
    address public beaconOracle;
    address public depositController;

    bytes32 public withdrawalCredentials;

    uint256 public operatorFeeBasisPoints;

    uint256 public depositedValidators;
    uint256 public beaconValidators;
    uint256 public beaconBalance;
    uint256 public nwlLostOperatorStakes;

    int256 private depositChange;
    uint256 public totalDeposits;
    uint256 public bufferedETH;

    uint256 private maxDeposits;
    uint256 private minDeposits;

    event DepositEther(uint256 nwlValidatorCount, uint256 wlValidatorCount);
    event ReportBeaconState(
        uint256 beaconValidators,
        uint256 beaconBalance,
        uint256 nwlLostOperatorStakes
    );
    event SetMaxDeposits(uint256 max);
    event SetMinDeposits(uint256 min);
    event SetDepositController(address controller);
    event SetRewardsReceiver(address rewardsReceiver);
    event SetBeaconOracle(address oracle);
    event SetWLOperatorController(address controller);
    event SetNWLOperatorController(address controller);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _wETH,
        address _stakingPool,
        uint256 _maxDeposits,
        uint256 _minDeposits,
        address _depositContract,
        bytes32 _withdrawalCredentials,
        uint256 _operatorFeeBasisPoints
    ) public initializer {
        __Strategy_init(_wETH, _stakingPool);
        depositContract = IDepositContract(_depositContract);
        withdrawalCredentials = _withdrawalCredentials;
        operatorFeeBasisPoints = _operatorFeeBasisPoints;
        maxDeposits = _maxDeposits;
        minDeposits = _minDeposits;
    }

    receive() external payable {}

    /**
     * @notice Updates the number of validators in the beacon validator set and their total balance
     * @dev periodically called by the Oracle contract
     * @param _beaconValidators number of validators in the beacon state
     * @param _beaconBalance summed balance of all validators
     * @param _nwlLostOperatorStakes sum of all lost non-whitelisted operator stakes (max of 16 ETH per nwl validator -
     * the first 16 ETH lost for each nwl validator is staked by the operator, not this pool)
     */
    function reportBeaconState(
        uint256 _beaconValidators,
        uint256 _beaconBalance,
        uint256 _nwlLostOperatorStakes
    ) external {
        require(msg.sender == beaconOracle, "Sender is not beacon oracle");
        require(
            _beaconValidators <= depositedValidators,
            "Reported more validators than deposited"
        );
        require(_beaconValidators >= beaconValidators, "Reported less validators than tracked");

        uint256 newValidators = _beaconValidators - beaconValidators;
        int rewardBase = int(
            newValidators * DEPOSIT_AMOUNT + beaconBalance + nwlLostOperatorStakes
        );

        beaconBalance = _beaconBalance;
        beaconValidators = _beaconValidators;
        nwlLostOperatorStakes = _nwlLostOperatorStakes;

        int change = int(_beaconBalance) - rewardBase + int(_nwlLostOperatorStakes);
        if (change > 0) {
            uint256 rewards = rewardsReceiver.withdraw();
            if (rewards > 0) {
                IWrappedETH(address(token)).wrap{value: rewards}();
                bufferedETH += rewards;
                change += int(rewards);
            }
        }

        depositChange += change;
        emit ReportBeaconState(_beaconValidators, _beaconBalance, _nwlLostOperatorStakes);
    }

    /**
     * @notice unwraps wETH and deposits ETH into the DepositContract
     * @dev always deposits for non-whitelisted validators first, followed by whitelisted only if there
     * are no non-whitelisted remaining in the queue
     * @param _nwlTotalValidatorCount sum of all validators to assign non-whitelisted operators
     * @param _wlTotalValidatorCount sum of all validators to assign whitelisted operators
     * @param _wlOperatorIds ids of whitelisted operators that should be assigned validators
     * @param _wlValidatorCounts number of validators to assign each whitelisted operator
     */
    function depositEther(
        uint256 _nwlTotalValidatorCount,
        uint256 _wlTotalValidatorCount,
        uint256[] calldata _wlOperatorIds,
        uint256[] calldata _wlValidatorCounts
    ) external {
        require(msg.sender == depositController, "Sender is not deposit controller");

        uint256 totalDepositAmount = (DEPOSIT_AMOUNT *
            _wlTotalValidatorCount +
            (DEPOSIT_AMOUNT / 2) *
            _nwlTotalValidatorCount);
        require(totalDepositAmount > 0, "Cannot deposit 0");
        require(bufferedETH >= totalDepositAmount, "Insufficient balance for deposit");

        bytes memory nwlPubkeys;
        bytes memory nwlSignatures;

        if (_nwlTotalValidatorCount > 0) {
            (nwlPubkeys, nwlSignatures) = nwlOperatorController.assignNextValidators(
                _nwlTotalValidatorCount
            );

            require(
                nwlPubkeys.length / PUBKEY_LENGTH == _nwlTotalValidatorCount,
                "Incorrect non-whitelisted pubkeys length"
            );
            require(
                nwlSignatures.length / SIGNATURE_LENGTH == _nwlTotalValidatorCount,
                "Incorrect non-whitelisted signatures length"
            );
            require(nwlPubkeys.length % PUBKEY_LENGTH == 0, "Invalid non-whitelisted pubkeys");
            require(
                nwlSignatures.length % SIGNATURE_LENGTH == 0,
                "Invalid non-whitelisted signatures"
            );
        }

        bytes memory wlPubkeys;
        bytes memory wlSignatures;

        if (_wlTotalValidatorCount > 0) {
            require(
                nwlOperatorController.queueLength() == 0,
                "Non-whitelisted queue must be empty to assign whitelisted"
            );

            (wlPubkeys, wlSignatures) = wlOperatorController.assignNextValidators(
                _wlOperatorIds,
                _wlValidatorCounts,
                _wlTotalValidatorCount
            );

            require(
                wlPubkeys.length / PUBKEY_LENGTH == _wlTotalValidatorCount,
                "Incorrect whitelisted pubkeys length"
            );
            require(
                wlSignatures.length / SIGNATURE_LENGTH == _wlTotalValidatorCount,
                "Incorrect whitelisted signatures length"
            );
            require(wlPubkeys.length % PUBKEY_LENGTH == 0, "Invalid whitelisted pubkeys");
            require(wlSignatures.length % SIGNATURE_LENGTH == 0, "Invalid whitelisted signatures");
        }

        IWrappedETH(address(token)).unwrap(totalDepositAmount);

        for (uint256 i = 0; i < _nwlTotalValidatorCount; i++) {
            bytes memory pubkey = BytesLib.slice(nwlPubkeys, i * PUBKEY_LENGTH, PUBKEY_LENGTH);
            bytes memory signature = BytesLib.slice(
                nwlSignatures,
                i * SIGNATURE_LENGTH,
                SIGNATURE_LENGTH
            );
            _deposit(pubkey, signature);
        }

        for (uint256 i = 0; i < _wlTotalValidatorCount; i++) {
            bytes memory pubkey = BytesLib.slice(wlPubkeys, i * PUBKEY_LENGTH, PUBKEY_LENGTH);
            bytes memory signature = BytesLib.slice(
                wlSignatures,
                i * SIGNATURE_LENGTH,
                SIGNATURE_LENGTH
            );
            _deposit(pubkey, signature);
        }

        bufferedETH -= totalDepositAmount;
        depositedValidators += _nwlTotalValidatorCount + _wlTotalValidatorCount;
        emit DepositEther(_nwlTotalValidatorCount, _wlTotalValidatorCount);
    }

    /**
     * @notice deposits wETH from StakingPool into this strategy
     * @param _amount amount of wETH to deposit
     */
    function deposit(uint256 _amount, bytes calldata) external onlyStakingPool {
        require(_amount <= canDeposit(), "Insufficient deposit room");
        token.transferFrom(address(stakingPool), address(this), _amount);
        totalDeposits += _amount;
        bufferedETH += _amount;
    }

    /**
     * @notice withdraws ETH
     * @dev not implemented yet
     * @param _amount amount of ETH to withdraw
     */
    function withdraw(uint256 _amount, bytes calldata) external onlyStakingPool {
        revert("Not implemented yet");
    }

    /**
     * @notice withdraws ETH to non-whitelisted operator
     * @dev not implemented yet
     * @param _receiver receiver of ETH
     * @param _amount amount of ETH to withdraw
     */
    function nwlWithdraw(address _receiver, uint256 _amount) external {
        require(
            msg.sender == address(nwlOperatorController),
            "Sender is not non-whitelisted operator controller"
        );
        revert("Not implemented yet");
    }

    function getDepositChange() external view override returns (int256) {
        return depositChange;
    }

    /**
     * @notice updates deposit accounting and calculates reward distribution
     */
    function updateDeposits(
        bytes calldata
    )
        external
        onlyStakingPool
        returns (int256 depChange, address[] memory receivers, uint256[] memory amounts)
    {
        depChange = depositChange;
        if (depChange > 0) {
            uint256 rewards = uint256(depChange);

            uint256 nwlOperatorDeposits = nwlOperatorController.totalActiveStake();
            uint256 nwlOperatorRewardsBasisPoints = (BASIS_POINTS * nwlOperatorDeposits) /
                (totalDeposits + nwlOperatorDeposits);

            uint256 activeWLValidators = wlOperatorController.totalActiveValidators();
            uint256 activeNWLValidators = nwlOperatorController.totalActiveValidators();

            uint256 operatorFee = (rewards * operatorFeeBasisPoints) / BASIS_POINTS;
            uint256 wlOperatorFee = (operatorFee * activeWLValidators) /
                (activeNWLValidators + activeWLValidators);
            uint256 nwlOperatorFee = operatorFee -
                wlOperatorFee +
                (rewards * nwlOperatorRewardsBasisPoints) /
                BASIS_POINTS;

            receivers = new address[](2);
            amounts = new uint256[](2);

            receivers[0] = address(wlOperatorController);
            receivers[1] = address(nwlOperatorController);
            amounts[0] = wlOperatorFee;
            amounts[1] = nwlOperatorFee;
        }
        totalDeposits = uint256(int(totalDeposits) + depChange);
        depositChange = 0;
    }

    /**
     * @notice sets the whitelisted operator controller
     * @param _wlOperatorController controller address
     */
    function setWLOperatorController(address _wlOperatorController) external onlyOwner {
        wlOperatorController = IWLOperatorController(_wlOperatorController);
        emit SetWLOperatorController(_wlOperatorController);
    }

    /**
     * @notice sets the non-whitelisted operator controller
     * @param _nwlOperatorController controller address
     */
    function setNWLOperatorController(address _nwlOperatorController) external onlyOwner {
        nwlOperatorController = INWLOperatorController(_nwlOperatorController);
        emit SetNWLOperatorController(_nwlOperatorController);
    }

    /**
     * @notice sets the beacon oracle
     * @param _beaconOracle oracle address
     */
    function setBeaconOracle(address _beaconOracle) external onlyOwner {
        beaconOracle = _beaconOracle;
        emit SetBeaconOracle(_beaconOracle);
    }

    /**
     * @notice returns the total amount of deposits in this strategy
     * @return total deposits
     */
    function getTotalDeposits() public view override returns (uint256) {
        return totalDeposits;
    }

    /**
     * @notice returns the maximum that can be deposited into the strategy
     * @return max deposit
     */
    function getMaxDeposits() public view override returns (uint256) {
        return maxDeposits;
    }

    /**
     * @notice returns the minimum that must remain the strategy
     * @return min deposit
     */
    function getMinDeposits() public view override returns (uint256) {
        return minDeposits;
    }

    /**
     * @notice sets the maximum that can be deposited into the strategy
     * @param _maxDeposits maximum deposits
     */
    function setMaxDeposits(uint256 _maxDeposits) external onlyOwner {
        maxDeposits = _maxDeposits;
        emit SetMaxDeposits(_maxDeposits);
    }

    /**
     * @notice sets the minimum that can be deposited into the strategy
     * @param _minDeposits minimum deposits
     */
    function setMinDeposits(uint256 _minDeposits) external onlyOwner {
        minDeposits = _minDeposits;
        emit SetMinDeposits(_minDeposits);
    }

    /**
     * @notice sets the deposit controller
     * @param _depositController deposit controller address
     */
    function setDepositController(address _depositController) external onlyOwner {
        depositController = _depositController;
        emit SetDepositController(_depositController);
    }

    /**
     * @notice sets the rewards receiver
     * @param _rewardsReceiver rewards receiver address
     */
    function setRewardsReceiver(address _rewardsReceiver) external onlyOwner {
        rewardsReceiver = IRewardsReceiver(_rewardsReceiver);
        emit SetRewardsReceiver(_rewardsReceiver);
    }

    /**
     * @dev invokes a single deposit call to the DepositContract
     * @param _pubkey validator to deposit for
     * @param _signature signature of the deposit call
     */
    function _deposit(bytes memory _pubkey, bytes memory _signature) internal {
        require(withdrawalCredentials != 0, "Empty withdrawal credentials");

        uint256 depositValue = DEPOSIT_AMOUNT;
        uint256 depositAmount = depositValue / DEPOSIT_AMOUNT_UNIT;

        bytes32 pubkeyRoot = sha256(abi.encodePacked(_pubkey, bytes16(0)));
        bytes32 signatureRoot = sha256(
            abi.encodePacked(
                sha256(BytesLib.slice(_signature, 0, 64)),
                sha256(
                    abi.encodePacked(
                        BytesLib.slice(_signature, 64, SIGNATURE_LENGTH - 64),
                        bytes32(0)
                    )
                )
            )
        );
        bytes32 depositDataRoot = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubkeyRoot, withdrawalCredentials)),
                sha256(
                    abi.encodePacked(
                        _toLittleEndian64(uint64(depositAmount)),
                        bytes24(0),
                        signatureRoot
                    )
                )
            )
        );

        uint256 targetBalance = address(this).balance - depositValue;

        depositContract.deposit{value: depositValue}(
            _pubkey,
            abi.encodePacked(withdrawalCredentials),
            _signature,
            depositDataRoot
        );

        require(address(this).balance == targetBalance, "Deposit failed");
    }

    /**
     * @dev converts value to little endian bytes
     * @param _value number to convert
     */
    function _toLittleEndian64(uint64 _value) internal pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(_value);
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }
}
