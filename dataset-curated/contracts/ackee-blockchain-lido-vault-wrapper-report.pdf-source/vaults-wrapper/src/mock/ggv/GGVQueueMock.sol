// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BorrowedMath} from "./BorrowedMath.sol";
import {GGVVaultMock} from "./GGVVaultMock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IStETH} from "src/interfaces/core/IStETH.sol";
import {IWstETH} from "src/interfaces/core/IWstETH.sol";
import {IBoringOnChainQueue} from "src/interfaces/ggv/IBoringOnChainQueue.sol";

contract GGVQueueMock is IBoringOnChainQueue {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    uint256 internal immutable ONE_SHARE;
    GGVVaultMock internal immutable _VAULT;
    IStETH public immutable STETH;
    IWstETH public immutable WSTETH;

    address public _owner;

    EnumerableSet.Bytes32Set private _withdrawRequests;
    uint96 public nonce = 1;
    mapping(address assetOut => WithdrawAsset) public _withdrawAssets;
    mapping(bytes32 requestId => OnChainWithdraw) internal _helper_requestsById;

    event OnChainWithdrawRequested(
        bytes32 indexed requestId,
        address indexed user,
        address indexed assetOut,
        uint96 nonce,
        uint128 amountOfShares,
        uint128 amountOfAssets,
        uint40 creationTime,
        uint24 secondsToMaturity,
        uint24 secondsToDeadline
    );

    constructor(address __vault, address _steth, address _wsteth, address __owner) {
        _owner = __owner;
        _VAULT = GGVVaultMock(__vault);
        STETH = IStETH(_steth);
        WSTETH = IWstETH(_wsteth);
        ONE_SHARE = 10 ** 18;

        // allow withdraws for steth by default
        _updateWithdrawAsset(_steth, 0, 0, 0, 500, 100);
        _updateWithdrawAsset(_wsteth, 0, 0, 0, 500, 100);
    }

    function changeOwner(address newOwner) external {
        if (msg.sender != _owner) {
            revert("Sender is not an owner");
        }
        _owner = newOwner;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function authority() external view returns (address) {
        return _owner;
    }

    function boringVault() external view returns (address) {
        return address(_VAULT);
    }

    function accountant() external view returns (address) {
        return address(this);
    }

    function withdrawAssets(address assetOut) external view returns (WithdrawAsset memory) {
        return _withdrawAssets[assetOut];
    }

    function updateWithdrawAsset(
        address assetOut,
        uint24 secondsToMaturity,
        uint24 minimumSecondsToDeadline,
        uint16 minDiscount,
        uint16 maxDiscount,
        uint96 minimumShares
    ) external {
        require(msg.sender == _owner, "Only owner can update withdraw asset");
        _updateWithdrawAsset(
            assetOut, secondsToMaturity, minimumSecondsToDeadline, minDiscount, maxDiscount, minimumShares
        );
    }

    function setWithdrawCapacity(address assetOut, uint256 withdrawCapacity) external {
        require(msg.sender == _owner, "Only owner can update withdraw asset");
        _withdrawAssets[assetOut].withdrawCapacity = withdrawCapacity;
    }

    function requestOnChainWithdraw(
        address _assetOut,
        uint128 amountOfShares,
        uint16 discount,
        uint24 secondsToDeadline
    ) external returns (bytes32 requestId) {
        WithdrawAsset memory withdrawAsset = _withdrawAssets[_assetOut];
        _beforeNewRequest(withdrawAsset, amountOfShares, discount, secondsToDeadline);

        // hardcode for steth only
        if (_assetOut != address(STETH) && _assetOut != address(WSTETH)) {
            revert("Only steth and wsteth supported");
        }

        ERC20 assetOut = ERC20(_assetOut);

        uint128 amountOfAssets = uint128(_VAULT.getAssetsByShares(amountOfShares));
        if (amountOfAssets > assetOut.balanceOf(address(_VAULT))) {
            revert("Not enough assets in vault");
        }

        // needs approval
        require(_VAULT.transferFrom(msg.sender, address(this), amountOfShares), "Transfer failed");

        uint96 requestNonce;
        // See nonce definition for unchecked safety.
        unchecked {
            // Set request nonce as current nonce, then increment nonce.
            requestNonce = nonce++;
        }

        uint128 amountOfAssets128 = previewAssetsOut(_assetOut, amountOfShares, discount);

        uint40 timeNow = uint40(block.timestamp); // Safe to cast to uint40 as it won't overflow for 10s of thousands of years
        OnChainWithdraw memory req = OnChainWithdraw({
            nonce: requestNonce,
            user: msg.sender,
            assetOut: _assetOut,
            amountOfShares: amountOfShares,
            amountOfAssets: amountOfAssets128,
            creationTime: timeNow,
            secondsToMaturity: withdrawAsset.secondsToMaturity,
            secondsToDeadline: secondsToDeadline
        });

        requestId = keccak256(abi.encode(req));

        // write to onchain storage for easier tests
        _helper_requestsById[requestId] = req;

        _withdrawRequests.add(requestId);
        nonce++;

        _decrementWithdrawCapacity(_assetOut, amountOfShares);

        emit OnChainWithdrawRequested(
            requestId,
            msg.sender,
            _assetOut,
            requestNonce,
            amountOfShares,
            amountOfAssets128,
            timeNow,
            withdrawAsset.secondsToMaturity,
            secondsToDeadline
        );

        return requestId;
    }

    function getRequestIds() external view returns (bytes32[] memory) {
        return _withdrawRequests.values();
    }

    function mockGetRequestById(bytes32 requestId) external view returns (OnChainWithdraw memory) {
        return _helper_requestsById[requestId];
    }

    function solveOnChainWithdraws(OnChainWithdraw[] calldata requests, bytes calldata, address) external {
        ERC20 solveAsset = ERC20(requests[0].assetOut);
        uint256 requiredAssets;
        uint256 totalShares;
        uint256 requestsLength = requests.length;
        for (uint256 i = 0; i < requestsLength; ++i) {
            if (address(solveAsset) != requests[i].assetOut) revert("solve asset mismatch");
            uint256 maturity = requests[i].creationTime + requests[i].secondsToMaturity;
            if (block.timestamp < maturity) revert("not matured");
            uint256 deadline = maturity + requests[i].secondsToDeadline;
            if (block.timestamp > deadline) revert("deadline passed");
            requiredAssets += requests[i].amountOfAssets;
            totalShares += requests[i].amountOfShares;
            _dequeueOnChainWithdraw(requests[i]);
            //emit OnChainWithdrawSolved(requestId, requests[i].user, block.timestamp);
            _VAULT.burnSharesReturnAssets(
                solveAsset, requests[i].amountOfShares, requests[i].amountOfAssets, requests[i].user
            );
        }
    }

    function cancelOnChainWithdraw(OnChainWithdraw memory request) external returns (bytes32 requestId) {
        require(msg.sender == request.user, "Only request creator can cancel");
        requestId = _dequeueOnChainWithdraw(request);
        _incrementWithdrawCapacity(request.assetOut, request.amountOfShares);
        require(_VAULT.transfer(request.user, request.amountOfShares));
    }

    function previewAssetsOut(address assetOut, uint128 amountOfShares, uint16 discount)
        public
        view
        returns (uint128 amountOfAssets128)
    {
        if (assetOut != address(STETH) && assetOut != address(WSTETH)) {
            revert("Only steth and wsteth supported");
        }

        uint256 amountOfAssets = _VAULT.getAssetsByShares(amountOfShares);
        // discount
        amountOfAssets = BorrowedMath.mulDivDown(amountOfAssets, 1e4 - discount, 1e4);

        uint256 amountOfTokens;
        if (assetOut == address(STETH)) {
            amountOfTokens = STETH.getPooledEthByShares(amountOfAssets);
        } else {
            amountOfTokens = amountOfAssets;
        }

        if (amountOfTokens > type(uint128).max) revert("overflow");

        amountOfAssets128 = amountOfTokens.toUint128();
    }

    event NonPure();

    function replaceOnChainWithdraw(OnChainWithdraw memory, uint16, uint24) external returns (bytes32, bytes32) {
        emit NonPure();
        revert("not implemented");
    }

    function _beforeNewRequest(
        WithdrawAsset memory withdrawAsset,
        uint128 amountOfShares,
        uint16 discount,
        uint24 secondsToDeadline
    ) internal view virtual {
        if (!withdrawAsset.allowWithdraws) revert("Withdraws not allowed");
        if (discount < withdrawAsset.minDiscount || discount > withdrawAsset.maxDiscount) {
            revert("Bad discount");
        }
        if (amountOfShares < withdrawAsset.minimumShares) revert("Bad share amount");
        if (secondsToDeadline < withdrawAsset.minimumSecondsToDeadline) revert("Bad deadline");
    }

    function _decrementWithdrawCapacity(address assetOut, uint256 amountOfShares) internal {
        WithdrawAsset storage withdrawAsset = _withdrawAssets[assetOut];
        if (withdrawAsset.withdrawCapacity < type(uint256).max) {
            if (withdrawAsset.withdrawCapacity < amountOfShares) revert("Not enough capacity");
            withdrawAsset.withdrawCapacity -= amountOfShares;
        }
    }

    function _incrementWithdrawCapacity(address assetOut, uint256 amountOfShares) internal {
        WithdrawAsset storage withdrawAsset = _withdrawAssets[assetOut];
        if (withdrawAsset.withdrawCapacity < type(uint256).max) {
            withdrawAsset.withdrawCapacity += amountOfShares;
        }
    }

    function _dequeueOnChainWithdraw(OnChainWithdraw memory request) internal virtual returns (bytes32 requestId) {
        // Remove request from queue.
        requestId = keccak256(abi.encode(request));
        bool removedFromSet = _withdrawRequests.remove(requestId);
        if (!removedFromSet) revert("request not found");
    }

    function _updateWithdrawAsset(
        address assetOut,
        uint24 secondsToMaturity,
        uint24 minimumSecondsToDeadline,
        uint16 minDiscount,
        uint16 maxDiscount,
        uint96 minimumShares
    ) internal {
        _withdrawAssets[assetOut] = WithdrawAsset({
            allowWithdraws: true,
            secondsToMaturity: secondsToMaturity,
            minimumSecondsToDeadline: minimumSecondsToDeadline,
            minDiscount: minDiscount,
            maxDiscount: maxDiscount,
            minimumShares: minimumShares,
            withdrawCapacity: type(uint256).max
        });
    }
}
