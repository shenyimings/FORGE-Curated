// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../@resolv/IResolvStaking.sol";
import "../../../@resolv/IStUSR.sol";
import "../../../@resolv/IStakedTokenDistributor.sol";
import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "./IP2pResolvProxy.sol";

error P2pResolvProxy__ZeroAddress_USR();
error P2pResolvProxy__AssetNotSupported(address _asset);
error P2pResolvProxy__UnauthorizedAccount(address _account);
error P2pResolvProxy__NotP2pOperator(address _caller);
error P2pResolvProxy__CallerNeitherClientNorP2pOperator(address _caller);
error P2pResolvProxy__ZeroAccruedRewards();
error P2pResolvProxy__UnsupportedAsset(address _asset);
error P2pResolvProxy__ZeroAddressStakedTokenDistributor();
error P2pResolvProxy__CannotSweepProtectedToken(address _token);
error P2pResolvProxy__RewardTokenLookupFailed(uint256 index);

contract P2pResolvProxy is P2pYieldProxy, IP2pResolvProxy {
    using SafeERC20 for IERC20;

    /// @dev USR address
    address internal immutable i_USR;

    /// @dev stUSR address
    address internal immutable i_stUSR;

    /// @dev RESOLV address
    address internal immutable i_RESOLV;

    /// @dev stRESOLV address
    address internal immutable i_stRESOLV;

    IStakedTokenDistributor private s_stakedTokenDistributor;

    // Tracks pending RESOLV rewards that arrived via StakedTokenDistributor claims.
    uint256 private s_pendingResolvRewardFromStakedTokenDistributor;

    /// @dev Throws if called by any account other than the P2pOperator.
    modifier onlyP2pOperator() {
        address p2pOperator = i_factory.getP2pOperator();
        require (msg.sender == p2pOperator, P2pResolvProxy__NotP2pOperator(msg.sender));
        _;
    }

    /// @dev Throws if called by any account other than client or P2pOperator.
    modifier onlyClientOrP2pOperator() {
        if (msg.sender != s_client) {
            address p2pOperator = i_factory.getP2pOperator();
            require (msg.sender == p2pOperator, P2pResolvProxy__CallerNeitherClientNorP2pOperator(msg.sender));
        }
        _;
    }

    /// @notice Constructor for P2pResolvProxy
    /// @param _factory Factory address
    /// @param _p2pTreasury P2pTreasury address
    /// @param _allowedCalldataChecker AllowedCalldataChecker
    /// @param _stUSR stUSR address
    /// @param _USR USR address
    /// @param _stRESOLV stRESOLV address
    /// @param _RESOLV RESOLV address
    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _stUSR,
        address _USR,
        address _stRESOLV,
        address _RESOLV
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker) {
        require(_USR != address(0), P2pResolvProxy__ZeroAddress_USR());
        i_USR = _USR;

        i_stUSR = _stUSR;

        i_RESOLV = _RESOLV;

        i_stRESOLV = _stRESOLV;
    }

    /// @inheritdoc IP2pYieldProxy
    function deposit(address _asset, uint256 _amount) external override onlyFactory {
        if (_asset == i_USR) {
            _deposit(
                i_stUSR,
                abi.encodeWithSelector(IStUSR.deposit.selector, _amount),
                i_USR,
                _amount
            );
        } else if (_asset == i_RESOLV) {
            _depositResolv(_amount);
        } else {
            revert P2pResolvProxy__AssetNotSupported(_asset);
        }
    }

    /// @inheritdoc IP2pResolvProxy
    function withdrawUSR(uint256 _amount)
    external
    onlyClient {
        require (_amount > 0, P2pYieldProxy__ZeroAssetAmount());
        uint256 currentBalance = IERC20(i_stUSR).balanceOf(address(this));
        if (_amount >= currentBalance || currentBalance - _amount <= 1) {
            _withdraw(
                i_stUSR,
                i_USR,
                abi.encodeCall(IStUSR.withdrawAll, ())
            );
            return;
        }
        _withdraw(
            i_stUSR,
            i_USR,
            abi.encodeWithSelector(IStUSR.withdraw.selector, _amount)
        );
    }

    function withdrawUSRAccruedRewards()
    external
    onlyP2pOperator {
        int256 amount = calculateAccruedRewardsUSR();
        require (amount > 0, P2pResolvProxy__ZeroAccruedRewards());
        _withdraw(
            i_stUSR,
            i_USR,
            abi.encodeWithSelector(IStUSR.withdraw.selector, amount),
            true
        );
    }

    /// @inheritdoc IP2pResolvProxy
    function withdrawAllUSR()
    external
    onlyClient {
        _withdraw(
            i_stUSR,
            i_USR,
            abi.encodeCall(IStUSR.withdrawAll, ())
        );
    }

    /// @inheritdoc IP2pResolvProxy
    function initiateWithdrawalRESOLV(uint256 _amount)
    external
    onlyClient {
        return IResolvStaking(i_stRESOLV).initiateWithdrawal(_amount);
    }

    /// @inheritdoc IP2pResolvProxy
    function withdrawRESOLV()
    external
    onlyClientOrP2pOperator
    nonReentrant
    {
        IResolvStaking staking = IResolvStaking(i_stRESOLV);
        uint256 pendingReward = s_pendingResolvRewardFromStakedTokenDistributor;

        if (pendingReward == 0) {
            staking.withdraw(false, s_client);
            emit P2pResolvProxy__ResolvPrincipalWithdrawal(msg.sender);
            return;
        }

        IERC20 resolvToken = IERC20(i_RESOLV);
        uint256 balanceBefore = resolvToken.balanceOf(address(this));
        staking.withdraw(false, address(this));
        uint256 balanceAfter = resolvToken.balanceOf(address(this));
        uint256 delta = balanceAfter - balanceBefore;

        s_pendingResolvRewardFromStakedTokenDistributor = 0;
        uint256 expectedReward = pendingReward;
        uint256 principalPortion = delta > expectedReward ? delta - expectedReward : 0;
        uint256 rewardPortion = delta - principalPortion;

        uint256 p2pAmount = calculateP2pFeeAmount(rewardPortion);
        uint256 clientRewardAmount = rewardPortion - p2pAmount;

        if (p2pAmount > 0) {
            resolvToken.safeTransfer(i_p2pTreasury, p2pAmount);
        }

        uint256 clientAmountToSend = clientRewardAmount + principalPortion;
        if (clientAmountToSend > 0) {
            resolvToken.safeTransfer(s_client, clientAmountToSend);
        }

        emit P2pResolvProxy__DistributorRewardsReleased(
            expectedReward,
            delta,
            p2pAmount,
            clientRewardAmount,
            principalPortion
        );
    }

    /// @inheritdoc IP2pResolvProxy
    function claimStakedTokenDistributor(
        uint256 _index,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    )
    external
    nonReentrant
    onlyClientOrP2pOperator
    {
        // claim _reward token from StakedTokenDistributor
        address stakedTokenDistributor = address(s_stakedTokenDistributor);
        require(
            stakedTokenDistributor != address(0),
            P2pResolvProxy__ZeroAddressStakedTokenDistributor()
        );

        IERC20 stResolv = IERC20(i_stRESOLV);
        uint256 sharesBefore = stResolv.balanceOf(address(this));
        IStakedTokenDistributor(stakedTokenDistributor).claim(_index, _amount, _merkleProof);
        uint256 claimedShares = stResolv.balanceOf(address(this)) - sharesBefore;
        require(claimedShares > 0, P2pYieldProxy__ZeroAssetAmount());

        s_pendingResolvRewardFromStakedTokenDistributor += claimedShares;
        emit P2pResolvProxy__Claimed(claimedShares);

        IResolvStaking(i_stRESOLV).initiateWithdrawal(claimedShares);
    }

    /// @inheritdoc IP2pResolvProxy
    function claimRewardTokens() external onlyClientOrP2pOperator nonReentrant {
        address[] memory rewardTokens = _getRewardTokens();
        uint256 tokenCount = rewardTokens.length;
        uint256[] memory balancesBefore = new uint256[](tokenCount);

        for (uint256 i; i < tokenCount; ++i) {
            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf(address(this));
        }

        IResolvStaking(i_stRESOLV).claim(address(this), address(this));

        for (uint256 i; i < tokenCount; ++i) {
            address tokenAddress = rewardTokens[i];
            IERC20 token = IERC20(tokenAddress);
            uint256 balanceAfter = token.balanceOf(address(this));
            uint256 delta = balanceAfter - balancesBefore[i];
            if (delta > 0) {
                uint256 p2pAmount = calculateP2pFeeAmount(delta);
                uint256 clientAmount = delta - p2pAmount;

                if (p2pAmount > 0) {
                    token.safeTransfer(i_p2pTreasury, p2pAmount);
                }

                if (clientAmount > 0) {
                    token.safeTransfer(s_client, clientAmount);
                }

                emit P2pResolvProxy__RewardTokensClaimed(
                    tokenAddress,
                    delta,
                    p2pAmount,
                    clientAmount
                );
            }
        }
    }

    /// @inheritdoc IP2pResolvProxy
    function sweepRewardToken(address _token) external onlyClientOrP2pOperator {
        // Prevent sweeping of protected assets that are handled by existing accounting
        if (_token == i_USR || _token == i_RESOLV || _token == i_stUSR || _token == i_stRESOLV) {
            revert P2pResolvProxy__CannotSweepProtectedToken(_token);
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(_token).safeTransfer(s_client, balance);
            emit P2pResolvProxy__RewardTokenSwept(_token, balance);
        }
    }

    function setStakedTokenDistributor(address _stakedTokenDistributor) external override onlyP2pOperator {
        require(_stakedTokenDistributor != address(0), P2pResolvProxy__ZeroAddressStakedTokenDistributor());
        address previousStakedTokenDistributor = address(s_stakedTokenDistributor);
        s_stakedTokenDistributor = IStakedTokenDistributor(_stakedTokenDistributor);

        emit P2pResolvProxy__StakedTokenDistributorUpdated(
            previousStakedTokenDistributor,
            _stakedTokenDistributor
        );
    }

    function getStakedTokenDistributor() public view override returns(address) {
        return address(s_stakedTokenDistributor);
    }

    function getUserPrincipalUSR() public view returns(uint256) {
        return getUserPrincipal(i_USR);
    }

    function getUserPrincipalRESOLV() public view returns(uint256) {
        return IERC20(i_stRESOLV).balanceOf(address(this));
    }

    function calculateAccruedRewardsUSR() public view returns(int256) {
        uint256 currentAmount = IERC20(i_stUSR).balanceOf(address(this));
        uint256 userPrincipal = getUserPrincipal(i_USR);
        return int256(currentAmount) - int256(userPrincipal);
    }

    function calculateAccruedRewardsRESOLV(address _token) public view returns(int256) {
        return int256(
            IResolvStaking(i_stRESOLV).getUserClaimableAmounts(address(this), _token)
        );
    }

    function getLastFeeCollectionTimeUSR() public view returns(uint48) {
        return getLastFeeCollectionTime(i_USR);
    }

    function getLastFeeCollectionTimeRESOLV() public view returns(uint48) {
        return getLastFeeCollectionTime(i_RESOLV);
    }

    function _depositResolv(uint256 _amount) internal {
        require(_amount > 0, P2pYieldProxy__ZeroAssetAmount());

        IERC20 resolvToken = IERC20(i_RESOLV);
        uint256 balanceBefore = resolvToken.balanceOf(address(this));
        resolvToken.safeTransferFrom(s_client, address(this), _amount);
        uint256 actualAmount = resolvToken.balanceOf(address(this)) - balanceBefore;

        require(
            actualAmount == _amount,
            P2pYieldProxy__DifferentActuallyDepositedAmount(_amount, actualAmount)
        );

        resolvToken.safeIncreaseAllowance(i_stRESOLV, actualAmount);
        IResolvStaking(i_stRESOLV).deposit(actualAmount, address(this));
        emit P2pResolvProxy__ResolvDeposited(actualAmount);
    }

    function _getCurrentAssetAmount(address _yieldProtocolAddress, address _asset) internal view override returns (uint256) {
        if (_asset == i_USR) {
            return IERC20(_yieldProtocolAddress).balanceOf(address(this));
        }

        revert P2pResolvProxy__UnsupportedAsset(_asset);
    }

    function _getRewardTokens() internal view returns (address[] memory tokens) {
        IResolvStaking staking = IResolvStaking(i_stRESOLV);
        tokens = new address[](4); // start small; will expand as needed
        uint256 count;

        while (true) {
            try staking.rewardTokens(count) returns (address token) {
                if (count == tokens.length) {
                    address[] memory expanded = new address[](tokens.length * 2);
                    for (uint256 j; j < tokens.length; ++j) {
                        expanded[j] = tokens[j];
                    }
                    tokens = expanded;
                }
                tokens[count] = token;
                ++count;
            } catch {
                break;
            }
        }

        assembly {
            mstore(tokens, count)
        }
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(P2pYieldProxy) returns (bool) {
        return interfaceId == type(IP2pResolvProxy).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
