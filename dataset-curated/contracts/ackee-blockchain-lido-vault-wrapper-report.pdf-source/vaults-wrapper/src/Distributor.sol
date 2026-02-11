// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Distributor is AccessControlEnumerable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Merkle root of the distribution
    bytes32 public root;

    /// @notice IPFS CID of the last published Merkle tree
    string public cid;

    /// @notice Mapping of claimed amounts by account and token
    mapping(address account => mapping(address token => uint256 amount)) public claimed;

    /// @notice List of supported tokens
    EnumerableSet.AddressSet private tokens;

    /// @notice Last processed block number for user tracking
    uint256 public lastProcessedBlock;

    // ==================== Events ====================
    event TokenAdded(address indexed token);
    event Claimed(address indexed recipient, address indexed token, uint256 amount);
    event MerkleRootUpdated(
        bytes32 oldRoot, bytes32 indexed newRoot, string oldCid, string newCid, uint256 oldBlock, uint256 newBlock
    );

    // ==================== Errors ====================
    error AlreadyProcessed();
    error AlreadySetInThisBlock();
    error InvalidProof();
    error ClaimableTooLow();
    error RootNotSet();
    error TokenAlreadyAdded(address token);
    error ZeroAddress();
    error TokenNotSupported(address token);

    /**
     * @notice Constructor
     * @param _owner The address of the owner (admin)
     * @param _manager The address of the manager (MANAGER_ROLE)
     */
    constructor(address _owner, address _manager) {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(MANAGER_ROLE, _manager);
    }

    /**
     * @notice Add a token to the list of supported tokens
     * @param token The address of the token to add
     */
    function addToken(address token) external {
        _checkRole(MANAGER_ROLE, msg.sender);
        if (token == address(0)) revert ZeroAddress();
        if (tokens.contains(token)) revert TokenAlreadyAdded(token);

        tokens.add(token);

        emit TokenAdded(token);
    }

    /**
     * @notice Get the list of supported tokens
     * @return tokens The list of supported tokens
     */
    function getTokens() external view returns (address[] memory) {
        return tokens.values();
    }

    /**
     * @notice Sets the Merkle root and CID
     * @param _root The new Merkle root
     * @param _cid The new CID
     */
    function setMerkleRoot(bytes32 _root, string calldata _cid) external {
        _checkRole(MANAGER_ROLE, msg.sender);
        if (_root == root && keccak256(bytes(_cid)) == keccak256(bytes(cid))) revert AlreadyProcessed();
        if (block.number == lastProcessedBlock) revert AlreadySetInThisBlock();

        emit MerkleRootUpdated(root, _root, cid, _cid, lastProcessedBlock, block.number);

        root = _root;
        cid = _cid;
        lastProcessedBlock = block.number;
    }

    /**
     * @notice Preview the amount of tokens that can be claimed
     * @param _recipient The address to claim rewards for.
     * @param _token The address of the reward token.
     * @param _cumulativeAmount The overall claimable amount of token rewards.
     * @param _proof The merkle proof that validates this claim.
     * @return claimable The amount of tokens that can be claimed.
     */
    function previewClaim(address _recipient, address _token, uint256 _cumulativeAmount, bytes32[] calldata _proof)
        public
        view
        returns (uint256 claimable)
    {
        if (root == bytes32(0)) revert RootNotSet();
        if (!tokens.contains(_token)) revert TokenNotSupported(_token);

        if (!MerkleProof.verifyCalldata(
                _proof, root, keccak256(bytes.concat(keccak256(abi.encode(_recipient, _token, _cumulativeAmount))))
            )) revert InvalidProof();

        uint256 alreadyClaimed = claimed[_recipient][_token];
        if (_cumulativeAmount <= alreadyClaimed) return 0;

        unchecked {
            claimable = _cumulativeAmount - alreadyClaimed;
        }
    }

    /**
     * @notice Claims rewards.
     * @dev Anyone can claim rewards on behalf of an account.
     *
     * @param _recipient The address to claim rewards for.
     * @param _token The address of the reward token.
     * @param _cumulativeAmount The overall claimable amount of token rewards.
     * @param _proof The merkle proof that validates this claim.
     * @return claimedAmount The amount of reward token claimed.
     */
    function claim(address _recipient, address _token, uint256 _cumulativeAmount, bytes32[] calldata _proof)
        external
        returns (uint256 claimedAmount)
    {
        claimedAmount = previewClaim(_recipient, _token, _cumulativeAmount, _proof);
        if (claimedAmount == 0) revert ClaimableTooLow();
        claimed[_recipient][_token] = _cumulativeAmount;

        IERC20(_token).safeTransfer(_recipient, claimedAmount);
        emit Claimed(_recipient, _token, claimedAmount);
    }
}
