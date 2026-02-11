// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract Multisig {
    enum Operation {
        Call,
        DelegateCall
    }

    // keccak256(
    //     "EIP712Domain(uint256 chainId,address verifyingContract)"
    // );
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    // keccak256(
    //     "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
    // );
    bytes32 private constant SAFE_TX_TYPEHASH = 0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8;

    event ApproveHash(
        bytes32 indexed approvedHash,
        address indexed owner,
        address to,
        uint256 value,
        bytes data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        uint256 nonce
    );
    event ExecutionFailure(bytes32 indexed txHash, uint256 payment);
    event ExecutionSuccess(bytes32 indexed txHash, uint256 payment);
    event SafeReceived(address indexed sender, uint256 value);

    uint256 public nonce;

    mapping(address => address) internal owners;
    uint256 internal immutable ownerCount;
    uint256 internal immutable threshold;

    address internal constant SENTINEL_OWNERS = address(0x1);

    // mapping to keep track of all message hashes that have been approved by ALL REQUIRED owners
    mapping(bytes32 => uint256) public signedMessages;
    // mapping to keep track of all hashes (message or transaction) that have been approved by ANY owners
    mapping(address => mapping(bytes32 => uint256)) public approvedHashes;

    constructor(address[] memory _owners, uint256 _threshold) {
        // validate that threshold is smaller than number of added owners
        require(_threshold <= _owners.length, "Too big threshold");
        // there has to be at least one Safe owner
        require(_threshold >= 1, "Threshold can't be equal to zero");
        // initializing Safe owners
        address currentOwner = SENTINEL_OWNERS;
        for (uint256 i = 0; i < _owners.length; i++) {
            // owner address cannot be null
            address owner = _owners[i];
            require(owner != address(0) && owner != SENTINEL_OWNERS && owner != address(this) && currentOwner != owner, "Incorrect owner address");
            // no duplicate owners allowed
            require(owners[owner] == address(0), "Owners' addresses must not be repeated");
            owners[currentOwner] = owner;
            currentOwner = owner;
        }
        owners[currentOwner] = SENTINEL_OWNERS;
        ownerCount = _owners.length;
        threshold = _threshold;
    }

    ///////////////////////////////
    /// VIEW FUNCTIONS
    ///////////////////////////////

    /**
     * @notice returns the ID of the chain the contract is currently deployed on
     * @return the ID of the current chain as a uint256
     */
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    /**
     * @dev returns the domain separator for this contract, as defined in the EIP-712 standard
     * @return bytes32 the domain separator hash
     */
    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, getChainId(), this));
    }

    /**
     * @notice returns the pre-image of the transaction hash (see getTransactionHash)
     * @param to destination address
     * @param value ether value
     * @param data data payload
     * @param operation operation type
     * @param safeTxGas gas that should be used for the safe transaction
     * @param baseGas gas costs for that are independent of the transaction execution(e.g. base transaction fee, signature check, payment of the refund)
     * @param gasPrice maximum gas price that should be used for this transaction
     * @param gasToken token address (or 0 if ETH) that is used for the payment
     * @param refundReceiver address of receiver of gas payment (or 0 if tx.origin)
     * @param _nonce transaction nonce
     * @return transaction hash bytes
     */
    function encodeTransactionData(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) public view returns (bytes memory) {
        bytes32 safeTxHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH,
                to,
                value,
                keccak256(data),
                operation,
                safeTxGas,
                baseGas,
                gasPrice,
                gasToken,
                refundReceiver,
                _nonce
            )
        );
        return abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator(), safeTxHash);
    }

    /**
     * @notice checks whether the signature provided is valid for the provided data and hash. Reverts otherwise
     * @param dataHash hash of the data (could be either a message hash or transaction hash)
     * @param data that should be signed (this is passed to an external validator contract)
     */
    function checkApprovals(bytes32 dataHash, bytes memory data) public view {
        // load threshold to avoid multiple storage loads
        uint256 _threshold = threshold;
        // check that a threshold is set
        require(_threshold > 0, "Threshold is not set");
        checkNApprovals(dataHash, data, _threshold);
    }

    /**
     * @notice checks whether the signature provided is valid for the provided data and hash. Reverts otherwise
     * @dev since the EIP-1271 does an external call, be mindful of reentrancy attacks
     * @param dataHash hash of the data (could be either a message hash or transaction hash)
     * @param data that should be signed (this is passed to an external validator contract)
     * @param requiredSignatures amount of required valid signatures
     */
    function checkNApprovals(bytes32 dataHash, bytes memory data, uint256 requiredSignatures) public view {
        uint256 count = 0;
        address currentOwner = owners[SENTINEL_OWNERS];
        while (currentOwner != SENTINEL_OWNERS) {
            if (approvedHashes[currentOwner][dataHash] != 0) {
                count++;
            }
            currentOwner = owners[currentOwner];
        }
        require(count >= requiredSignatures, "Not enough approvals");
    }

    /**
     * @notice returns transaction hash to be signed by owners
     * @param to destination address
     * @param value ether value
     * @param data data payload
     * @param operation operation type
     * @param safeTxGas fas that should be used for the safe transaction
     * @param baseGas gas costs for data used to trigger the safe transaction
     * @param gasPrice maximum gas price that should be used for this transaction
     * @param gasToken token address (or 0 if ETH) that is used for the payment
     * @param refundReceiver address of receiver of gas payment (or 0 if tx.origin)
     * @param _nonce transaction nonce
     * @return transaction hash
     */
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) public view returns (bytes32) {
        return keccak256(encodeTransactionData(to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, _nonce));
    }

    /**
     * @notice returns the number of required confirmations for a Safe transaction aka the threshold
     * @return threshold number
     */
    function getThreshold() public view returns (uint256) {
        return threshold;
    }

    /**
     * @notice returns if `owner` is an owner of the Safe
     * @return boolean if owner is an owner of the Safe
     */
    function isOwner(address owner) public view returns (bool) {
        return owner != SENTINEL_OWNERS && owners[owner] != address(0);
    }

    /**
     * @notice returns a list of Safe owners
     * @return array of Safe owners
     */
    function getOwners() public view returns (address[] memory) {
        address[] memory array = new address[](ownerCount);

        // populate return array
        uint256 index = 0;
        address currentOwner = owners[SENTINEL_OWNERS];
        while (currentOwner != SENTINEL_OWNERS) {
            array[index] = currentOwner;
            currentOwner = owners[currentOwner];
            index++;
        }
        return array;
    }

    ///////////////////////////////
    /// INTERNAL FUNCTIONS
    ///////////////////////////////

    /**
     * @notice handles the payment for a Safe transaction
     * @param gasUsed gas used by the Safe transaction
     * @param baseGas gas costs that are independent of the transaction execution (e.g. base transaction fee, signature check, payment of the refund)
     * @param gasPrice gas price that should be used for the payment calculation
     * @param gasToken token address (or 0 if ETH) that is used for the payment
     * @return payment The amount of payment made in the specified token
     */
    function handlePayment(
        uint256 gasUsed,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver
    ) private returns (uint256 payment) {
        // solhint-disable-next-line avoid-tx-origin
        address payable receiver = refundReceiver == address(0) ? payable(tx.origin) : refundReceiver;
        if (gasToken == address(0)) {
            // for ETH we will only adjust the gas price to not be higher than the actual used gas price
            payment = (gasUsed + baseGas) * (gasPrice < tx.gasprice ? gasPrice : tx.gasprice);
            require(receiver.send(payment), "Error when paying a transaction in native currency");
        } else {
            payment = (gasUsed + baseGas) * (gasPrice);
            require(transferToken(gasToken, receiver, payment), "Error when paying a transaction in token");
        }
    }

    /**
     * @notice transfers a token and returns a boolean if it was a success
     * @dev it checks the return data of the transfer call and returns true if the transfer was successful
     *      it doesn't check if the `token` address is a contract or not
     * @param token token that should be transferred
     * @param receiver receiver to whom the token should be transferred
     * @param amount the amount of tokens that should be transferred
     * @return transferred Returns true if the transfer was successful
     */
    function transferToken(address token, address receiver, uint256 amount) internal returns (bool transferred) {
        // 0xa9059cbb - keccack("transfer(address,uint256)")
        bytes memory data = abi.encodeWithSelector(0xa9059cbb, receiver, amount);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // We write the return value to scratch space.
            // See https://docs.soliditylang.org/en/v0.7.6/internals/layout_in_memory.html#layout-in-memory
            let success := call(sub(gas(), 10000), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            switch returndatasize()
            case 0 {
                transferred := success
            }
            case 0x20 {
                transferred := iszero(or(iszero(success), iszero(mload(0))))
            }
            default {
                transferred := 0
            }
        }
    }

    /**
     * @notice splits signature bytes into `uint8 v, bytes32 r, bytes32 s`
     * @dev make sure to perform a bounds check for @param pos, to avoid out of bounds access on @param signatures
     *      the signature format is a compact form of {bytes32 r}{bytes32 s}{uint8 v}
     *      compact means uint8 is not padded to 32 bytes
     * @param pos which signature to read
     *            a prior bounds check of this parameter should be performed, to avoid out of bounds access
     * @param signatures concatenated {r, s, v} signatures
     * @return v Recovery ID or Safe signature type
     * @return r Output value r of the signature
     * @return s Output value s of the signature
     */
    function signatureSplit(bytes memory signatures, uint256 pos) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let signaturePos := mul(0x41, pos)
            r := mload(add(signatures, add(signaturePos, 0x20)))
            s := mload(add(signatures, add(signaturePos, 0x40)))
            /**
             * here we are loading the last 32 bytes, including 31 bytes
             * of 's'. There is no 'mload8' to do this
             * 'byte' is not working due to the Solidity parser, so lets
             * use the second best option, 'and'
             */
            v := and(mload(add(signatures, add(signaturePos, 0x41))), 0xff)
        }
    }

    /**
     * @notice executes either a delegatecall or a call with provided parameters
     * @dev this method doesn't perform any sanity check of the transaction, such as:
     *      - if the contract at `to` address has code or not
     *      it is the responsibility of the caller to perform such checks
     * @param to destination address
     * @param value ether value
     * @param data data payload
     * @param operation operation type
     * @return success boolean flag indicating if the call succeeded
     */
    function execute(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        uint256 txGas
    ) internal returns (bool success) {
        if (operation == Operation.DelegateCall) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0)
            }
        } else {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
            }
        }
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    ///////////////////////////////
    /// PUBLIC FUNCTIONS
    ///////////////////////////////

    /** @notice executes a `operation` {0: Call, 1: DelegateCall}} transaction to `to` with `value` (Native Currency)
     *          and pays `gasPrice` * `gasLimit` in `gasToken` token to `refundReceiver`
     * @dev the fees are always transferred, even if the user transaction fails
     *      this method doesn't perform any sanity check of the transaction, such as:
     *      - if the contract at `to` address has code or not
     *      - if the `gasToken` is a contract or not
     *      it is the responsibility of the caller to perform such checks
     * @param to destination address of Safe transaction
     * @param value ether value of Safe transaction
     * @param data data payload of Safe transaction
     * @param operation operation type of Safe transaction
     * @param safeTxGas gas that should be used for the Safe transaction
     * @param baseGas gas costs that are independent of the transaction execution(e.g. base transaction fee, signature check, payment of the refund)
     * @param gasPrice gas price that should be used for the payment calculation
     * @param gasToken token address (or 0 if ETH) that is used for the payment
     * @param refundReceiver address of receiver of gas payment (or 0 if tx.origin)
     * @return success Boolean indicating transaction's success
     */
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver
    ) public payable virtual returns (bool success) {
        bytes32 txHash;
        // use scope here to limit variable lifetime and prevent `stack too deep` errors
        {
            bytes memory txHashData = encodeTransactionData(
                // transaction info
                to,
                value,
                data,
                operation,
                safeTxGas,
                // payment info
                baseGas,
                gasPrice,
                gasToken,
                refundReceiver,
                // signature info
                nonce
            );
            // increase nonce and execute transaction.
            nonce++;
            txHash = keccak256(txHashData);
            checkApprovals(txHash, txHashData);
        }
        // we require some gas to emit the events (at least 2500) after the execution and some to perform code until the execution (500)
        // we also include the 1/64 in the check that is not send along with a call to counteract potential shortings because of EIP-150
        require(gasleft() >= max((safeTxGas * 64) / 63, safeTxGas + 2500) + 500, "Insufficient gas");
        // use scope here to limit variable lifetime and prevent `stack too deep` errors
        {
            uint256 gasUsed = gasleft();
            // if the gasPrice is 0 we assume that nearly all available gas can be used (it is always more than safeTxGas)
            // we only substract 2500 (compared to the 3000 before) to ensure that the amount passed is still higher than safeTxGas
            success = execute(to, value, data, operation, gasPrice == 0 ? (gasleft() - 2500) : safeTxGas);
            gasUsed = gasUsed - gasleft();
            // if no safeTxGas and no gasPrice was set (e.g. both are 0), then the internal tx is required to be successful
            // this makes it possible to use `estimateGas` without issues, as it searches for the minimum gas where the tx doesn't revert
            require(success || safeTxGas != 0 || gasPrice != 0, "Error during call");
            // we transfer the calculated tx costs to the tx.origin to avoid sending it to intermediate contracts that have made calls
            uint256 payment = 0;
            if (gasPrice > 0) {
                payment = handlePayment(gasUsed, baseGas, gasPrice, gasToken, refundReceiver);
            }
            if (success) emit ExecutionSuccess(txHash, payment);
            else emit ExecutionFailure(txHash, payment);
        }
    }

    /**
     * @notice marks hash `hashToApprove` as approved
     * @dev this can be used with a pre-approved hash transaction signature
     *      IMPORTANT: the approved hash stays approved forever. There's no revocation mechanism, so it behaves similarly to ECDSA signatures
     * @param hashToApprove the hash to mark as approved for signatures that are verified by this contract
     */
    function approveHash(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes32 hashToApprove
    ) external {
        require(owners[msg.sender] != address(0), "Now owner");

        bytes32 txHash = getTransactionHash(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            nonce
        );
        require(txHash == hashToApprove, "Incorrect data to approve");

        approvedHashes[msg.sender][hashToApprove] = 1;
        emit ApproveHash(
            hashToApprove,
            msg.sender,
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            nonce
        );
    }

    /**
     * @dev performs a delegatecall on a targetContract in the context of self
     * internally reverts execution to avoid side effects (making it static)
     *
     * this method reverts with data equal to `abi.encode(bool(success), bytes(response))`
     * specifically, the `returndata` after a call to this method will be:
     * `success:bool || response.length:uint256 || response:bytes`
     *
     * @param targetContract address of the contract containing the code to execute
     * @param calldataPayload calldata that should be sent to the target contract (encoded method name and arguments)
     */
    function simulateAndRevert(address targetContract, bytes memory calldataPayload) external {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let success := delegatecall(gas(), targetContract, add(calldataPayload, 0x20), mload(calldataPayload), 0, 0)

            mstore(0x00, success)
            mstore(0x20, returndatasize())
            returndatacopy(0x40, 0, returndatasize())
            revert(0, add(returndatasize(), 0x40))
        }
    }

    /**
     * @notice Receive function accepts native currency transactions.
     * @dev Emits an event with sender and received value.
     */
    receive() external payable {
        emit SafeReceived(msg.sender, msg.value);
    }
}