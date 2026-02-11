// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../common/IAllowedCalldataChecker.sol";

/// @dev External interface of P2pYieldProxyFactory
interface IP2pYieldProxyFactory is IAllowedCalldataChecker, IERC165 {

    /// @dev Emitted when the P2pSigner is transferred
    event P2pYieldProxyFactory__P2pSignerTransferred(
        address indexed _previousP2pSigner,
        address indexed _newP2pSigner
    );

    /// @dev Emitted when the deposit is made
    event P2pYieldProxyFactory__Deposited(
        address indexed _client,
        uint96 indexed _clientBasisPoints
    );

    /// @dev Emitted when the a new proxy is created
    event P2pYieldProxyFactory__ProxyCreated(
        address _proxy,
        address _client,
        uint96 _clientBasisPoints
    );

    /// @notice Deposits a client supplied asset into the underlying yield protocol via a proxy.
    /// @param _asset Address of the ERC-20 asset to deposit on behalf of the client.
    /// @param _amount Amount of `_asset` to move from the client to the proxy and forward to the yield protocol.
    /// @param _clientBasisPoints Fee share expressed in basis points (out of 10_000) that the client keeps.
    /// @param _p2pSignerSigDeadline Expiration timestamp for the signer approval accompanying this deposit.
    /// @param _p2pSignerSignature Off-chain signature authorising the deposit parameters from the designated signer.
    /// @return p2pYieldProxyAddress Deterministic proxy address used for the client after the deposit is processed.
    function deposit(
        address _asset,
        uint256 _amount,

        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    )
    external
    returns (address p2pYieldProxyAddress);

    /// @notice Predicts the deterministic proxy address that will serve a specific client and fee configuration.
    /// @param _client Address of the client that will control the proxy.
    /// @param _clientBasisPoints Fee share (in basis points) that the client keeps from accrued rewards.
    /// @return proxyAddress Deterministic address where the proxy will be deployed or already lives.
    function predictP2pYieldProxyAddress(
        address _client,
        uint96 _clientBasisPoints
    ) external view returns (address proxyAddress);

    /// @notice Updates the recognised P2P signer that authorises new deposits.
    /// @param _newP2pSigner Address of the replacement signer allowed to approve deposits.
    function transferP2pSigner(
        address _newP2pSigner
    ) external;

    /// @notice Returns the implementation contract used as the template for future proxies.
    /// @return referenceProxy Address of the proxy implementation clone target.
    function getReferenceP2pYieldProxy() external view returns (address referenceProxy);

    /// @notice Computes the EIP-191 hash that must be signed by the authorised P2P signer for a deposit.
    /// @param _client Address of the client that will control the proxy.
    /// @param _clientBasisPoints Fee share (in basis points) that the client keeps from accrued rewards.
    /// @param _p2pSignerSigDeadline Expiration timestamp of the off-chain approval.
    /// @return signerHash Message hash that should be signed by the configured P2P signer.
    function getHashForP2pSigner(
        address _client,
        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline
    ) external view returns (bytes32 signerHash);

    /// @notice Returns the address authorised to co-sign new deposits.
    /// @return signer Address of the currently configured P2P signer.
    function getP2pSigner() external view returns (address signer);

    /// @notice Returns the operator allowed to manage privileged actions on the factory.
    /// @return operator Address of the current P2P operator.
    function getP2pOperator() external view returns (address operator);

    /// @notice Returns every proxy address created by this factory.
    /// @return proxies Array containing the addresses of all instantiated proxies.
    function getAllProxies() external view returns (address[] memory proxies);
}
