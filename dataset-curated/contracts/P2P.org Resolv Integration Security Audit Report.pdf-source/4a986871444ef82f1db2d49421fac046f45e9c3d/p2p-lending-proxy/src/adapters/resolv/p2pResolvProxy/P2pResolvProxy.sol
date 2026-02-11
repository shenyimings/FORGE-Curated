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

    IStakedTokenDistributor private immutable i_stakedTokenDistributor;

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
    /// @param _stakedTokenDistributor StakedTokenDistributor
    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _stUSR,
        address _USR,
        address _stRESOLV,
        address _RESOLV,
        address _stakedTokenDistributor
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker) {
        require(_USR != address(0), P2pResolvProxy__ZeroAddress_USR());
        i_USR = _USR;

        i_stUSR = _stUSR;

        i_RESOLV = _RESOLV;

        i_stRESOLV = _stRESOLV;

        i_stakedTokenDistributor = IStakedTokenDistributor(_stakedTokenDistributor);
    }

    /// @inheritdoc IP2pYieldProxy
    function deposit(address _asset, uint256 _amount) external override {
        if (_asset == i_USR) {
            _deposit(
                i_stUSR,
                abi.encodeWithSelector(IStUSR.deposit.selector, _amount),
                i_USR,
                _amount
            );
        } else if (_asset == i_RESOLV) {
            _deposit(
                i_stRESOLV,
                abi.encodeWithSelector(IResolvStaking.deposit.selector, _amount, address(this)),
                i_RESOLV,
                _amount
            );
        } else {
            revert P2pResolvProxy__AssetNotSupported(_asset);
        }
    }

    /// @inheritdoc IP2pResolvProxy
    function withdrawUSR(uint256 _amount)
    external
    onlyClient {
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
            abi.encodeWithSelector(IStUSR.withdraw.selector, amount)
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

    function initiateWithdrawalRESOLVAccruedRewards()
    external
    onlyP2pOperator {
        int256 amount = calculateAccruedRewardsRESOLV();
        require (amount > 0, P2pResolvProxy__ZeroAccruedRewards());
        return IResolvStaking(i_stRESOLV).initiateWithdrawal(uint256(amount));
    }

    /// @inheritdoc IP2pResolvProxy
    function withdrawRESOLV()
    external
    onlyClientOrP2pOperator {
        bool isEnabled = IResolvStaking(i_stRESOLV).claimEnabled();

        _withdraw(
            i_stRESOLV,
            i_RESOLV,
            abi.encodeWithSelector(IResolvStaking.withdraw.selector, isEnabled, address(this))
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
    {
        if (msg.sender != s_client) {
            address p2pOperator = i_factory.getP2pOperator();
            require(
                msg.sender == p2pOperator,
                P2pResolvProxy__UnauthorizedAccount(msg.sender)
            );
        }

        // claim _reward token from StakedTokenDistributor
        i_stakedTokenDistributor.claim(_index, _amount, _merkleProof);

        emit P2pResolvProxy__Claimed(_amount);
    }

    function getUserPrincipalUSR() public view returns(uint256) {
        return getUserPrincipal(i_USR);
    }

    function getUserPrincipalRESOLV() public view returns(uint256) {
        return getUserPrincipal(i_RESOLV);
    }

    function calculateAccruedRewardsUSR() public view returns(int256) {
        return calculateAccruedRewards(i_stUSR,i_USR);
    }

    function calculateAccruedRewardsRESOLV() public view returns(int256) {
        return calculateAccruedRewards(i_stRESOLV,i_RESOLV);
    }

    function getLastFeeCollectionTimeUSR() public view returns(uint48) {
        return getLastFeeCollectionTime(i_USR);
    }

    function getLastFeeCollectionTimeRESOLV() public view returns(uint48) {
        return getLastFeeCollectionTime(i_RESOLV);
    }

    function _getCurrentAssetAmount(address _yieldProtocolAddress, address _asset) internal view override returns (uint256) {
        if (_asset == i_RESOLV) {
            uint256 pendingClaimable = IResolvStaking(_yieldProtocolAddress).getUserClaimableAmounts(address(this), i_RESOLV);
            return getUserPrincipal(_asset) + pendingClaimable;
        }

        if (_asset == i_USR) {
            return IERC20(_yieldProtocolAddress).balanceOf(address(this));
        }

        revert P2pResolvProxy__UnsupportedAsset(_asset);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(P2pYieldProxy) returns (bool) {
        return interfaceId == type(IP2pResolvProxy).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
