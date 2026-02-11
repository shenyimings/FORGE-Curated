// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";

import "../base/RewardsPoolController.sol";
import "../interfaces/IBoostController.sol";
import "../interfaces/IERC721Receiver.sol";

/**
 * @title SDL Pool
 * @notice Allows users to stake/lock SDL tokens and receive a percentage of the protocol's earned rewards
 */
contract SDLPool is RewardsPoolController, IERC721Upgradeable, IERC721MetadataUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Lock {
        uint256 amount;
        uint256 boostAmount;
        uint64 startTime;
        uint64 duration;
        uint64 expiry;
    }

    string public name;
    string public symbol;

    mapping(address => mapping(address => bool)) private operatorApprovals;
    mapping(uint256 => address) private tokenApprovals;

    IERC20Upgradeable public sdlToken;
    IBoostController public boostController;

    uint256 public lastLockId;
    mapping(uint256 => Lock) private locks;
    mapping(uint256 => address) private lockOwners;
    mapping(address => uint256) private balances;

    uint256 public totalEffectiveBalance;
    mapping(address => uint256) private effectiveBalances;

    address public delegatorPool;

    string public baseURI;

    event InitiateUnlock(address indexed owner, uint256 indexed lockId, uint64 expiry);
    event Withdraw(address indexed owner, uint256 indexed lockId, uint256 amount);
    event CreateLock(
        address indexed owner,
        uint256 indexed lockId,
        uint256 amount,
        uint256 boostAmount,
        uint64 lockingDuration
    );
    event UpdateLock(
        address indexed owner,
        uint256 indexed lockId,
        uint256 amount,
        uint256 boostAmount,
        uint64 lockingDuration
    );

    error SenderNotAuthorized();
    error InvalidLockId();
    error InvalidValue();
    error InvalidLockingDuration();
    error InvalidParams();
    error TransferFromIncorrectOwner();
    error TransferToZeroAddress();
    error TransferToNonERC721Implementer();
    error ApprovalToCurrentOwner();
    error ApprovalToCaller();
    error UnauthorizedToken();
    error TotalDurationNotElapsed();
    error HalfDurationNotElapsed();
    error InsufficientBalance();
    error UnlockNotInitiated();
    error DuplicateContract();
    error ContractNotFound();
    error UnlockAlreadyInitiated();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initializes contract
     * @param _name name of the staking derivative token
     * @param _symbol symbol of the staking derivative token
     * @param _boostController address of the boost controller
     * @param _delegatorPool address of the old contract this one will replace
     **/
    function initialize(
        string memory _name,
        string memory _symbol,
        address _sdlToken,
        address _boostController,
        address _delegatorPool
    ) public initializer {
        __RewardsPoolController_init();
        name = _name;
        symbol = _symbol;
        sdlToken = IERC20Upgradeable(_sdlToken);
        boostController = IBoostController(_boostController);
        delegatorPool = _delegatorPool;
    }

    /**
     * @notice reverts if `_owner` is not the owner of `_lockId`
     **/
    modifier onlyLockOwner(uint256 _lockId, address _owner) {
        if (_owner != ownerOf(_lockId)) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice returns the effective stake balance of an account
     * @dev the effective stake balance includes the actual amount of tokens an
     * account has staked across all locks plus any applicable boost gained by locking
     * @param _account address of account
     * @return effective stake balance
     **/
    function effectiveBalanceOf(address _account) external view returns (uint256) {
        return effectiveBalances[_account];
    }

    /**
     * @notice returns the number of locks owned by an account
     * @param _account address of account
     * @return total number of locks owned by account
     **/
    function balanceOf(address _account) public view returns (uint256) {
        return balances[_account];
    }

    /**
     * @notice returns the owner of a lock
     * @dev reverts if `_lockId` is invalid
     * @param _lockId id of the lock
     * @return lock owner
     **/
    function ownerOf(uint256 _lockId) public view returns (address) {
        address owner = lockOwners[_lockId];
        if (owner == address(0)) revert InvalidLockId();
        return owner;
    }

    /**
     * @notice returns the list of locks that corresponds to `_lockIds`
     * @dev reverts if any lockId is invalid
     * @param _lockIds list of lock ids
     * @return list of locks
     **/
    function getLocks(uint256[] calldata _lockIds) external view returns (Lock[] memory) {
        Lock[] memory retLocks = new Lock[](_lockIds.length);

        for (uint256 i = 0; i < _lockIds.length; ++i) {
            uint256 lockId = _lockIds[i];
            if (lockOwners[lockId] == address(0)) revert InvalidLockId();
            retLocks[i] = locks[lockId];
        }

        return retLocks;
    }

    /**
     * @notice returns a list of lockIds owned by an account
     * @param _owner address of account
     * @return list of lockIds
     **/
    function getLockIdsByOwner(address _owner) external view returns (uint256[] memory) {
        uint256 maxLockId = lastLockId;
        uint256 lockCount = balanceOf(_owner);
        uint256 lockIdsFound;
        uint256[] memory lockIds = new uint256[](lockCount);

        for (uint256 i = 1; i <= maxLockId; ++i) {
            if (lockOwners[i] == _owner) {
                lockIds[lockIdsFound] = i;
                lockIdsFound++;
                if (lockIdsFound == lockCount) break;
            }
        }

        assert(lockIdsFound == lockCount);

        return lockIds;
    }

    /**
     * @notice ERC677 implementation to stake/lock SDL tokens or distribute rewards
     * @dev
     * - will update/create a lock if the token transferred is SDL or will distribute rewards otherwise
     *
     * For Non-SDL:
     * - reverts if token is unsupported
     *
     * For SDL:
     * - set lockId to 0 to create a new lock or set lockId to > 0 to stake more into an existing lock
     * - set lockingDuration to 0 to stake without locking or set lockingDuration to > 0 to lock for an amount
     *   time in seconds
     * - see _updateLock() for more details on updating an existing lock or _createLock() for more details on
     *   creating a new lock
     * @param _sender of the stake
     * @param _value of the token transfer
     * @param _calldata encoded lockId (uint256) and lockingDuration (uint64)
     **/
    function onTokenTransfer(
        address _sender,
        uint256 _value,
        bytes calldata _calldata
    ) external override {
        if (msg.sender != address(sdlToken) && !isTokenSupported(msg.sender))
            revert UnauthorizedToken();

        if (_value == 0) revert InvalidValue();

        if (msg.sender == address(sdlToken)) {
            (uint256 lockId, uint64 lockingDuration) = abi.decode(_calldata, (uint256, uint64));
            if (lockId > 0) {
                _updateLock(_sender, lockId, _value, lockingDuration);
            } else {
                _createLock(_sender, _value, lockingDuration);
            }
        } else {
            distributeToken(msg.sender);
        }
    }

    /**
     * @notice extends the locking duration of a lock
     * @dev
     * - reverts if `_lockId` is invalid or sender is not owner of lock
     * - reverts if `_lockingDuration` is less than current locking duration of lock
     * - reverts if `_lockingDuration` is 0 or exceeds the maximum
     * @param _lockId id of lock
     * @param _lockingDuration new locking duration to set
     **/
    function extendLockDuration(uint256 _lockId, uint64 _lockingDuration) external {
        if (_lockingDuration == 0) revert InvalidLockingDuration();
        _updateLock(msg.sender, _lockId, 0, _lockingDuration);
    }

    /**
     * @notice initiates the unlock period for a lock
     * @dev
     * - at least half of the locking duration must have elapsed to initiate the unlock period
     * - the unlock period consists of half of the locking duration
     * - boost will be set to 0 upon initiation of the unlock period
     *
     * - reverts if `_lockId` is invalid or sender is not owner of lock
     * - reverts if a minimum of half the locking duration has not elapsed
     * @param _lockId id of lock
     **/
    function initiateUnlock(
        uint256 _lockId
    ) external onlyLockOwner(_lockId, msg.sender) updateRewards(msg.sender) {
        if (locks[_lockId].expiry != 0) revert UnlockAlreadyInitiated();
        uint64 halfDuration = locks[_lockId].duration / 2;
        if (locks[_lockId].startTime + halfDuration > block.timestamp)
            revert HalfDurationNotElapsed();

        uint64 expiry = uint64(block.timestamp) + halfDuration;
        locks[_lockId].expiry = expiry;

        uint256 boostAmount = locks[_lockId].boostAmount;
        locks[_lockId].boostAmount = 0;
        effectiveBalances[msg.sender] -= boostAmount;
        totalEffectiveBalance -= boostAmount;

        emit InitiateUnlock(msg.sender, _lockId, expiry);
    }

    /**
     * @notice withdraws unlocked SDL
     * @dev
     * - SDL can only be withdrawn if unlocked (once the unlock period has elapsed or if it was never
     *   locked in the first place)
     * - reverts if `_lockId` is invalid or sender is not owner of lock
     * - reverts if not unlocked
     * - reverts if `_amount` exceeds the amount staked in the lock
     * @param _lockId id of the lock
     * @param _amount amount to withdraw from the lock
     **/
    function withdraw(
        uint256 _lockId,
        uint256 _amount
    ) external onlyLockOwner(_lockId, msg.sender) updateRewards(msg.sender) {
        if (locks[_lockId].startTime != 0) {
            uint64 expiry = locks[_lockId].expiry;
            if (expiry == 0) revert UnlockNotInitiated();
            if (expiry > block.timestamp) revert TotalDurationNotElapsed();
        }

        uint256 baseAmount = locks[_lockId].amount;
        if (_amount > baseAmount) revert InsufficientBalance();

        emit Withdraw(msg.sender, _lockId, _amount);

        if (_amount == baseAmount) {
            delete locks[_lockId];
            delete lockOwners[_lockId];
            balances[msg.sender] -= 1;
            if (tokenApprovals[_lockId] != address(0)) delete tokenApprovals[_lockId];
            emit Transfer(msg.sender, address(0), _lockId);
        } else {
            locks[_lockId].amount = baseAmount - _amount;
        }

        effectiveBalances[msg.sender] -= _amount;
        totalEffectiveBalance -= _amount;

        sdlToken.safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice transfers a lock between accounts
     * @dev reverts if sender is not the owner of and not approved to transfer the lock
     * @param _from address to transfer from
     * @param _to address to transfer to
     * @param _lockId id of lock to transfer
     **/
    function transferFrom(address _from, address _to, uint256 _lockId) external {
        if (!_isApprovedOrOwner(msg.sender, _lockId)) revert SenderNotAuthorized();
        _transfer(_from, _to, _lockId);
    }

    /**
     * @notice transfers a lock between accounts and validates that the receiver supports ERC721
     * @dev
     * - calls onERC721Received on `_to` if it is a contract or reverts if it is a contract
     *   and does not implemement onERC721Received
     * - reverts if sender is not the owner of and not approved to transfer the lock
     * - reverts if `_lockId` is invalid
     * @param _from address to transfer from
     * @param _to address to transfer to
     * @param _lockId id of lock to transfer
     **/
    function safeTransferFrom(address _from, address _to, uint256 _lockId) external {
        safeTransferFrom(_from, _to, _lockId, "");
    }

    /**
     * @notice transfers a lock between accounts and validates that the receiver supports ERC721
     * @dev
     * - calls onERC721Received on `_to` if it is a contract or reverts if it is a contract
     *   and does not implemement onERC721Received
     * - reverts if sender is not the owner of and not approved to transfer the lock
     * - reverts if `_lockId` is invalid
     * @param _from address to transfer from
     * @param _to address to transfer to
     * @param _lockId id of lock to transfer
     * @param _data optional data to pass to receiver
     **/
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _lockId,
        bytes memory _data
    ) public {
        if (!_isApprovedOrOwner(msg.sender, _lockId)) revert SenderNotAuthorized();
        _transfer(_from, _to, _lockId);
        if (!_checkOnERC721Received(_from, _to, _lockId, _data))
            revert TransferToNonERC721Implementer();
    }

    /**
     * @notice approves `_to` to transfer `_lockId` to another address
     * @dev
     * - approval is revoked on transfer and can also be revoked by approving zero address
     * - reverts if sender is not owner of lock and not an approved operator for the owner
     * - reverts if `_to` is owner of lock
     * - reverts if `_lockId` is invalid
     * @param _to address approved to transfer
     * @param _lockId id of lock
     **/
    function approve(address _to, uint256 _lockId) external {
        address owner = ownerOf(_lockId);

        if (_to == owner) revert ApprovalToCurrentOwner();
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender))
            revert SenderNotAuthorized();

        tokenApprovals[_lockId] = _to;
        emit Approval(owner, _to, _lockId);
    }

    /**
     * @notice returns the address approved to transfer a lock
     * @param _lockId id of lock
     * @return approved address
     **/
    function getApproved(uint256 _lockId) public view returns (address) {
        if (lockOwners[_lockId] == address(0)) revert InvalidLockId();

        return tokenApprovals[_lockId];
    }

    /**
     * @notice approves _operator to transfer all tokens owned by sender
     * @dev
     * - approval will not be revoked until this function is called again with
     *   `_approved` set to false
     * - reverts if sender is `_operator`
     * @param _operator address to approve/unapprove
     * @param _approved whether address is approved or not
     **/
    function setApprovalForAll(address _operator, bool _approved) external {
        address owner = msg.sender;
        if (owner == _operator) revert ApprovalToCaller();

        operatorApprovals[owner][_operator] = _approved;
        emit ApprovalForAll(owner, _operator, _approved);
    }

    /**
     * @notice returns whether `_operator` is approved to transfer all tokens owned by `_owner`
     * @param _owner owner of tokens
     * @param _operator address approved to transfer
     * @return whether address is approved or not
     **/
    function isApprovedForAll(address _owner, address _operator) public view returns (bool) {
        return operatorApprovals[_owner][_operator];
    }

    /**
     * @notice returns an account's staked amount for use by reward pools
     * controlled by this contract
     * @param _account account address
     * @return account's staked amount
     */
    function staked(address _account) external view override returns (uint256) {
        return effectiveBalances[_account];
    }

    /**
     * @notice returns the total staked amount for use by reward pools
     * controlled by this contract
     * @return total staked amount
     */
    function totalStaked() external view override returns (uint256) {
        return totalEffectiveBalance;
    }

    /**
     * @notice returns whether this contract supports an interface
     * @param _interfaceId id of interface
     * @return whether contract supports interface or not
     */
    function supportsInterface(bytes4 _interfaceId) external view returns (bool) {
        return
            _interfaceId == type(IERC721Upgradeable).interfaceId ||
            _interfaceId == type(IERC721MetadataUpgradeable).interfaceId ||
            _interfaceId == type(IERC165Upgradeable).interfaceId;
    }

    /**
     * @dev returns the URI for a token
     */
    function tokenURI(uint256) external view returns (string memory) {
        return baseURI;
    }

    /**
     * @dev sets the base URI for all tokens
     */
    function setBaseURI(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    /**
     * @notice sets the boost controller
     * @dev this contract handles boost calculations for locking SDL
     * @param _boostController address of boost controller
     */
    function setBoostController(address _boostController) external onlyOwner {
        boostController = IBoostController(_boostController);
    }

    /**
     * @notice used by the delegator pool to migrate user stakes to this contract
     * @dev
     * - creates a new lock to represent the migrated stake
     * - reverts if `_lockingDuration` exceeds maximum
     * @param _sender owner of lock
     * @param _amount amount to stake
     * @param _lockingDuration duration of lock
     */
    function migrate(address _sender, uint256 _amount, uint64 _lockingDuration) external {
        if (msg.sender != delegatorPool) revert SenderNotAuthorized();
        sdlToken.safeTransferFrom(delegatorPool, address(this), _amount);
        _createLock(_sender, _amount, _lockingDuration);
    }

    /**
     * @notice creates a new lock
     * @dev reverts if `_lockingDuration` exceeds maximum
     * @param _sender owner of lock
     * @param _amount amount to stake
     * @param _lockingDuration duration of lock
     */
    function _createLock(
        address _sender,
        uint256 _amount,
        uint64 _lockingDuration
    ) private updateRewards(_sender) {
        uint256 boostAmount = boostController.getBoostAmount(_amount, _lockingDuration);
        uint256 totalAmount = _amount + boostAmount;
        uint64 startTime = _lockingDuration != 0 ? uint64(block.timestamp) : 0;
        uint256 lockId = lastLockId + 1;

        locks[lockId] = Lock(_amount, boostAmount, startTime, _lockingDuration, 0);
        lockOwners[lockId] = _sender;
        balances[_sender] += 1;
        lastLockId++;

        effectiveBalances[_sender] += totalAmount;
        totalEffectiveBalance += totalAmount;

        emit CreateLock(_sender, lockId, _amount, boostAmount, _lockingDuration);
        emit Transfer(address(0), _sender, lockId);
    }

    /**
     * @notice updates an existing lock
     * @dev
     * - reverts if `_lockId` is invalid
     * - reverts if `_lockingDuration` is less than current locking duration of lock
     * - reverts if `_lockingDuration` exceeds maximum
     * @param _sender owner of lock
     * @param _lockId id of lock
     * @param _amount additional amount to stake
     * @param _lockingDuration duration of lock
     */
    function _updateLock(
        address _sender,
        uint256 _lockId,
        uint256 _amount,
        uint64 _lockingDuration
    ) private onlyLockOwner(_lockId, _sender) updateRewards(_sender) {
        uint64 curLockingDuration = locks[_lockId].duration;
        uint64 curExpiry = locks[_lockId].expiry;
        if (
            (curExpiry == 0 || curExpiry > block.timestamp) && _lockingDuration < curLockingDuration
        ) {
            revert InvalidLockingDuration();
        }

        uint256 curBaseAmount = locks[_lockId].amount;

        uint256 baseAmount = curBaseAmount + _amount;
        uint256 boostAmount = boostController.getBoostAmount(baseAmount, _lockingDuration);

        if (_amount != 0) {
            locks[_lockId].amount = baseAmount;
        }

        if (_lockingDuration != curLockingDuration) {
            locks[_lockId].duration = _lockingDuration;
        }

        if (_lockingDuration != 0) {
            locks[_lockId].startTime = uint64(block.timestamp);
        } else if (curLockingDuration != 0) {
            delete locks[_lockId].startTime;
        }

        if (locks[_lockId].expiry != 0) {
            locks[_lockId].expiry = 0;
        }

        int256 diffTotalAmount = int256(baseAmount + boostAmount) -
            int256(curBaseAmount + locks[_lockId].boostAmount);
        if (diffTotalAmount > 0) {
            effectiveBalances[_sender] += uint256(diffTotalAmount);
            totalEffectiveBalance += uint256(diffTotalAmount);
        } else if (diffTotalAmount < 0) {
            effectiveBalances[_sender] -= uint256(-1 * diffTotalAmount);
            totalEffectiveBalance -= uint256(-1 * diffTotalAmount);
        }

        locks[_lockId].boostAmount = boostAmount;

        emit UpdateLock(_sender, _lockId, baseAmount, boostAmount, _lockingDuration);
    }

    /**
     * @notice transfers a lock between accounts
     * @dev
     * - reverts if `_from` is not the owner of the lock
     * - reverts if `to` is zero address
     * @param _from address to transfer from
     * @param _to address to transfer to
     * @param _lockId id of lock to transfer
     **/
    function _transfer(address _from, address _to, uint256 _lockId) private {
        if (_from != ownerOf(_lockId)) revert TransferFromIncorrectOwner();
        if (_to == address(0)) revert TransferToZeroAddress();

        delete tokenApprovals[_lockId];

        _updateRewards(_from);
        _updateRewards(_to);

        uint256 effectiveBalanceChange = locks[_lockId].amount + locks[_lockId].boostAmount;
        effectiveBalances[_from] -= effectiveBalanceChange;
        effectiveBalances[_to] += effectiveBalanceChange;

        balances[_from] -= 1;
        balances[_to] += 1;
        lockOwners[_lockId] = _to;

        emit Transfer(_from, _to, _lockId);
    }

    /**
     * taken from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol
     * @notice verifies that an address supports ERC721 and calls onERC721Received if applicable
     * @dev
     * - called after a lock is safe transferred
     * - calls onERC721Received on `_to` if it is a contract or reverts if it is a contract
     *   and does not implemement onERC721Received
     * @param _from address that lock is being transferred from
     * @param _to address that lock is being transferred to
     * @param _lockId id of lock
     * @param _data optional data to be passed to receiver
     */
    function _checkOnERC721Received(
        address _from,
        address _to,
        uint256 _lockId,
        bytes memory _data
    ) private returns (bool) {
        if (_to.code.length > 0) {
            try IERC721Receiver(_to).onERC721Received(msg.sender, _from, _lockId, _data) returns (
                bytes4 retval
            ) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert TransferToNonERC721Implementer();
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @notice returns whether an account is authorized to transfer a lock
     * @dev returns true if `_spender` is approved to transfer `_lockId` or if `_spender` is
     * approved to transfer all locks owned by the owner of `_lockId`
     * @param _spender address of account
     * @param _lockId id of lock
     * @return whether address is authorized ot not
     **/
    function _isApprovedOrOwner(address _spender, uint256 _lockId) private view returns (bool) {
        address owner = ownerOf(_lockId);
        return (_spender == owner ||
            isApprovedForAll(owner, _spender) ||
            getApproved(_lockId) == _spender);
    }
}
