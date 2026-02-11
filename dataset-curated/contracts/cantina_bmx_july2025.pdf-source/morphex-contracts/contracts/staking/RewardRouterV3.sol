// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouterV2.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IGlpManager.sol";
import "../access/Governable.sol";

contract RewardRouterV3 is IRewardRouterV2, ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public glp; // BMX Liquidity Provider token

    address public override stakedGlpTracker;
    address public override feeGlpTracker;

    address public glpManager;

    mapping (address => address) public pendingReceivers;

    event StakeGlp(address account, uint256 amount);
    event UnstakeGlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _glp,
        address _feeGlpTracker,
        address _stakedGlpTracker,
        address _glpManager
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;
        weth = _weth;
        glp = _glp;
        feeGlpTracker = _feeGlpTracker;
        stakedGlpTracker = _stakedGlpTracker;
        glpManager = _glpManager;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 glpAmount = IGlpManager(glpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdg, _minGlp);
        IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        IRewardTracker(stakedGlpTracker).stakeForAccount(account, account, feeGlpTracker, glpAmount);

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(glpManager, msg.value);

        address account = msg.sender;
        uint256 glpAmount = IGlpManager(glpManager).addLiquidityForAccount(address(this), account, weth, msg.value, _minUsdg, _minGlp);

        IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        IRewardTracker(stakedGlpTracker).stakeForAccount(account, account, feeGlpTracker, glpAmount);

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        IRewardTracker(stakedGlpTracker).unstakeForAccount(account, feeGlpTracker, _glpAmount, account);
        IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        uint256 amountOut = IGlpManager(glpManager).removeLiquidityForAccount(account, _tokenOut, _glpAmount, _minOut, _receiver);

        emit UnstakeGlp(account, _glpAmount);

        return amountOut;
    }

    function unstakeAndRedeemGlpETH(uint256 _glpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        IRewardTracker(stakedGlpTracker).unstakeForAccount(account, feeGlpTracker, _glpAmount, account);
        IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        uint256 amountOut = IGlpManager(glpManager).removeLiquidityForAccount(account, weth, _glpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeGlp(account, _glpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeGlpTracker).claimForAccount(account, account);
        IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeGlpTracker).claimForAccount(account, account);
    }

    function handleRewards(
        bool _shouldClaimBmx,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 bmxAmount = 0;
        if (_shouldClaimBmx) {
            uint256 amount = IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
            bmxAmount = bmxAmount.add(amount);
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 wethAmount = IRewardTracker(feeGlpTracker).claimForAccount(account, address(this));

                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeGlpTracker).claimForAccount(account, account);
            }
        }
    }
}
