// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./interfaces/IStakingPool.sol";
import "./interfaces/IPriorityPool.sol";
import "./interfaces/IWithdrawalPool.sol";
import "./interfaces/IERC677.sol";
import "./interfaces/ISDLPool.sol";

/**
 * @title Staking Proxy
 * @notice Enables a staker to deposit tokens and earn rewards without ever directly interacting with the LST contracts
 * @dev When tokens are queued for deposit, the corresponding liquid staking tokens will be distributed using a merkle
 * tree. The tree is updated once a certain threshold of LSTs is reached at which point LSTs can be claimed. In order
 * for this contract to claim its LSTs (and execute some other funcion calls), merkle data must be passed as an argument.
 * This data is stored on IPFS at the hash which can be queried from this contract. For some functions, this data can be
 * used as is but for ones that require a merkle proof, a merkle tree must be generated using the IPFS data, then a merkle
 * proof generated using the tree.
 * @dev Data may or may not need to be passed when depositing and/or withdrawing depending on the underlying LST implementation.
 * If data does need to be passed, it will need to be fetched from an external source specific to that LST.
 */
contract StakingProxy is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of asset token
    IERC20Upgradeable public token;
    // address of liquid staking token
    IStakingPool public lst;
    // address of priority pool
    IPriorityPool public priorityPool;
    // address of withdrawal pool
    IWithdrawalPool public withdrawalPool;
    // address of SDL pool
    ISDLPool public sdlPool;

    // address authorized to deposit/withdraw asset tokens
    address public staker;

    error SenderNotAuthorized();
    error InvalidToken();
    error InvalidValue();
    error InvalidTokenId();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _token address of asset token
     * @param _lst address of liquid staking token
     * @param _priorityPool address of priority pool
     * @param _withdrawalPool address of withdrawal pool
     * @param _sdlPool address of SDL pool
     * @param _staker address authorized to deposit/withdraw asset tokens
     */
    function initialize(
        address _token,
        address _lst,
        address _priorityPool,
        address _withdrawalPool,
        address _sdlPool,
        address _staker
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        token = IERC20Upgradeable(_token);
        lst = IStakingPool(_lst);
        priorityPool = IPriorityPool(_priorityPool);
        token.safeApprove(_priorityPool, type(uint256).max);
        IERC20Upgradeable(_lst).safeApprove(_priorityPool, type(uint256).max);
        withdrawalPool = IWithdrawalPool(_withdrawalPool);
        sdlPool = ISDLPool(_sdlPool);
        staker = _staker;
    }

    /**
     * @notice Reverts if sender is not staker
     */
    modifier onlyStaker() {
        if (msg.sender != staker) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Returns the IPFS hash of the current merkle distribution tree
     * @dev returns CIDv0 with no prefix - prefix must be added and hash must be properly encoded offchain
     * @return IPFS hash
     */
    function getMerkleIPFSHash() external view returns (bytes32) {
        return priorityPool.ipfsHash();
    }

    /**
     * @notice Returns the total amount of liquid staking tokens held by this contract
     * @dev excludes unclaimed LSTs sitting in the priority pool
     * @return total LSTs held by contract
     */
    function getTotalDeposits() external view returns (uint256) {
        return lst.balanceOf(address(this));
    }

    /**
     * @notice Returns the total amount of tokens queued for deposit into the staking pool by this contract
     * @param _distributionAmount amount as recorded in this contract's merkle tree entry (stored on IPFS)
     * @return total tokens queued for deposit
     */
    function getTotalQueuedForDeposit(uint256 _distributionAmount) external view returns (uint256) {
        return priorityPool.getQueuedTokens(address(this), _distributionAmount);
    }

    /**
     * @notice Returns the total amount of tokens queued for withdrawal from the staking pool by this contract
     * @return total tokens queued for withdrawal
     */
    function getTotalQueuedForWithdrawal() external view returns (uint256) {
        return withdrawalPool.getAccountTotalQueuedWithdrawals(address(this));
    }

    /**
     * @notice Returns the total amount of withdrawable tokens for this contract
     * @param _distributionAmount amount as recorded in this contract's merkle tree entry (stored on IPFS)
     * @return total amount withdrawable from the priority pool
     * @return total amount withdrawable from the withdrawal pool
     * @return withdrawal ids for withdrawal from withdrawal pool
     * @return batch ids for withdrawal from withdrawal pool
     */
    function getTotalWithdrawable(
        uint256 _distributionAmount
    ) external view returns (uint256, uint256, uint256[] memory, uint256[] memory) {
        (uint256[] memory withdrawalIds, uint256 withdrawable) = withdrawalPool
            .getFinalizedWithdrawalIdsByOwner(address(this));
        uint256[] memory batchIds = withdrawalPool.getBatchIds(withdrawalIds);

        uint256 priorityPoolCanWithdraw = priorityPool.canWithdraw(
            address(this),
            _distributionAmount
        );

        return (priorityPoolCanWithdraw, withdrawable, withdrawalIds, batchIds);
    }

    /**
     * @notice Returns the total amount of claimable liquid staking tokens for this contract
     * @param _distributionSharesAmount shares amount as recorded in this contract's merkle tree entry (stored on IPFS)
     * @return total claimable LSTs
     */
    function getTotalClaimableLSTs(
        uint256 _distributionSharesAmount
    ) external view returns (uint256) {
        return priorityPool.getLSDTokens(address(this), _distributionSharesAmount);
    }

    /**
     * @notice ERC677 implementation to receive deposits
     * @param _sender address of sender
     * @param _value value of transfer
     * @param _calldata encoded deposit data
     */
    function onTokenTransfer(address _sender, uint256 _value, bytes calldata _calldata) external {
        if (msg.sender != address(token)) revert InvalidToken();
        if (_sender != staker) revert SenderNotAuthorized();
        if (_value == 0) revert InvalidValue();

        bytes[] memory data = abi.decode(_calldata, (bytes[]));
        IERC677(address(token)).transferAndCall(
            address(priorityPool),
            _value,
            abi.encode(true, data)
        );
    }

    /**
     * @notice Deposits tokens and/or queues tokens for deposit into the staking pool
     * @param _amount amount of tokens to deposit
     * @param _data encoded deposit data
     */
    function deposit(uint256 _amount, bytes[] calldata _data) external onlyStaker {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        priorityPool.deposit(_amount, true, _data);
    }

    /**
     * @notice Withdraws tokens and/or queues tokens for withdrawal from the staking pool
     * @dev if there is any amount withdrawable from the withdrawal pool, the entire amount will be withdrawn
     * even if it exceeds _amountToWithdraw
     * @param _amountToWithdraw amount of tokens to withdraw
     * @param _distributionAmount amount as recorded in this contract's merkle tree entry (stored on IPFS)
     * @param _distributionSharesAmount shares amount as recorded in this contract's merkle tree entry (stored on IPFS)
     * @param _merkleProof merkle proof for this contract's merkle tree entry (generated using IPFS data)
     * @param _withdrawalIds list of withdrawal ids required if finalizing queued withdrawals
     * @param _batchIds list of batch ids required if finalizing queued withdrawals
     * @param _data encoded withdrawal data
     */
    function withdraw(
        uint256 _amountToWithdraw,
        uint256 _distributionAmount,
        uint256 _distributionSharesAmount,
        bytes32[] calldata _merkleProof,
        uint256[] calldata _withdrawalIds,
        uint256[] calldata _batchIds,
        bytes[] calldata _data
    ) external onlyStaker {
        uint256 availableTokens;

        if (_withdrawalIds.length != 0) {
            withdrawalPool.withdraw(_withdrawalIds, _batchIds);
            availableTokens = token.balanceOf(address(this));
        }

        if (availableTokens < _amountToWithdraw) {
            priorityPool.withdraw(
                _amountToWithdraw - availableTokens,
                _distributionAmount,
                _distributionSharesAmount,
                _merkleProof,
                true,
                true,
                _data
            );
            availableTokens = token.balanceOf(address(this));
        }

        token.safeTransfer(msg.sender, availableTokens);
    }

    /**
     * @notice Claims liquid staking tokens from the priority pool
     * @param _amount amount as recorded in this contract's merkle tree entry (stored on IPFS)
     * @param _sharesAmount shares amount as recorded in this contract's merkle tree entry (stored on IPFS)
     * @param _merkleProof merkle proof for this contract's merkle tree entry (generated from IPFS data)
     */
    function claimLSTs(
        uint256 _amount,
        uint256 _sharesAmount,
        bytes32[] calldata _merkleProof
    ) external {
        priorityPool.claimLSDTokens(_amount, _sharesAmount, _merkleProof);
    }

    /**
     * @notice Returns a list of reSDL token ids held by this contract
     * @return list of token ids
     */
    function getRESDLTokenIds() external view returns (uint256[] memory) {
        return sdlPool.getLockIdsByOwner(address(this));
    }

    /**
     * @notice Called when an reSDL token is transferred to this contract using safeTransfer
     */
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice Withdraws an reSDL token
     * @param _tokenId id of token
     * @param _receiver address to receive token
     */
    function withdrawRESDLToken(uint256 _tokenId, address _receiver) external onlyOwner {
        if (sdlPool.ownerOf(_tokenId) != address(this)) revert InvalidTokenId();
        IERC721(address(sdlPool)).safeTransferFrom(address(this), _receiver, _tokenId);
    }

    /**
     * @notice Claims rewards from the SDL Pool
     * @dev rewards will be redistributed to the SDL Pool
     * @dev this contract will be redistrubuted some of its own rewards
     * @param _tokens list of tokens to claim rewards for
     */
    function claimRESDLRewards(address[] calldata _tokens) external {
        sdlPool.withdrawRewards(_tokens);
        for (uint256 i = 0; i < _tokens.length; ++i) {
            uint256 balance = IERC20Upgradeable(_tokens[i]).balanceOf(address(this));
            if (balance != 0) {
                IERC20Upgradeable(_tokens[i]).safeTransfer(address(sdlPool), balance);
            }
        }
        sdlPool.distributeTokens(_tokens);
    }

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
