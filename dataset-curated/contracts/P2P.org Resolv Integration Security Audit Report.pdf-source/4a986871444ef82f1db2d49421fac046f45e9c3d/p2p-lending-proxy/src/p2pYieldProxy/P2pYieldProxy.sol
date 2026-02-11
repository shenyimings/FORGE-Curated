// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts-upgradable/security/ReentrancyGuardUpgradeable.sol";
import "../@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../@openzeppelin/contracts/utils/Address.sol";
import "../@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "../common/AllowedCalldataChecker.sol";
import "../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import "../structs/P2pStructs.sol";
import "./IP2pYieldProxy.sol";

error P2pYieldProxy__ZeroAddressAsset();
error P2pYieldProxy__ZeroAssetAmount();
error P2pYieldProxy__ZeroSharesAmount();
error P2pYieldProxy__InvalidClientBasisPoints(uint96 _clientBasisPoints);
error P2pYieldProxy__NotFactory(address _factory);
error P2pYieldProxy__DifferentActuallyDepositedAmount(
    uint256 _requestedAmount,
    uint256 _actualAmount
);
error P2pYieldProxy__NotFactoryCalled(
    address _msgSender,
    IP2pYieldProxyFactory _actualFactory
);
error P2pYieldProxy__NotClientCalled(
    address _msgSender,
    address _actualClient
);
error P2pYieldProxy__ZeroAddressFactory();
error P2pYieldProxy__ZeroAddressP2pTreasury();
error P2pYieldProxy__ZeroAllowedCalldataChecker();
error P2pYieldProxy__DataTooShort();

