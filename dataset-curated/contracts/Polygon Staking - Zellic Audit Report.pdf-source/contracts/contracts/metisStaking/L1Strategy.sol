// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./interfaces/ISequencerVault.sol";
import "./interfaces/IMetisLockingInfo.sol";

/**
 * @title L1 Strategy
 * @notice Strategy that receives deposits sent from L2 (Metis) and stakes them into
 * Metis sequencer staking vaults on L1 (Ethereum)
 */
contract L1Strategy is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of METIS token
    IERC20Upgradeable public token;
    // address of L1 Transmitter
    address public l1Transmitter;

    // address of Metis LockingInfo
    IMetisLockingInfo public lockingInfo;

    // address on L2 that will receive claimed rewards
    address public rewardRecipient;
    // min amount of rewards required to relock/claim in vaults on a call to updateDeposits
    uint256 public minRewardsToClaim;

    // address of the implementation contract to use when deploying new vaults
    address public vaultImplementation;
    // list of all sequencer vaults
    ISequencerVault[] private vaults;

    // total deposits tracked in this strategy
    uint256 private totalDeposits;
    // total tokens queued for deposit into vaults
    uint256 private totalQueuedTokens;

    // basis point amount of an operator's earned rewards that they receive
    uint256 public operatorRewardPercentage;

    event VaultAdded(address signer);
    event SetOperatorRewardPercentage(uint256 operatorRewardPercentage);
    event SetVaultImplementation(address vaultImplementation);
    event UpgradedVaults(uint256[] vaults);

    error FeesTooLarge();
    error AddressNotContract();
    error SenderNotAuthorized();
    error ZeroAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _token address of METIS token
     * @param _lockingInfo address of Metis locking info contract
     * @param _vaultImplementation address of the implementation contract to use when deploying new vaults
     * @param _rewardRecipient address on l2 that will receive claimed rewards
     * @param _minRewardsToClaim min amount of rewards required to relock/claim in vaults on a call to updateDeposits
     * @param _operatorRewardPercentage basis point amount of an operator's earned rewards that they receive
     **/
    function initialize(
        address _token,
        address _lockingInfo,
        address _vaultImplementation,
        address _rewardRecipient,
        uint256 _minRewardsToClaim,
        uint256 _operatorRewardPercentage
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        token = IERC20Upgradeable(_token);
        lockingInfo = IMetisLockingInfo(_lockingInfo);

        if (!_isContract(_vaultImplementation)) revert AddressNotContract();
        vaultImplementation = _vaultImplementation;

        if (_rewardRecipient == address(0)) revert ZeroAddress();
        rewardRecipient = _rewardRecipient;

        minRewardsToClaim = _minRewardsToClaim;

        if (_operatorRewardPercentage > 3000) revert FeesTooLarge();
        operatorRewardPercentage = _operatorRewardPercentage;
    }

    /**
     * @notice Reverts if sender is not L1 Transmitter
     **/
    modifier onlyL1Transmitter() {
        if (msg.sender != l1Transmitter) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Deposits tokens into this strategy from the L1 Transmitter
     * @param _amount amount to deposit
     */
    function deposit(uint256 _amount) external onlyL1Transmitter {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        totalDeposits += _amount;
        totalQueuedTokens += _amount;
    }

    /**
     * @notice Withdraws tokens from this strategy to the L1 Transmitter
     * @param _amount amount to withdraw
     */
    function withdraw(uint256 _amount) external onlyL1Transmitter {
        if (_amount > totalQueuedTokens) {
            uint256 toWithdraw = _amount - totalQueuedTokens;

            for (uint256 i = vaults.length - 1; i >= 0; --i) {
                uint256 canWithdraw = vaults[i].canWithdraw();
                if (canWithdraw == 0) continue;

                if (toWithdraw <= canWithdraw) {
                    vaults[i].withdraw(toWithdraw);
                    break;
                } else {
                    vaults[i].withdraw(canWithdraw);
                    toWithdraw -= canWithdraw;
                }
            }
        }

        token.safeTransfer(msg.sender, _amount);

        totalDeposits -= _amount;
        uint256 balance = token.balanceOf(address(this));
        if (totalQueuedTokens != balance) totalQueuedTokens = balance;
    }

    /**
     * @notice Returns a list of all vaults controlled by this contract
     * @return list of vault addresses
     */
    function getVaults() external view returns (ISequencerVault[] memory) {
        return vaults;
    }

    /**
     * @notice Returns a list of principal deposits for all vaults
     * @return list of deposit amounts
     */
    function getVaultDeposits() external view returns (uint256[] memory) {
        uint256[] memory deposits = new uint256[](vaults.length);
        for (uint256 i = 0; i < vaults.length; ++i) {
            deposits[i] = vaults[i].getPrincipalDeposits();
        }
        return deposits;
    }

    /**
     * @notice Returns the total amount of queued tokens
     * @return total queued tokens
     */
    function getTotalQueuedTokens() external view returns (uint256) {
        return totalQueuedTokens;
    }

    /**
     * @notice Deposits queued tokens into vaults
     * @dev called by deposit controller bot once certain conditions are met as defined offchain
     * @param _vaults list of vaults to deposit into
     * @param _amounts amount to deposit into each vault
     */
    function depositQueuedTokens(
        uint256[] calldata _vaults,
        uint256[] calldata _amounts
    ) external onlyL1Transmitter {
        uint256 totalDeposited;

        for (uint256 i = 0; i < _vaults.length; ++i) {
            vaults[_vaults[i]].deposit(_amounts[i]);
            totalDeposited += _amounts[i];
        }

        totalQueuedTokens -= totalDeposited;
    }

    /**
     * @notice Returns the deposit change since deposits were last updated
     * @dev deposit change could be positive or negative depending on reward rate and whether
     * any slashing occurred
     * @return deposit change
     */
    function getDepositChange() public view returns (int) {
        uint256 totalBalance = token.balanceOf(address(this));
        for (uint256 i = 0; i < vaults.length; ++i) {
            totalBalance += vaults[i].getTotalDeposits();
        }
        return int(totalBalance) - int(totalDeposits);
    }

    /**
     * @notice Updates deposit accounting
     * @param _l2Gas per vault gas limit for reward bridging
     * @param _l2Fee per vault fee to pay for reward bridging
     * @return totalDeposits total deposits currently in the pool
     * @return claimedRewards amount of rewards claimed from Metis staking contract
     * @return opRewardReceivers list of operator reward receiver addresses on L2
     * @return opRewardAmounts list of newly earned operator reward amounts corresponding to receivers
     */
    function updateDeposits(
        uint32 _l2Gas,
        uint256 _l2Fee
    )
        external
        payable
        onlyL1Transmitter
        returns (
            uint256,
            uint256,
            address[] memory opRewardReceivers,
            uint256[] memory opRewardAmounts
        )
    {
        opRewardReceivers = new address[](vaults.length);
        opRewardAmounts = new uint256[](opRewardReceivers.length);

        uint256 vaultDeposits;
        uint256 claimedRewards;

        for (uint256 i = 0; i < opRewardReceivers.length; ++i) {
            (uint256 deposits, uint256 opRewards, uint256 claimed) = vaults[i].updateDeposits{
                value: minRewardsToClaim == 0 ? 0 : _l2Fee
            }(minRewardsToClaim, _l2Gas);

            vaultDeposits += deposits;
            claimedRewards += claimed;

            opRewardReceivers[i] = vaults[i].rewardsReceiver();
            opRewardAmounts[i] = opRewards;
        }

        uint256 balance = token.balanceOf(address(this));
        totalDeposits = vaultDeposits + balance;

        if (totalQueuedTokens != balance) totalQueuedTokens = balance;

        if (address(this).balance != 0) {
            payable(msg.sender).transfer(address(this).balance);
        }

        return (totalDeposits, claimedRewards, opRewardReceivers, opRewardAmounts);
    }

    /**
     * @notice Initiates an exit for a sequencer vault
     * @dev all sequencer rewards must be claimed for the vault being exited
     * @param _vaultId index of vault to exit
     */
    function initiateExit(uint256 _vaultId) external onlyOwner {
        vaults[_vaultId].initiateExit();
    }

    /**
     * @notice Withdraws all principal deposits for an exited sequencer vault and removes the vault
     * @dev all sequencer rewards must be claimed for the vault being exited
     * @param _vaultId index of vault
     */
    function finalizeExit(uint256 _vaultId) external onlyOwner {
        totalQueuedTokens += vaults[_vaultId].getPrincipalDeposits();
        vaults[_vaultId].finalizeExit();

        uint256 numVaults = vaults.length;
        for (uint256 i = _vaultId; i < numVaults - 1; ++i) {
            vaults[i] = vaults[i + 1];
        }
        vaults.pop();
    }

    /**
     * @notice Returns the total amount of deposits as tracked in this strategy
     * @return total deposits
     */
    function getTotalDeposits() public view returns (uint256) {
        return totalDeposits;
    }

    /**
     * @notice Returns the maximum that can be deposited into this strategy
     * @return maximum deposits
     */
    function getMaxDeposits() public view returns (uint256) {
        uint256 activeSequencers;

        uint256 numVaults = vaults.length;
        for (uint256 i = 0; i < numVaults; ++i) {
            if (vaults[i].exitDelayEndTime() == 0) {
                ++activeSequencers;
            }
        }

        return activeSequencers * getVaultDepositMax();
    }

    /**
     * @notice Returns the minimum that must remain this strategy
     * @return minimum deposits
     */
    function getMinDeposits() public view returns (uint256) {
        uint256 minDeposits;

        uint256 numVaults = vaults.length;
        for (uint256 i = 0; i < numVaults; ++i) {
            minDeposits += vaults[i].getPrincipalDeposits() - vaults[i].canWithdraw();
        }

        return minDeposits;
    }

    /**
     * @notice returns the available withdrawal room for this strategy
     * @return available withdrawal room
     */
    function canWithdraw() external view returns (uint256) {
        uint256 deposits = getTotalDeposits();
        if (deposits <= getMinDeposits()) {
            return 0;
        } else {
            return deposits - getMinDeposits();
        }
    }

    /**
     * @notice Returns the minimum that can be deposited into a vault
     * @return minimum vault deposit
     */
    function getVaultDepositMin() public view returns (uint256) {
        return lockingInfo.minLock();
    }

    /**
     * @notice Returns the maximum that can be deposited into a vault
     * @return maximum vault deposit
     */
    function getVaultDepositMax() public view returns (uint256) {
        return lockingInfo.maxLock();
    }

    /**
     * @notice Receives ETH transfers
     * @dev used when vaults transfer back unused fees
     */
    receive() external payable {}

    /**
     * @notice Deploys a new vault and adds it to this strategy
     * @param _pubkey public key of sequencer
     * @param _signer signer address of sequencer
     * @param _rewardsReceiver address authorized to claim rewards for the vault
     */
    function addVault(
        bytes calldata _pubkey,
        address _signer,
        address _rewardsReceiver
    ) external onlyOwner {
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address,address,bytes,address,address)",
            address(token),
            address(this),
            lockingInfo.manager(),
            address(lockingInfo),
            _pubkey,
            _signer,
            _rewardsReceiver
        );
        address vault = address(new ERC1967Proxy(vaultImplementation, data));

        token.safeApprove(vault, type(uint256).max);
        vaults.push(ISequencerVault(vault));

        emit VaultAdded(_signer);
    }

    /**
     * @notice Upgrades vaults to a new implementation contract
     * @param _vaults list of vault indexes to upgrade
     * @param _data list of encoded function calls to be executed for each vault after upgrade
     */
    function upgradeVaults(uint256[] calldata _vaults, bytes[] memory _data) external onlyOwner {
        for (uint256 i = 0; i < _vaults.length; ++i) {
            if (_data[i].length == 0) {
                vaults[_vaults[i]].upgradeTo(vaultImplementation);
            } else {
                vaults[_vaults[i]].upgradeToAndCall(vaultImplementation, _data[i]);
            }
        }
        emit UpgradedVaults(_vaults);
    }

    /**
     * @notice Sets a new vault implementation contract to be used when deploying/upgrading vaults
     * @param _vaultImplementation address of implementation contract
     */
    function setVaultImplementation(address _vaultImplementation) external onlyOwner {
        if (!_isContract(_vaultImplementation)) revert AddressNotContract();
        vaultImplementation = _vaultImplementation;
        emit SetVaultImplementation(_vaultImplementation);
    }

    /**
     * @notice Sets the basis point amount of an operator's earned rewards that they receive
     * @dev L2Transmitter::executeUpdate should be called on L2 right before calling this function
     * @param _operatorRewardPercentage basis point amount
     */
    function setOperatorRewardPercentage(uint256 _operatorRewardPercentage) public onlyOwner {
        if (_operatorRewardPercentage > 3000) revert FeesTooLarge();

        operatorRewardPercentage = _operatorRewardPercentage;
        emit SetOperatorRewardPercentage(_operatorRewardPercentage);
    }

    /**
     * @notice Sets the min amount of rewards required to relock/claim in vaults on a call to updateDeposits
     * (set 0 to skip reward claiming)
     * @param _minRewardsToClaim min amount of rewards
     **/
    function setMinRewardsToClaim(uint256 _minRewardsToClaim) external onlyOwner {
        minRewardsToClaim = _minRewardsToClaim;
    }

    /**
     * @notice Sets the address of the l1 transmitter
     * @param _l1Transmitter address of l1 transmitter
     */
    function setL1Transmitter(address _l1Transmitter) external onlyOwner {
        l1Transmitter = _l1Transmitter;
    }

    /**
     * @notice Returns whether an address belongs to a contract
     * @param _address address to check
     * @return true if address is contract, false otherwise
     */
    function _isContract(address _address) private view returns (bool) {
        uint256 length;
        assembly {
            length := extcodesize(_address)
        }
        return length > 0;
    }

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
