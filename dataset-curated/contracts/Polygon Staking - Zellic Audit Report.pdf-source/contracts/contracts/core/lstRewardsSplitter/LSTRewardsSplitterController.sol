// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IERC677.sol";
import "../interfaces/ILSTRewardsSplitter.sol";
import "./LSTRewardsSplitter.sol";

/**
 * @title LST Rewards Splitter Controller
 * @notice Manages multiple LSTRewardsSplitters
 */
contract LSTRewardsSplitterController is Ownable {
    using SafeERC20 for IERC677;

    // mapping of account address to corresponding splitter
    mapping(address => ILSTRewardsSplitter) public splitters;
    // list of accounts that have splitters
    address[] internal accounts;

    // address of liquid staking token
    address public lst;
    // min amount of new rewards required to split
    uint256 public rewardThreshold;

    error InvalidToken();
    error SenderNotAuthorized();
    error InvalidPerformData();
    error SplitterAlreadyExists();
    error SplitterNotFound();

    /**
     * @notice Initializes contract
     * @param _lst address of liquid staking token
     * @param _rewardThreshold min amount of new rewards required to split
     */
    constructor(address _lst, uint256 _rewardThreshold) {
        lst = _lst;
        rewardThreshold = _rewardThreshold;
    }

    /**
     * @notice Returns a list of all accounts
     * @return list of accounts
     */
    function getAccounts() external view returns (address[] memory) {
        return accounts;
    }

    /**
     * @notice ERC677 implementation to receive an LST deposit
     **/
    function onTokenTransfer(address _sender, uint256 _value, bytes calldata) external {
        if (msg.sender != lst) revert InvalidToken();
        if (address(splitters[_sender]) == address(0)) revert SenderNotAuthorized();

        splitters[_sender].deposit(_value);
    }

    /**
     * @notice Withdraws tokens
     * @param _amount amount to withdraw
     */
    function withdraw(uint256 _amount) external {
        if (address(splitters[msg.sender]) == address(0)) revert SenderNotAuthorized();
        splitters[msg.sender].withdraw(_amount, msg.sender);
    }

    /**
     * @notice Returns whether a call should be made to performUpkeep to split new rewards
     * @return upkeepNeeded true if performUpkeep should be called, false otherwise
     * @return performData abi encoded list of splitters to call
     */
    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        bool[] memory splittersToCall = new bool[](accounts.length);
        bool overallUpkeepNeeded;

        for (uint256 i = 0; i < splittersToCall.length; ++i) {
            (bool upkeepNeeded, ) = splitters[accounts[i]].checkUpkeep("");
            splittersToCall[i] = upkeepNeeded;
            if (upkeepNeeded) overallUpkeepNeeded = true;
        }

        return (overallUpkeepNeeded, abi.encode(splittersToCall));
    }

    /**
     * @notice splits new rewards between receivers
     * @param _performData abi encoded list of splitters to call
     */
    function performUpkeep(bytes calldata _performData) external {
        bool[] memory splittersToCall = abi.decode(_performData, (bool[]));
        bool splitterCalled;

        for (uint256 i = 0; i < splittersToCall.length; ++i) {
            if (splittersToCall[i] == true) {
                splitters[accounts[i]].performUpkeep("");
                splitterCalled = true;
            }
        }

        if (splitterCalled == false) {
            revert InvalidPerformData();
        }
    }

    /**
     * @notice Deploys a new splitter
     * @param _account address of account to deploy splitter for
     * @param _fees list of splitter fees
     */
    function addSplitter(
        address _account,
        LSTRewardsSplitter.Fee[] memory _fees
    ) external onlyOwner {
        if (address(splitters[_account]) != address(0)) revert SplitterAlreadyExists();

        address splitter = address(new LSTRewardsSplitter(lst, _fees, owner()));
        splitters[_account] = ILSTRewardsSplitter(splitter);
        accounts.push(_account);
        IERC677(lst).safeApprove(splitter, type(uint256).max);
    }

    /**
     * @notice Removes an account's splitter
     * @param _account address of account
     **/
    function removeSplitter(address _account) external onlyOwner {
        ILSTRewardsSplitter splitter = splitters[_account];
        if (address(splitter) == address(0)) revert SplitterNotFound();

        uint256 balance = IERC20(lst).balanceOf(address(splitter));
        uint256 principalDeposits = splitter.principalDeposits();
        if (balance != 0) {
            if (balance != principalDeposits) splitter.splitRewards();
            splitter.withdraw(splitter.principalDeposits(), _account);
        }

        delete splitters[_account];

        uint256 numAccounts = accounts.length;
        for (uint256 i = 0; i < numAccounts; ++i) {
            if (accounts[i] == _account) {
                accounts[i] = accounts[numAccounts - 1];
                accounts.pop();
                break;
            }
        }

        IERC677(lst).safeApprove(address(splitter), 0);
    }

    /**
     * @notice Sets the reward threshold
     * @param _rewardThreshold min amount of new rewards required to split
     */
    function setRewardThreshold(uint256 _rewardThreshold) external onlyOwner {
        rewardThreshold = _rewardThreshold;
    }
}