/// @title P2pYieldProxy
/// @notice P2pYieldProxy is a contract that allows a client to deposit and withdraw assets from a yield protocol.
abstract contract P2pYieldProxy is
    Initializable,
    ReentrancyGuardUpgradeable,
    ERC165,
    IP2pYieldProxy {

    using SafeERC20 for IERC20;
    using Address for address;

    /// @dev P2pYieldProxyFactory
    IP2pYieldProxyFactory internal immutable i_factory;

    /// @dev P2pTreasury
    address internal immutable i_p2pTreasury;

    IAllowedCalldataChecker internal immutable i_allowedCalldataChecker;

    /// @dev Client
    address internal s_client;

    /// @dev Client basis points
    uint96 internal s_clientBasisPoints;

    // asset => amount
    mapping(address => uint256) internal s_totalDeposited;

    // asset => amount
    mapping(address => Withdrawn) internal s_totalWithdrawn;

    /// @notice If caller is not factory, revert
    modifier onlyFactory() {
        if (msg.sender != address(i_factory)) {
            revert P2pYieldProxy__NotFactoryCalled(msg.sender, i_factory);
        }
        _;
    }

    /// @notice If caller is not client, revert
    modifier onlyClient() {
        if (msg.sender != s_client) {
            revert P2pYieldProxy__NotClientCalled(msg.sender, s_client);
        }
        _;
    }

    /// @dev Modifier for checking if a calldata is allowed
    /// @param _yieldProtocolAddress The address of the yield protocol
    /// @param _yieldProtocolCalldata The calldata (encoded signature + arguments) to be passed to the yield protocol
    modifier calldataShouldBeAllowed(
        address _yieldProtocolAddress,
        bytes calldata _yieldProtocolCalldata
    ) {
        // validate yieldProtocolCalldata for yieldProtocolAddress
        bytes4 selector = _getFunctionSelector(_yieldProtocolCalldata);
        i_allowedCalldataChecker.checkCalldata(
            _yieldProtocolAddress,
            selector,
            _yieldProtocolCalldata[4:]
        );
        _;
    }

    /// @notice Constructor for P2pYieldProxy
    /// @param _factory The factory address
    /// @param _p2pTreasury The P2pTreasury address
    /// @param _allowedCalldataChecker AllowedCalldataChecker
    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker
    ) {
        require(_factory != address(0), P2pYieldProxy__ZeroAddressFactory());
        i_factory = IP2pYieldProxyFactory(_factory);

        require(_p2pTreasury != address(0), P2pYieldProxy__ZeroAddressP2pTreasury());
        i_p2pTreasury = _p2pTreasury;

        require (_allowedCalldataChecker != address(0), P2pYieldProxy__ZeroAllowedCalldataChecker());
        i_allowedCalldataChecker = IAllowedCalldataChecker(_allowedCalldataChecker);
    }

    /// @inheritdoc IP2pYieldProxy
    function initialize(
        address _client,
        uint96 _clientBasisPoints
    )
    external
    initializer
    onlyFactory
    {
        __ReentrancyGuard_init();

        require(
            _clientBasisPoints > 0 && _clientBasisPoints <= 10_000,
            P2pYieldProxy__InvalidClientBasisPoints(_clientBasisPoints)
        );

        s_client = _client;
        s_clientBasisPoints = _clientBasisPoints;

        emit P2pYieldProxy__Initialized();
    }

    /// @inheritdoc IP2pYieldProxy
    function deposit(address _asset, uint256 _amount) external virtual;

    /// @notice Deposit assets into yield protocol
    /// @param _yieldProtocolAddress yield protocol address
    /// @param _yieldProtocolDepositCalldata calldata for deposit function of yield protocol
    /// @param _asset asset to deposit
    /// @param _amount amount to deposit
    function _deposit(
        address _yieldProtocolAddress,
        bytes memory _yieldProtocolDepositCalldata,
        address _asset,
        uint256 _amount
    )
    internal
    onlyFactory
    {
        require (_asset != address(0), P2pYieldProxy__ZeroAddressAsset());
        require (_amount > 0, P2pYieldProxy__ZeroAssetAmount());

        address client = s_client;

        uint256 assetAmountBefore = IERC20(_asset).balanceOf(address(this));

        // transfer tokens into Proxy
        IERC20(_asset).safeTransferFrom(
            client,
            address(this),
            _amount
        );

        uint256 assetAmountAfter = IERC20(_asset).balanceOf(address(this));
        uint256 actualAmount = assetAmountAfter - assetAmountBefore;

        require (
            actualAmount == _amount,
            P2pYieldProxy__DifferentActuallyDepositedAmount(_amount, actualAmount)
        ); // no support for fee-on-transfer or rebasing tokens

        uint256 totalDepositedAfter = s_totalDeposited[_asset] + actualAmount;
        s_totalDeposited[_asset] = totalDepositedAfter;
        emit P2pYieldProxy__Deposited(
            _yieldProtocolAddress,
            _asset,
            actualAmount,
            totalDepositedAfter
        );

        IERC20(_asset).safeIncreaseAllowance(
            _yieldProtocolAddress,
            actualAmount
        );

        _yieldProtocolAddress.functionCall(_yieldProtocolDepositCalldata);
    }

    /// @notice Withdraw assets from yield protocol
    /// @param _yieldProtocolAddress yield protocol address
    /// @param _asset ERC-20 asset address
    /// @param _yieldProtocolWithdrawalCalldata calldata for withdraw function of yield protocol
    function _withdraw(
        address _yieldProtocolAddress,
        address _asset,
        bytes memory _yieldProtocolWithdrawalCalldata
    )
    internal
    nonReentrant
    {
        int256 accruedRewards = calculateAccruedRewards(_yieldProtocolAddress, _asset);

        uint256 assetAmountBefore = IERC20(_asset).balanceOf(address(this));

        // withdraw assets from Protocol
        _yieldProtocolAddress.functionCall(_yieldProtocolWithdrawalCalldata);

        uint256 assetAmountAfter = IERC20(_asset).balanceOf(address(this));

        uint256 newAssetAmount = assetAmountAfter - assetAmountBefore;

        uint256 positiveAccruedRewards;
        if (accruedRewards > 0) {
            positiveAccruedRewards = uint256(accruedRewards);
        }

        uint256 profitPortion = newAssetAmount > positiveAccruedRewards
            ? positiveAccruedRewards
            : newAssetAmount;
        uint256 principalPortion = newAssetAmount - profitPortion;

        Withdrawn memory withdrawn = s_totalWithdrawn[_asset];
        uint256 totalWithdrawnBefore = uint256(withdrawn.amount);
        uint256 totalWithdrawnAfter = totalWithdrawnBefore + principalPortion;

        // update total withdrawn
        withdrawn.amount = uint208(totalWithdrawnAfter);
        withdrawn.lastFeeCollectionTime = uint48(block.timestamp);
        s_totalWithdrawn[_asset] = withdrawn;

        uint256 p2pAmount;
        if (profitPortion > 0) {
            // That extra 9999 ensures that any nonzero remainder will push the result up by 1 (ceiling division).
            p2pAmount = calculateP2pFeeAmount(profitPortion);
        }
        uint256 clientAmount = newAssetAmount - p2pAmount;

        if (p2pAmount > 0) {
            IERC20(_asset).safeTransfer(i_p2pTreasury, p2pAmount);
        }
        // clientAmount must be > 0 at this point
        IERC20(_asset).safeTransfer(s_client, clientAmount);

        emit P2pYieldProxy__Withdrawn(
            _yieldProtocolAddress,
            _yieldProtocolAddress,
            _asset,
            newAssetAmount,
            totalWithdrawnAfter,
            accruedRewards,
            p2pAmount,
            clientAmount
        );
    }

    /// @inheritdoc IP2pYieldProxy
    function callAnyFunction(
        address _yieldProtocolAddress,
        bytes calldata _yieldProtocolCalldata
    )
    external
    onlyClient
    nonReentrant
    calldataShouldBeAllowed(_yieldProtocolAddress, _yieldProtocolCalldata)
    {
        emit P2pYieldProxy__CalledAsAnyFunction(_yieldProtocolAddress);
        _yieldProtocolAddress.functionCall(_yieldProtocolCalldata);
    }

    /// @notice Returns function selector (first 4 bytes of data)
    /// @param _data calldata (encoded signature + arguments)
    /// @return functionSelector function selector
    function _getFunctionSelector(
        bytes calldata _data
    ) private pure returns (bytes4 functionSelector) {
        require (_data.length >= 4, P2pYieldProxy__DataTooShort());
        return bytes4(_data[:4]);
    }

    /// @inheritdoc IP2pYieldProxy
    function getFactory() external view returns (address) {
        return address(i_factory);
    }

    /// @inheritdoc IP2pYieldProxy
    function getP2pTreasury() external view returns (address) {
        return i_p2pTreasury;
    }

    /// @inheritdoc IP2pYieldProxy
    function getClient() external view returns (address) {
        return s_client;
    }

    /// @inheritdoc IP2pYieldProxy
    function getClientBasisPoints() external view returns (uint96) {
        return s_clientBasisPoints;
    }

    /// @inheritdoc IP2pYieldProxy
    function getTotalDeposited(address _asset) external view returns (uint256) {
        return s_totalDeposited[_asset];
    }

    /// @inheritdoc IP2pYieldProxy
    function getTotalWithdrawn(address _asset) external view returns (uint256) {
        return s_totalWithdrawn[_asset].amount;
    }

    function getUserPrincipal(address _asset) public view returns(uint256) {
        uint256 totalDeposited = s_totalDeposited[_asset];
        uint256 totalWithdrawn = s_totalWithdrawn[_asset].amount;
        if (totalDeposited > totalWithdrawn) {
            return totalDeposited - totalWithdrawn;
        }
        return 0;
    }

    function calculateAccruedRewards(address _yieldProtocolAddress, address _asset) public view virtual returns(int256) {
        uint256 currentAmount = _getCurrentAssetAmount(_yieldProtocolAddress, _asset);
        uint256 userPrincipal = getUserPrincipal(_asset);
        return int256(currentAmount) - int256(userPrincipal);
    }

    function _getCurrentAssetAmount(address _yieldProtocolAddress, address _asset) internal view virtual returns (uint256);

    function getLastFeeCollectionTime(address _asset) public view returns(uint48) {
        return s_totalWithdrawn[_asset].lastFeeCollectionTime;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IP2pYieldProxy).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Calculates P2P treasury fee amount using ceiling division
    /// @param _amount amount
    /// @return p2pFeeAmount p2p fee amount
    function calculateP2pFeeAmount(uint256 _amount) internal view returns (uint256 p2pFeeAmount) {
        if (_amount == 0) return 0;
        p2pFeeAmount = (_amount * (10_000 - s_clientBasisPoints) + 9999) / 10_000;
    }
}
