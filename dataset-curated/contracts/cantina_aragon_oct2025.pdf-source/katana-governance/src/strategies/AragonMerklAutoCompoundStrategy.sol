// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC721HolderUpgradeable as ERC721Holder } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { VotingEscrow, GaugeVoter, EscrowIVotesAdapter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";

import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { Swapper } from "src/Swapper.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";
import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";
import { IStrategyNFT } from "src/interfaces/IStrategyNFT.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { NFTBaseStrategy } from "../abstracts/NFTBaseStrategy.sol";

contract AragonMerklAutoCompoundStrategy is
    Initializable,
    ERC721Holder,
    UUPSUpgradeable,
    DaoAuthorizable,
    NFTBaseStrategy
{
    using SafeERC20 for IERC20;

    ///@notice The bytes32 identifier for admin role functions.
    bytes32 public constant AUTOCOMPOUND_STRATEGY_ADMIN_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_ADMIN_ROLE");

    ///@notice The bytes32 identifier for vote function.
    bytes32 public constant AUTOCOMPOUND_STRATEGY_VOTE_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_VOTE_ROLE");

    ///@notice The bytes32 identifier for claimAndCompound function.
    bytes32 public constant AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE =
        keccak256("AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE");

    /// @notice The gauge voter where this contract votes for gauges.
    GaugeVoter public voter;

    /// @notice The vault address where this contract auto-compounds(deposits kat).
    AvKATVault public vault;

    /// @notice The swapper contract which this contract asks for claiming tokens.
    Swapper public swapper;

    /// @notice The ivotes adapter for delegation
    EscrowIVotesAdapter public ivotesAdapter;

    /// @notice The address that this strategy delegates voting power to.
    address public delegatee;

    /// @notice Emitted when the admin withdraws mistakenly withdraws token ids.
    event Sweep(uint256[] tokenIds, address receiver);

    /// @notice Thrown when the admin tries to withdraw master token id.
    error CannotTransferMasterToken();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dao,
        address _escrow,
        address _swapper,
        address _vault,
        address _rewardDistributor
    )
        external
        initializer
    {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));

        ivotesAdapter = EscrowIVotesAdapter(VotingEscrow(_escrow).ivotesAdapter());
        voter = GaugeVoter(VotingEscrow(_escrow).voter());
        swapper = Swapper(_swapper);
        vault = AvKATVault(_vault);

        __NFTBaseStrategy_init(_escrow, VotingEscrow(_escrow).token(), VotingEscrow(_escrow).lockNFT(), _vault);

        // As the caller on distributor's `claim` function will be swapper,
        // it can only work if this contract allowed swapper to claim on behalf.
        IRewardsDistributor(_rewardDistributor).toggleOperator(address(this), _swapper);
    }

    /// @notice Sets the delegatee address for voting power delegation.
    /// @param _delegatee The address to delegate voting power to.
    function delegate(address _delegatee) public virtual auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) {
        delegatee = _delegatee;
        if (_delegatee != address(0)) {
            ivotesAdapter.delegate(_delegatee);
        }
    }

    /// @notice Claims and swaps token. If claimed amount for `token` is > 0,
    ///         it donates(i.e increases totalAssets) without minting shares.
    /// @param _tokens Which tokens to claim.
    /// @param _amounts How much to claim for each token.
    /// @param _proofs The merkle proof that this contract holds `_amounts` on merkle distributor.
    /// @param _actions The actions that Swapper contract executes. Most times, it will be swap actions.
    /// @return Returns shares that were minted in exchange for depositting kat tokens.
    function claimAndCompound(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs,
        Action[] calldata _actions
    )
        public
        virtual
        auth(AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE)
        returns (uint256)
    {
        // which tokens to claim for with their proofs and amounts.
        ISwapper.Claim memory claimTokens = ISwapper.Claim(_tokens, _amounts, _proofs);

        (uint256 claimedAmount,) = swapper.claimAndSwap(claimTokens, _actions, 0);

        // If claimedAmount is greater than 0, autocompound received some amounts on `token`.
        // Donate to vault to increase totalAssets without minting shares.
        // This increases the value of all existing shares proportionally.
        if (claimedAmount > 0) {
            _deposit(claimedAmount);
        }

        return claimedAmount;
    }

    /// @notice Votes on gauge voter with `_votes`.
    /// @dev The caller must invoke `delegate` with this strategy’s address, effectively delegating to itself.
    /// @param _votes The gauges and their weights to vote for.
    function vote(GaugeVoter.GaugeVote[] calldata _votes) external virtual auth(AUTOCOMPOUND_STRATEGY_VOTE_ROLE) {
        voter.vote(_votes);
    }

    /// @notice Allows the admin to withdraw specified token IDs, provided none are the master token.
    /// @dev This allows to withdraw tokens that have been mistakenly transfered to strategy contract.
    /// @param _tokenIds The token IDs to withdraw. All IDs must currently be held by this strategy.
    /// @param _receiver The address that will receive the NFTs.
    function withdrawTokens(
        uint256[] memory _tokenIds,
        address _receiver
    )
        external
        virtual
        auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (tokenId == masterTokenId) {
                revert CannotTransferMasterToken();
            }

            nft.safeTransferFrom(address(this), _receiver, tokenId);
        }

        emit Sweep(_tokenIds, _receiver);
    }

    /// @inheritdoc IStrategy
    function retireStrategy() public virtual override {
        // For safety reasons, revoke current delegatee
        ivotesAdapter.delegate(address(0));

        super.retireStrategy();
    }

    /*//////////////////////////////////////////////////////////////
                        Upgrade
    //////////////////////////////////////////////////////////////*/
    function _authorizeUpgrade(address) internal virtual override auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[45] private __gap;
}
