// SPDX-License-Identifier: MIT
pragma solidity =0.8.25 >=0.6.2 >=0.8.25 ^0.8.0 ^0.8.25;

// lib/forge-std/src/interfaces/IERC165.sol

interface IERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceID The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    /// uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceID` and
    /// `interfaceID` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}

// lib/forge-std/src/interfaces/IERC20.sol

/// @dev Interface of the ERC20 standard as defined in the EIP.
/// @dev This includes the optional name, symbol, and decimals metadata.
interface IERC20 {
    /// @dev Emitted when `value` tokens are moved from one account (`from`) to another (`to`).
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev Emitted when the allowance of a `spender` for an `owner` is set, where `value`
    /// is the new allowance.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Returns the amount of tokens in existence.
    function totalSupply() external view returns (uint256);

    /// @notice Returns the amount of tokens owned by `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Moves `amount` tokens from the caller's account to `to`.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Returns the remaining number of tokens that `spender` is allowed
    /// to spend on behalf of `owner`
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @dev Be aware of front-running risks: https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Moves `amount` tokens from `from` to `to` using the allowance mechanism.
    /// `amount` is then deducted from the caller's allowance.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Returns the name of the token.
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token.
    function symbol() external view returns (string memory);

    /// @notice Returns the decimals places of the token.
    function decimals() external view returns (uint8);
}

// lib/permit2/src/interfaces/IEIP712.sol

interface IEIP712 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// src/Context.sol

abstract contract AbstractContext {
    function _msgSender() internal view virtual returns (address);

    function _msgData() internal view virtual returns (bytes calldata);

    function _isForwarded() internal view virtual returns (bool);
}

abstract contract Context is AbstractContext {
    function _msgSender() internal view virtual override returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual override returns (bytes calldata) {
        return msg.data;
    }

    function _isForwarded() internal view virtual override returns (bool) {
        return false;
    }
}

// src/IERC721Owner.sol

interface IERC721Owner {
    function ownerOf(uint256) external view returns (address);
}

// src/allowanceholder/IAllowanceHolder.sol

interface IAllowanceHolder {
    /// @notice Executes against `target` with the `data` payload. Prior to execution, token permits
    ///         are temporarily stored for the duration of the transaction. These permits can be
    ///         consumed by the `operator` during the execution
    /// @notice `operator` consumes the funds during its operations by calling back into
    ///         `AllowanceHolder` with `transferFrom`, consuming a token permit.
    /// @dev Neither `exec` nor `transferFrom` check that `token` contains code.
    /// @dev msg.sender is forwarded to target appended to the msg data (similar to ERC-2771)
    /// @param operator An address which is allowed to consume the token permits
    /// @param token The ERC20 token the caller has authorised to be consumed
    /// @param amount The quantity of `token` the caller has authorised to be consumed
    /// @param target A contract to execute operations with `data`
    /// @param data The data to forward to `target`
    /// @return result The returndata from calling `target` with `data`
    /// @notice If calling `target` with `data` reverts, the revert is propagated
    function exec(address operator, address token, uint256 amount, address payable target, bytes calldata data)
        external
        payable
        returns (bytes memory result);

    /// @notice The counterpart to `exec` which allows for the consumption of token permits later
    ///         during execution
    /// @dev *DOES NOT* check that `token` contains code. This function vacuously succeeds if
    ///      `token` is empty.
    /// @dev can only be called by the `operator` previously registered in `exec`
    /// @param token The ERC20 token to transfer
    /// @param owner The owner of tokens to transfer
    /// @param recipient The destination/beneficiary of the ERC20 `transferFrom`
    /// @param amount The quantity of `token` to transfer`
    /// @return true
    function transferFrom(address token, address owner, address recipient, uint256 amount) external returns (bool);
}

// src/core/univ3forks/PancakeSwapV3.sol

address constant pancakeSwapV3Factory = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9;
bytes32 constant pancakeSwapV3InitHash = 0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2;
uint8 constant pancakeSwapV3ForkId = 1;

interface IPancakeSwapV3Callback {
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

// src/core/univ3forks/SolidlyV3.sol

address constant solidlyV3Factory = 0x70Fe4a44EA505cFa3A57b95cF2862D4fd5F0f687;
address constant solidlyV3SonicFactory = 0x777fAca731b17E8847eBF175c94DbE9d81A8f630;
bytes32 constant solidlyV3InitHash = 0xe9b68c5f77858eecac2e651646e208175e9b1359d68d0e14fc69f8c54e5010bf;
uint8 constant solidlyV3ForkId = 3;

interface ISolidlyV3Callback {
    function solidlyV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

// src/core/univ3forks/SushiswapV3.sol

address constant sushiswapV3MainnetFactory = 0xbACEB8eC6b9355Dfc0269C18bac9d6E2Bdc29C4F;
address constant sushiswapV3Factory = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4; // Base, Linea
address constant sushiswapV3ArbitrumFactory = 0x1af415a1EbA07a4986a52B6f2e7dE7003D82231e;
//address constant sushiswapV3AvalancheFactory = 0x3e603C14aF37EBdaD31709C4f848Fc6aD5BEc715;
//address constant sushiswapV3BlastFactory = 0x7680D4B43f3d1d54d6cfEeB2169463bFa7a6cf0d;
//address constant sushiswapV3BnbFactory = 0x126555dd55a39328F69400d6aE4F782Bd4C34ABb;
address constant sushiswapV3OptimismFactory = 0x9c6522117e2ed1fE5bdb72bb0eD5E3f2bdE7DBe0;
address constant sushiswapV3PolygonFactory = 0x917933899c6a5F8E37F31E19f92CdBFF7e8FF0e2;
address constant sushiswapV3ScrollFactory = 0x46B3fDF7b5CDe91Ac049936bF0bDb12c5d22202e;
address constant sushiswapV3GnosisFactory = 0xf78031CBCA409F2FB6876BDFDBc1b2df24cF9bEf;
//bytes32 constant sushiswapV3BlastInitHash = 0x8e13daee7f5a62e37e71bf852bcd44e7d16b90617ed2b17c24c2ee62411c5bae;
uint8 constant sushiswapV3ForkId = 2;

// src/core/univ3forks/UniswapV3.sol

address constant uniswapV3MainnetFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
address constant uniswapV3SepoliaFactory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
address constant uniswapV3BaseFactory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
address constant uniswapV3BnbFactory = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
address constant uniswapV3AvalancheFactory = 0x740b1c1de25031C31FF4fC9A62f554A55cdC1baD;
address constant uniswapV3BlastFactory = 0x792edAdE80af5fC680d96a2eD80A44247D2Cf6Fd;
address constant uniswapV3ScrollFactory = 0x70C62C8b8e801124A4Aa81ce07b637A3e83cb919;
address constant uniswapV3LineaFactory = 0x31FAfd4889FA1269F7a13A66eE0fB458f27D72A9;
address constant uniswapV3MantleFactory = 0x0d922Fb1Bc191F64970ac40376643808b4B74Df9;
address constant uniswapV3TaikoFactory = 0x75FC67473A91335B5b8F8821277262a13B38c9b3;
address constant uniswapV3WorldChainFactory = 0x7a5028BDa40e7B173C278C5342087826455ea25a;
address constant uniswapV3GnosisFactory = 0xe32F7dD7e3f098D518ff19A22d5f028e076489B1;
address constant uniswapV3SonicFactory = 0xcb2436774C3e191c85056d248EF4260ce5f27A9D;
address constant uniswapV3InkFactory = 0x640887A9ba3A9C53Ed27D0F7e8246A4F933f3424;
bytes32 constant uniswapV3InitHash = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
uint8 constant uniswapV3ForkId = 0;

interface IUniswapV3Callback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

// src/deployer/DeployerAddress.sol

address constant DEPLOYER = 0x00000000000004533Fe15556B1E086BB1A72cEae;

// src/utils/FreeMemory.sol

abstract contract FreeMemory {
    modifier DANGEROUS_freeMemory() {
        uint256 freeMemPtr;
        assembly ("memory-safe") {
            freeMemPtr := mload(0x40)
        }
        _;
        assembly ("memory-safe") {
            mstore(0x40, freeMemPtr)
        }
    }
}

// src/utils/Panic.sol

library Panic {
    function panic(uint256 code) internal pure {
        assembly ("memory-safe") {
            mstore(0x00, 0x4e487b71) // selector for `Panic(uint256)`
            mstore(0x20, code)
            revert(0x1c, 0x24)
        }
    }

    // https://docs.soliditylang.org/en/latest/control-structures.html#panic-via-assert-and-error-via-require
    uint8 internal constant GENERIC = 0x00;
    uint8 internal constant ASSERT_FAIL = 0x01;
    uint8 internal constant ARITHMETIC_OVERFLOW = 0x11;
    uint8 internal constant DIVISION_BY_ZERO = 0x12;
    uint8 internal constant ENUM_CAST = 0x21;
    uint8 internal constant CORRUPT_STORAGE_ARRAY = 0x22;
    uint8 internal constant POP_EMPTY_ARRAY = 0x31;
    uint8 internal constant ARRAY_OUT_OF_BOUNDS = 0x32;
    uint8 internal constant OUT_OF_MEMORY = 0x41;
    uint8 internal constant ZERO_FUNCTION_POINTER = 0x51;
}

// src/utils/Revert.sol

library Revert {
    function _revert(bytes memory reason) internal pure {
        assembly ("memory-safe") {
            revert(add(reason, 0x20), mload(reason))
        }
    }

    function maybeRevert(bool success, bytes memory reason) internal pure {
        if (!success) {
            _revert(reason);
        }
    }
}

// lib/forge-std/src/interfaces/IERC4626.sol

/// @dev Interface of the ERC4626 "Tokenized Vault Standard", as defined in
/// https://eips.ethereum.org/EIPS/eip-4626
interface IERC4626 is IERC20 {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
    /// @dev
    /// - MUST be an ERC-20 token contract.
    /// - MUST NOT revert.
    function asset() external view returns (address assetTokenAddress);

    /// @notice Returns the total amount of the underlying asset that is “managed” by Vault.
    /// @dev
    /// - SHOULD include any compounding that occurs from yield.
    /// - MUST be inclusive of any fees that are charged against assets in the Vault.
    /// - MUST NOT revert.
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /// @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
    /// scenario where all the conditions are met.
    /// @dev
    /// - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
    /// - MUST NOT show any variations depending on the caller.
    /// - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
    /// - MUST NOT revert.
    ///
    /// NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
    /// “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
    /// from.
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /// @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
    /// scenario where all the conditions are met.
    /// @dev
    /// - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
    /// - MUST NOT show any variations depending on the caller.
    /// - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
    /// - MUST NOT revert.
    ///
    /// NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
    /// “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
    /// from.
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /// @notice Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver,
    /// through a deposit call.
    /// @dev
    /// - MUST return a limited value if receiver is subject to some deposit limit.
    /// - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be deposited.
    /// - MUST NOT revert.
    function maxDeposit(address receiver) external view returns (uint256 maxAssets);

    /// @notice Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
    /// current on-chain conditions.
    /// @dev
    /// - MUST return as close to and no more than the exact amount of Vault shares that would be minted in a deposit
    ///   call in the same transaction. I.e. deposit should return the same or more shares as previewDeposit if called
    ///   in the same transaction.
    /// - MUST NOT account for deposit limits like those returned from maxDeposit and should always act as though the
    ///   deposit would be accepted, regardless if the user has enough tokens approved, etc.
    /// - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
    /// - MUST NOT revert.
    ///
    /// NOTE: any unfavorable discrepancy between convertToShares and previewDeposit SHOULD be considered slippage in
    /// share price or some other type of condition, meaning the depositor will lose assets by depositing.
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /// @notice Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
    /// @dev
    /// - MUST emit the Deposit event.
    /// - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
    ///   deposit execution, and are accounted for during deposit.
    /// - MUST revert if all of assets cannot be deposited (due to deposit limit being reached, slippage, the user not
    ///   approving enough underlying tokens to the Vault contract, etc).
    ///
    /// NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Returns the maximum amount of the Vault shares that can be minted for the receiver, through a mint call.
    /// @dev
    /// - MUST return a limited value if receiver is subject to some mint limit.
    /// - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of shares that may be minted.
    /// - MUST NOT revert.
    function maxMint(address receiver) external view returns (uint256 maxShares);

    /// @notice Allows an on-chain or off-chain user to simulate the effects of their mint at the current block, given
    /// current on-chain conditions.
    /// @dev
    /// - MUST return as close to and no fewer than the exact amount of assets that would be deposited in a mint call
    ///   in the same transaction. I.e. mint should return the same or fewer assets as previewMint if called in the
    ///   same transaction.
    /// - MUST NOT account for mint limits like those returned from maxMint and should always act as though the mint
    ///   would be accepted, regardless if the user has enough tokens approved, etc.
    /// - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
    /// - MUST NOT revert.
    ///
    /// NOTE: any unfavorable discrepancy between convertToAssets and previewMint SHOULD be considered slippage in
    /// share price or some other type of condition, meaning the depositor will lose assets by minting.
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /// @notice Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
    /// @dev
    /// - MUST emit the Deposit event.
    /// - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the mint
    ///   execution, and are accounted for during mint.
    /// - MUST revert if all of shares cannot be minted (due to deposit limit being reached, slippage, the user not
    ///   approving enough underlying tokens to the Vault contract, etc).
    ///
    /// NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the
    /// Vault, through a withdraw call.
    /// @dev
    /// - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
    /// - MUST NOT revert.
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    /// @notice Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block,
    /// given current on-chain conditions.
    /// @dev
    /// - MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a withdraw
    ///   call in the same transaction. I.e. withdraw should return the same or fewer shares as previewWithdraw if
    ///   called
    ///   in the same transaction.
    /// - MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though
    ///   the withdrawal would be accepted, regardless if the user has enough shares, etc.
    /// - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
    /// - MUST NOT revert.
    ///
    /// NOTE: any unfavorable discrepancy between convertToShares and previewWithdraw SHOULD be considered slippage in
    /// share price or some other type of condition, meaning the depositor will lose assets by depositing.
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /// @notice Burns shares from owner and sends exactly assets of underlying tokens to receiver.
    /// @dev
    /// - MUST emit the Withdraw event.
    /// - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
    ///   withdraw execution, and are accounted for during withdraw.
    /// - MUST revert if all of assets cannot be withdrawn (due to withdrawal limit being reached, slippage, the owner
    ///   not having enough shares, etc).
    ///
    /// Note that some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
    /// Those methods should be performed separately.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Returns the maximum amount of Vault shares that can be redeemed from the owner balance in the Vault,
    /// through a redeem call.
    /// @dev
    /// - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
    /// - MUST return balanceOf(owner) if owner is not subject to any withdrawal limit or timelock.
    /// - MUST NOT revert.
    function maxRedeem(address owner) external view returns (uint256 maxShares);

    /// @notice Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block,
    /// given current on-chain conditions.
    /// @dev
    /// - MUST return as close to and no more than the exact amount of assets that would be withdrawn in a redeem call
    ///   in the same transaction. I.e. redeem should return the same or more assets as previewRedeem if called in the
    ///   same transaction.
    /// - MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the
    ///   redemption would be accepted, regardless if the user has enough shares, etc.
    /// - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
    /// - MUST NOT revert.
    ///
    /// NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
    /// share price or some other type of condition, meaning the depositor will lose assets by redeeming.
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /// @notice Burns exactly shares from owner and sends assets of underlying tokens to receiver.
    /// @dev
    /// - MUST emit the Withdraw event.
    /// - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
    ///   redeem execution, and are accounted for during redeem.
    /// - MUST revert if all of shares cannot be redeemed (due to withdrawal limit being reached, slippage, the owner
    ///   not having enough shares, etc).
    ///
    /// NOTE: some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
    /// Those methods should be performed separately.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

// lib/permit2/src/interfaces/ISignatureTransfer.sol

/// @title SignatureTransfer
/// @notice Handles ERC20 token transfers through signature based actions
/// @dev Requires user's token approval on the Permit2 contract
interface ISignatureTransfer is IEIP712 {
    /// @notice Thrown when the requested amount for a transfer is larger than the permissioned amount
    /// @param maxAmount The maximum amount a spender can request to transfer
    error InvalidAmount(uint256 maxAmount);

    /// @notice Thrown when the number of tokens permissioned to a spender does not match the number of tokens being transferred
    /// @dev If the spender does not need to transfer the number of tokens permitted, the spender can request amount 0 to be transferred
    error LengthMismatch();

    /// @notice Emits an event when the owner successfully invalidates an unordered nonce.
    event UnorderedNonceInvalidation(address indexed owner, uint256 word, uint256 mask);

    /// @notice The token and amount details for a transfer signed in the permit transfer signature
    struct TokenPermissions {
        // ERC20 token address
        address token;
        // the maximum amount that can be spent
        uint256 amount;
    }

    /// @notice The signed permit message for a single token transfer
    struct PermitTransferFrom {
        TokenPermissions permitted;
        // a unique value for every token owner's signature to prevent signature replays
        uint256 nonce;
        // deadline on the permit signature
        uint256 deadline;
    }

    /// @notice Specifies the recipient address and amount for batched transfers.
    /// @dev Recipients and amounts correspond to the index of the signed token permissions array.
    /// @dev Reverts if the requested amount is greater than the permitted signed amount.
    struct SignatureTransferDetails {
        // recipient address
        address to;
        // spender requested amount
        uint256 requestedAmount;
    }

    /// @notice Used to reconstruct the signed permit message for multiple token transfers
    /// @dev Do not need to pass in spender address as it is required that it is msg.sender
    /// @dev Note that a user still signs over a spender address
    struct PermitBatchTransferFrom {
        // the tokens and corresponding amounts permitted for a transfer
        TokenPermissions[] permitted;
        // a unique value for every token owner's signature to prevent signature replays
        uint256 nonce;
        // deadline on the permit signature
        uint256 deadline;
    }

    /// @notice A map from token owner address and a caller specified word index to a bitmap. Used to set bits in the bitmap to prevent against signature replay protection
    /// @dev Uses unordered nonces so that permit messages do not need to be spent in a certain order
    /// @dev The mapping is indexed first by the token owner, then by an index specified in the nonce
    /// @dev It returns a uint256 bitmap
    /// @dev The index, or wordPosition is capped at type(uint248).max
    function nonceBitmap(address, uint256) external view returns (uint256);

    /// @notice Transfers a token using a signed permit message
    /// @dev Reverts if the requested amount is greater than the permitted signed amount
    /// @param permit The permit data signed over by the owner
    /// @param owner The owner of the tokens to transfer
    /// @param transferDetails The spender's requested transfer details for the permitted token
    /// @param signature The signature to verify
    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;

    /// @notice Transfers a token using a signed permit message
    /// @notice Includes extra data provided by the caller to verify signature over
    /// @dev The witness type string must follow EIP712 ordering of nested structs and must include the TokenPermissions type definition
    /// @dev Reverts if the requested amount is greater than the permitted signed amount
    /// @param permit The permit data signed over by the owner
    /// @param owner The owner of the tokens to transfer
    /// @param transferDetails The spender's requested transfer details for the permitted token
    /// @param witness Extra data to include when checking the user signature
    /// @param witnessTypeString The EIP-712 type definition for remaining string stub of the typehash
    /// @param signature The signature to verify
    function permitWitnessTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;

    /// @notice Transfers multiple tokens using a signed permit message
    /// @param permit The permit data signed over by the owner
    /// @param owner The owner of the tokens to transfer
    /// @param transferDetails Specifies the recipient and requested amount for the token transfer
    /// @param signature The signature to verify
    function permitTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;

    /// @notice Transfers multiple tokens using a signed permit message
    /// @dev The witness type string must follow EIP712 ordering of nested structs and must include the TokenPermissions type definition
    /// @notice Includes extra data provided by the caller to verify signature over
    /// @param permit The permit data signed over by the owner
    /// @param owner The owner of the tokens to transfer
    /// @param transferDetails Specifies the recipient and requested amount for the token transfer
    /// @param witness Extra data to include when checking the user signature
    /// @param witnessTypeString The EIP-712 type definition for remaining string stub of the typehash
    /// @param signature The signature to verify
    function permitWitnessTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;

    /// @notice Invalidates the bits specified in mask for the bitmap at the word position
    /// @dev The wordPos is maxed at type(uint248).max
    /// @param wordPos A number to index the nonceBitmap at
    /// @param mask A bitmap masked against msg.sender's current bitmap at the word position
    function invalidateUnorderedNonces(uint256 wordPos, uint256 mask) external;
}

// src/core/SettlerErrors.sol

/// @notice Thrown when an offset is not the expected value
error InvalidOffset();

/// @notice Thrown when a validating a target contract to avoid certain types of targets
error ConfusedDeputy();

/// @notice Thrown when a target contract is invalid given the context
error InvalidTarget();

/// @notice Thrown when validating the caller against the expected caller
error InvalidSender();

/// @notice Thrown in cases when using a Trusted Forwarder / AllowanceHolder is not allowed
error ForwarderNotAllowed();

/// @notice Thrown when a signature length is not the expected length
error InvalidSignatureLen();

/// @notice Thrown when a slippage limit is exceeded
error TooMuchSlippage(IERC20 token, uint256 expected, uint256 actual);

/// @notice Thrown when a byte array that is supposed to encode a function from ISettlerActions is
///         not recognized in context.
error ActionInvalid(uint256 i, bytes4 action, bytes data);

/// @notice Thrown when the encoded fork ID as part of UniswapV3 fork path is not on the list of
///         recognized forks for this chain.
error UnknownForkId(uint8 forkId);

/// @notice Thrown when an AllowanceHolder transfer's permit is past its deadline
error SignatureExpired(uint256 deadline);

/// @notice An internal error that should never be thrown. Thrown when a callback reenters the
///         entrypoint and attempts to clobber the existing callback.
error ReentrantCallback(uint256 callbackInt);

/// @notice An internal error that should never be thrown. This error can only be thrown by
///         non-metatx-supporting Settler instances. Thrown when a callback-requiring liquidity
///         source is called, but Settler never receives the callback.
error CallbackNotSpent(uint256 callbackInt);

/// @notice Thrown when a metatransaction has reentrancy.
error ReentrantMetatransaction(bytes32 oldWitness);

/// @notice Thrown when any transaction has reentrancy, not just taker-submitted or metatransaction.
error ReentrantPayer(address oldPayer);

/// @notice An internal error that should never be thrown. Thrown when a metatransaction fails to
///         spend a coupon.
error WitnessNotSpent(bytes32 oldWitness);

/// @notice An internal error that should never be thrown. Thrown when the payer is unset
///         unexpectedly.
error PayerSpent();

error DeltaNotPositive(IERC20 token);
error DeltaNotNegative(IERC20 token);
error ZeroSellAmount(IERC20 token);
error ZeroBuyAmount(IERC20 buyToken);
error BoughtSellToken(IERC20 sellToken);
error TokenHashCollision(IERC20 token0, IERC20 token1);
error ZeroToken();

/// @notice Thrown for liquidities that require a Newton-Raphson approximation to solve their
///         constant function when Newton-Raphson fails to converge on the solution in a
///         "reasonable" number of iterations.
error NotConverged();

// src/utils/UnsafeMath.sol

library UnsafeMath {
    function unsafeInc(uint256 x) internal pure returns (uint256) {
        unchecked {
            return x + 1;
        }
    }

    function unsafeInc(uint256 x, bool b) internal pure returns (uint256) {
        assembly ("memory-safe") {
            x := add(x, b)
        }
        return x;
    }

    function unsafeInc(int256 x) internal pure returns (int256) {
        unchecked {
            return x + 1;
        }
    }

    function unsafeDec(uint256 x) internal pure returns (uint256) {
        unchecked {
            return x - 1;
        }
    }

    function unsafeDec(int256 x) internal pure returns (int256) {
        unchecked {
            return x - 1;
        }
    }

    function unsafeNeg(int256 x) internal pure returns (int256) {
        unchecked {
            return -x;
        }
    }

    function unsafeDiv(uint256 numerator, uint256 denominator) internal pure returns (uint256 quotient) {
        assembly ("memory-safe") {
            quotient := div(numerator, denominator)
        }
    }

    function unsafeDiv(int256 numerator, int256 denominator) internal pure returns (int256 quotient) {
        assembly ("memory-safe") {
            quotient := sdiv(numerator, denominator)
        }
    }

    function unsafeMod(uint256 numerator, uint256 denominator) internal pure returns (uint256 remainder) {
        assembly ("memory-safe") {
            remainder := mod(numerator, denominator)
        }
    }

    function unsafeMod(int256 numerator, int256 denominator) internal pure returns (int256 remainder) {
        assembly ("memory-safe") {
            remainder := smod(numerator, denominator)
        }
    }

    function unsafeMulMod(uint256 a, uint256 b, uint256 m) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := mulmod(a, b, m)
        }
    }

    function unsafeAddMod(uint256 a, uint256 b, uint256 m) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := addmod(a, b, m)
        }
    }

    function unsafeDivUp(uint256 n, uint256 d) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := add(gt(mod(n, d), 0x00), div(n, d))
        }
    }
}

library Math_0 {
    function or(bool a, bool b) internal pure returns (bool c) {
        assembly ("memory-safe") {
            c := or(a, b)
        }
    }

    function inc(uint256 x, bool c) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := add(x, c)
        }
        if (r < x) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
    }

    function dec(uint256 x, bool c) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := sub(x, c)
        }
        if (r > x) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
    }
}

// src/vendor/SafeTransferLib.sol

/// @notice Safe ETH and ERC20 transfer library that gracefully handles missing return values.
/// @author Modified from Solady (https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SafeTransferLib.sol)
/// @dev Note that none of the functions in this library check that a token has code at all! That responsibility is delegated to the caller.
library SafeTransferLib {
    /*//////////////////////////////////////////////////////////////
                             ETH OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function safeTransferETH(address payable to, uint256 amount) internal {
        assembly ("memory-safe") {
            // Transfer the ETH and revert if it fails.
            if iszero(call(gas(), to, amount, 0x00, 0x00, 0x00, 0x00)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function fastBalanceOf(IERC20 token, address acct) internal view returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x14, acct) // Store the `acct` argument.
            mstore(0x00, 0x70a08231000000000000000000000000) // Selector for `balanceOf(address)`, with `acct`'s padding.

            // Call and check for revert. Storing the selector with padding in
            // memory at 0 results in a start of calldata at offset 16. Calldata
            // is 36 bytes long (4 bytes selector, 32 bytes argument)
            if iszero(staticcall(gas(), token, 0x10, 0x24, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            // Check for short calldata and missing code
            if iszero(gt(returndatasize(), 0x1f)) { revert(0x00, 0x00) }

            r := mload(0x00)
        }
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        assembly ("memory-safe") {
            let ptr := mload(0x40) // Cache the free memory pointer.

            mstore(0x60, amount) // Store the `amount` argument.
            mstore(0x40, to) // Store the `to` argument.
            mstore(0x2c, shl(0x60, from)) // Store the `from` argument. (Clears `to`'s padding.)
            mstore(0x0c, 0x23b872dd000000000000000000000000) // Selector for `transferFrom(address,address,uint256)`, with `from`'s padding.

            // Calldata starts at offset 28 and is 100 bytes long (3 * 32 + 4).
            // If there is returndata (optional) we copy the first 32 bytes into the first slot of memory.
            if iszero(call(gas(), token, 0x00, 0x1c, 0x64, 0x00, 0x20)) {
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            // We check that the call either returned exactly 1 [true] (can't just be non-zero
            // data), or had no return data.
            if iszero(or(and(eq(mload(0x00), 0x01), gt(returndatasize(), 0x1f)), iszero(returndatasize()))) {
                mstore(0x00, 0x7939f424) // Selector for `TransferFromFailed()`
                revert(0x1c, 0x04)
            }

            mstore(0x60, 0x00) // Restore the zero slot to zero.
            mstore(0x40, ptr) // Restore the free memory pointer.
        }
    }

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            // Storing `amount` clobbers the upper bits of the free memory pointer, but those bits
            // can never be set without running into an OOG, so it's safe. We'll restore them to
            // zero at the end.
            mstore(0x00, 0xa9059cbb000000000000000000000000) // Selector for `transfer(address,uint256)`, with `to`'s padding.

            // Calldata starts at offset 16 and is 68 bytes long (2 * 32 + 4).
            // If there is returndata (optional) we copy the first 32 bytes into the first slot of memory.
            if iszero(call(gas(), token, 0x00, 0x10, 0x44, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            // We check that the call either returned exactly 1 [true] (can't just be non-zero
            // data), or had no return data.
            if iszero(or(and(eq(mload(0x00), 0x01), gt(returndatasize(), 0x1f)), iszero(returndatasize()))) {
                mstore(0x00, 0x90b8ec18) // Selector for `TransferFailed()`
                revert(0x1c, 0x04)
            }

            mstore(0x34, 0x00) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    function safeApprove(IERC20 token, address to, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            // Storing `amount` clobbers the upper bits of the free memory pointer, but those bits
            // can never be set without running into an OOG, so it's safe. We'll restore them to
            // zero at the end.
            mstore(0x00, 0x095ea7b3000000000000000000000000) // Selector for `approve(address,uint256)`, with `to`'s padding.

            // Calldata starts at offset 16 and is 68 bytes long (2 * 32 + 4).
            // If there is returndata (optional) we copy the first 32 bytes into the first slot of memory.
            if iszero(call(gas(), token, 0x00, 0x10, 0x44, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            // We check that the call either returned exactly 1 [true] (can't just be non-zero
            // data), or had no return data.
            if iszero(or(and(eq(mload(0x00), 0x01), gt(returndatasize(), 0x1f)), iszero(returndatasize()))) {
                mstore(0x00, 0x3e3f8f73) // Selector for `ApproveFailed()`
                revert(0x1c, 0x04)
            }

            mstore(0x34, 0x00) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    function safeApproveIfBelow(IERC20 token, address spender, uint256 amount) internal {
        uint256 allowance = token.allowance(address(this), spender);
        if (allowance < amount) {
            if (allowance != 0) {
                safeApprove(token, spender, 0);
            }
            safeApprove(token, spender, type(uint256).max);
        }
    }
}

// src/ISettlerActions.sol

interface ISettlerActions {
    /// @dev Transfer funds from msg.sender Permit2.
    function TRANSFER_FROM(address recipient, ISignatureTransfer.PermitTransferFrom memory permit, bytes memory sig)
        external;

    /// @dev Transfer funds from metatransaction requestor into the Settler contract using Permit2. Only for use in `Settler.executeMetaTxn` where the signature is provided as calldata
    function METATXN_TRANSFER_FROM(address recipient, ISignatureTransfer.PermitTransferFrom memory permit) external;

    /// @dev Settle an RfqOrder between maker and taker transfering funds directly between the parties
    // Post-req: Payout if recipient != taker
    function RFQ_VIP(
        address recipient,
        ISignatureTransfer.PermitTransferFrom memory makerPermit,
        address maker,
        bytes memory makerSig,
        ISignatureTransfer.PermitTransferFrom memory takerPermit,
        bytes memory takerSig
    ) external;

    /// @dev Settle an RfqOrder between maker and taker transfering funds directly between the parties for the entire amount
    function METATXN_RFQ_VIP(
        address recipient,
        ISignatureTransfer.PermitTransferFrom memory makerPermit,
        address maker,
        bytes memory makerSig,
        ISignatureTransfer.PermitTransferFrom memory takerPermit
    ) external;

    /// @dev Settle an RfqOrder between Maker and Settler. Transfering funds from the Settler contract to maker.
    /// Retaining funds in the settler contract.
    // Pre-req: Funded
    // Post-req: Payout
    function RFQ(
        address recipient,
        ISignatureTransfer.PermitTransferFrom memory permit,
        address maker,
        bytes memory makerSig,
        address takerToken,
        uint256 maxTakerAmount
    ) external;

    function UNISWAPV4(
        address recipient,
        address sellToken,
        uint256 bps,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        uint256 amountOutMin
    ) external;
    function UNISWAPV4_VIP(
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 amountOutMin
    ) external;
    function METATXN_UNISWAPV4_VIP(
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 amountOutMin
    ) external;

    function BALANCERV3(
        address recipient,
        address sellToken,
        uint256 bps,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        uint256 amountOutMin
    ) external;
    function BALANCERV3_VIP(
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 amountOutMin
    ) external;
    function METATXN_BALANCERV3_VIP(
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 amountOutMin
    ) external;

    /// @dev Trades against UniswapV3 using the contracts balance for funding
    // Pre-req: Funded
    // Post-req: Payout
    function UNISWAPV3(address recipient, uint256 bps, bytes memory path, uint256 amountOutMin) external;
    /// @dev Trades against UniswapV3 using user funds via Permit2 for funding
    function UNISWAPV3_VIP(
        address recipient,
        bytes memory path,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 amountOutMin
    ) external;
    /// @dev Trades against UniswapV3 using user funds via Permit2 for funding. Metatransaction variant. Signature is over all actions.
    function METATXN_UNISWAPV3_VIP(
        address recipient,
        bytes memory path,
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 amountOutMin
    ) external;

    function MAKERPSM(address recipient, uint256 bps, bool buyGem, uint256 amountOutMin) external;

    function CURVE_TRICRYPTO_VIP(
        address recipient,
        uint80 poolInfo,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 minBuyAmount
    ) external;
    function METATXN_CURVE_TRICRYPTO_VIP(
        address recipient,
        uint80 poolInfo,
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 minBuyAmount
    ) external;

    function DODOV1(address sellToken, uint256 bps, address pool, bool quoteForBase, uint256 minBuyAmount) external;
    function DODOV2(
        address recipient,
        address sellToken,
        uint256 bps,
        address pool,
        bool quoteForBase,
        uint256 minBuyAmount
    ) external;

    function VELODROME(address recipient, uint256 bps, address pool, uint24 swapInfo, uint256 minBuyAmount) external;

    /// @dev Trades against MaverickV2 using the contracts balance for funding
    /// This action does not use the MaverickV2 callback, so it takes an arbitrary pool address to make calls against.
    /// Passing `tokenAIn` as a parameter actually saves gas relative to introspecting the pool's `tokenA()` accessor.
    function MAVERICKV2(
        address recipient,
        address sellToken,
        uint256 bps,
        address pool,
        bool tokenAIn,
        uint256 minBuyAmount
    ) external;
    /// @dev Trades against MaverickV2, spending the taker's coupon inside the callback
    /// This action requires the use of the MaverickV2 callback, so we take the MaverickV2 CREATE2 salt as an argument to derive the pool address from the trusted factory and inithash.
    /// @param salt is formed as `keccak256(abi.encode(feeAIn, feeBIn, tickSpacing, lookback, tokenA, tokenB, kinds, address(0)))`
    function MAVERICKV2_VIP(
        address recipient,
        bytes32 salt,
        bool tokenAIn,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 minBuyAmount
    ) external;
    /// @dev Trades against MaverickV2, spending the taker's coupon inside the callback; metatransaction variant
    function METATXN_MAVERICKV2_VIP(
        address recipient,
        bytes32 salt,
        bool tokenAIn,
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 minBuyAmount
    ) external;

    /// @dev Trades against UniswapV2 using the contracts balance for funding
    /// @param swapInfo is encoded as the upper 16 bits as the fee of the pool in bps, the second
    ///                 lowest bit as "sell token has transfer fee", and the lowest bit as the
    ///                 "token0 for token1" flag.
    function UNISWAPV2(
        address recipient,
        address sellToken,
        uint256 bps,
        address pool,
        uint24 swapInfo,
        uint256 amountOutMin
    ) external;

    function POSITIVE_SLIPPAGE(address recipient, address token, uint256 expectedAmount) external;

    /// @dev Trades against a basic AMM which follows the approval, transferFrom(msg.sender) interaction
    // Pre-req: Funded
    // Post-req: Payout
    function BASIC(address sellToken, uint256 bps, address pool, uint256 offset, bytes calldata data) external;
}

// src/allowanceholder/AllowanceHolderContext.sol

abstract contract AllowanceHolderContext is Context {
    IAllowanceHolder internal constant _ALLOWANCE_HOLDER = IAllowanceHolder(0x0000000000001fF3684f28c67538d4D072C22734);

    function _isForwarded() internal view virtual override returns (bool) {
        return super._isForwarded() || super._msgSender() == address(_ALLOWANCE_HOLDER);
    }

    function _msgSender() internal view virtual override returns (address sender) {
        sender = super._msgSender();
        if (sender == address(_ALLOWANCE_HOLDER)) {
            // ERC-2771 like usage where the _trusted_ `AllowanceHolder` has appended the appropriate
            // msg.sender to the msg data
            assembly ("memory-safe") {
                sender := shr(0x60, calldataload(sub(calldatasize(), 0x14)))
            }
        }
    }

    // this is here to avoid foot-guns and make it very explicit that we intend
    // to pass the confused deputy check in AllowanceHolder
    function balanceOf(address) external pure {
        assembly ("memory-safe") {
            mstore8(0x00, 0x00)
            return(0x00, 0x01)
        }
    }
}

// src/deployer/TwoStepOwnable.sol

interface IOwnable is IERC165 {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function owner() external view returns (address);

    function transferOwnership(address) external returns (bool);

    error PermissionDenied();
    error ZeroAddress();
}

abstract contract AbstractOwnable is IOwnable {
    // This looks stupid (and it is), but this is required due to the glaring
    // deficiencies in Solidity's inheritance system.

    function _requireOwner() internal view virtual;

    /// This function should be overridden exactly once. This provides the base
    /// implementation. Mixin classes may modify `owner`.
    function _ownerImpl() internal view virtual returns (address);

    function owner() public view virtual override returns (address) {
        return _ownerImpl();
    }

    function _setOwner(address) internal virtual;

    constructor() {
        assert(type(IOwnable).interfaceId == 0x7f5828d0);
        assert(type(IERC165).interfaceId == 0x01ffc9a7);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IOwnable).interfaceId;
    }

    /// This modifier is not virtual on purpose; override _requireOwner instead.
    modifier onlyOwner() {
        _requireOwner();
        _;
    }
}

abstract contract AddressSlotStorage {
    type AddressSlot is bytes32;

    function _get(AddressSlot s) internal view returns (address r) {
        assembly ("memory-safe") {
            r := sload(s)
        }
    }

    function _set(AddressSlot s, address v) internal {
        assembly ("memory-safe") {
            sstore(s, v)
        }
    }
}

abstract contract OwnableStorageBase is AddressSlotStorage {
    function _ownerSlot() internal pure virtual returns (AddressSlot);
}

abstract contract OwnableStorage is OwnableStorageBase {
    address private _owner;

    function _ownerSlot() internal pure override returns (AddressSlot r) {
        assembly ("memory-safe") {
            r := _owner.slot
        }
    }

    constructor() {
        assert(AddressSlot.unwrap(_ownerSlot()) == bytes32(0));
    }
}

abstract contract OwnableBase is AbstractContext, AbstractOwnable {
    function renounceOwnership() public virtual returns (bool);
}

abstract contract OwnableImpl is OwnableStorageBase, OwnableBase {
    function _ownerImpl() internal view override returns (address) {
        return _get(_ownerSlot());
    }

    function _setOwner(address newOwner) internal virtual override {
        emit OwnershipTransferred(owner(), newOwner);
        _set(_ownerSlot(), newOwner);
    }

    function _requireOwner() internal view override {
        if (_msgSender() != owner()) {
            revert PermissionDenied();
        }
    }

    function renounceOwnership() public virtual override onlyOwner returns (bool) {
        _setOwner(address(0));
        return true;
    }

    function transferOwnership(address newOwner) public virtual override onlyOwner returns (bool) {
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }
        _setOwner(newOwner);
        return true;
    }
}

abstract contract Ownable is OwnableStorage, OwnableImpl {}

abstract contract AbstractTwoStepOwnable is AbstractOwnable {
    function _requirePendingOwner() internal view virtual;

    function pendingOwner() public view virtual returns (address);

    function _setPendingOwner(address) internal virtual;

    /// This modifier is not virtual on purpose; override _requirePendingOwner
    /// instead.
    modifier onlyPendingOwner() {
        _requirePendingOwner();
        _;
    }

    event OwnershipPending(address indexed);
}

abstract contract TwoStepOwnableStorageBase is AddressSlotStorage {
    function _pendingOwnerSlot() internal pure virtual returns (AddressSlot);
}

abstract contract TwoStepOwnableStorage is TwoStepOwnableStorageBase {
    address private _pendingOwner;

    function _pendingOwnerSlot() internal pure override returns (AddressSlot r) {
        assembly ("memory-safe") {
            r := _pendingOwner.slot
        }
    }

    constructor() {
        assert(AddressSlot.unwrap(_pendingOwnerSlot()) == bytes32(uint256(1)));
    }
}

abstract contract TwoStepOwnableBase is OwnableBase, AbstractTwoStepOwnable {}

abstract contract TwoStepOwnableImpl is TwoStepOwnableStorageBase, TwoStepOwnableBase {
    function pendingOwner() public view override returns (address) {
        return _get(_pendingOwnerSlot());
    }

    function _setPendingOwner(address newPendingOwner) internal override {
        emit OwnershipPending(newPendingOwner);
        _set(_pendingOwnerSlot(), newPendingOwner);
    }

    function renounceOwnership() public virtual override onlyOwner returns (bool) {
        if (pendingOwner() != address(0)) {
            _setPendingOwner(address(0));
        }
        _setOwner(address(0));
        return true;
    }

    function transferOwnership(address newOwner) public virtual override onlyOwner returns (bool) {
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }
        _setPendingOwner(newOwner);
        return true;
    }

    function _requirePendingOwner() internal view override {
        if (_msgSender() != pendingOwner()) {
            revert PermissionDenied();
        }
    }

    function acceptOwnership() public onlyPendingOwner returns (bool) {
        _setOwner(_msgSender());
        _setPendingOwner(address(0));
        return true;
    }

    function rejectOwnership() public onlyPendingOwner returns (bool) {
        _setPendingOwner(address(0));
        return true;
    }
}

abstract contract TwoStepOwnable is OwnableStorage, OwnableImpl, TwoStepOwnableStorage, TwoStepOwnableImpl {
    function renounceOwnership() public override(OwnableImpl, TwoStepOwnableImpl) returns (bool) {
        return TwoStepOwnableImpl.renounceOwnership();
    }

    function transferOwnership(address newOwner) public override(OwnableImpl, TwoStepOwnableImpl) returns (bool) {
        return TwoStepOwnableImpl.transferOwnership(newOwner);
    }
}

// src/utils/512Math.sol

/*

WARNING *** WARNING *** WARNING *** WARNING *** WARNING *** WARNING *** WARNING
  ***                                                                     ***
WARNING                     This code is unaudited                      WARNING
  ***                                                                     ***
WARNING *** WARNING *** WARNING *** WARNING *** WARNING *** WARNING *** WARNING

*/

/// The type uint512 behaves as if it were declared as
///     struct uint512 {
///         uint256 hi;
///         uint256 lo;
///     }
/// However, returning `memory` references from internal functions is impossible
/// to do efficiently, especially when the functions are small and are called
/// frequently. Therefore, we assume direct control over memory allocation using
/// the functions `tmp()` and `alloc()` defined below. If you need to pass
/// 512-bit integers between contracts (generally a bad idea), the struct
/// `uint512_external` defined at the end of this file is provided for this
/// purpose and has exactly the definition you'd expect (as well as convenient
/// conversion functions).
///
/// MAKING A DECLARATION OF THE FOLLOWING FORM WILL CAUSE UNEXPECTED BEHAVIOR:
///     uint512 x;
/// INSTEAD OF DOING THAT, YOU MUST USE `alloc()`, LIKE THIS:
///     uint512 x = alloc();
/// IF YOU REALLY WANTED TO DO THAT (ADVANCED USAGE) THEN FOR CLARITY, WRITE THE
/// FOLLOWING:
///     uint512 x = tmp();
///
/// While user-defined arithmetic operations (i.e. +, -, *, %, /) are provided
/// for `uint512`, they are not gas-optimal, full-featured, or composable. You
/// will get a revert upon incorrect usage. Their primary usage is when a simple
/// arithmetic operation needs to be performed followed by a comparison (e.g. <,
/// >, ==, etc.) or conversion to a pair of `uint256`s (i.e. `.into()`). The use
/// of the user-defined arithmetic operations is not composable with the usage
/// of `tmp()`.
///
/// In general, correct usage of `uint512` requires always specifying the output
/// location of each operation. For each `o*` operation (mnemonic:
/// out-of-place), the first argument is the output location and the remaining
/// arguments are the input. For each `i*` operation (mnemonic: in-place), the
/// first argument is both input and output and the remaining arguments are
/// purely input. For each `ir*` operation (mnemonic: in-place reverse; only for
/// non-commutative operations), the semantics of the input arguments are
/// flipped (i.e. `irsub(foo, bar)` is semantically equivalent to `foo = bar -
/// foo`); the first argument is still the output location. Only `irsub`,
/// `irmod`, `irdiv`, `irmodAlt`, and `irdivAlt` exist. Unless otherwise noted,
/// the return value of each function is the output location. This supports
/// chaining/pipeline/tacit-style programming.
///
/// All provided arithmetic operations behave as if they were inside an
/// `unchecked` block. We assume that because you're reaching for 512-bit math,
/// you have domain knowledge about the range of values that you will
/// encounter. Overflow causes truncation, not a revert. Division or modulo by
/// zero still causes a panic revert with code 18 (identical behavior to
/// "normal" unchecked arithmetic).
///
/// Three additional arithmetic operations are provided, bare `sub`, `mod`, and
/// `div`. These are provided for use when it is known that the result of the
/// operation will fit into 256 bits. This fact is not checked, but more
/// efficient algorithms are employed assuming this. The result is a `uint256`.
///
/// The operations `*mod` and `*div` with 512-bit denominator are `view` instead
/// of `pure` because they make use of the MODEXP (5) precompile. Some EVM L2s
/// and sidechains do not support MODEXP with 512-bit arguments. On those
/// chains, the `*modAlt` and `*divAlt` functions are provided. These functions
/// are truly `pure` and do not rely on MODEXP at all. The downside is that they
/// consume slightly (really only *slightly*) more gas.
///
/// ## Full list of provided functions
///
/// Unless otherwise noted, all functions return `(uint512)`
///
/// ### Utility
///
/// * from(uint256)
/// * from(uint256,uint256) -- The EVM is big-endian. The most-significant word is first.
/// * from(uint512) -- performs a copy
/// * into() returns (uint256,uint256) -- Again, the most-significant word is first.
/// * toExternal(uint512) returns (uint512_external memory)
///
/// ### Comparison (all functions return `(bool)`)
///
/// * isZero(uint512)
/// * isMax(uint512)
/// * eq(uint512,uint256)
/// * eq(uint512,uint512)
/// * ne(uint512,uint256)
/// * ne(uint512,uint512)
/// * gt(uint512,uint256)
/// * gt(uint512,uint512)
/// * ge(uint512,uint256)
/// * ge(uint512,uint512)
/// * lt(uint512,uint256)
/// * lt(uint512,uint512)
/// * le(uint512,uint256)
/// * le(uint512,uint512)
///
/// ### Addition
///
/// * oadd(uint512,uint256,uint256) -- iadd(uint256,uint256) is not provided for somewhat obvious reasons
/// * oadd(uint512,uint512,uint256)
/// * iadd(uint512,uint256)
/// * oadd(uint512,uint512,uint512)
/// * iadd(uint512,uint512)
///
/// ### Subtraction
///
/// * sub(uint512,uint256) returns (uint256)
/// * sub(uint512,uint512) returns (uint256)
/// * osub(uint512,uint512,uint256)
/// * isub(uint512,uint256)
/// * osub(uint512,uint512,uint512)
/// * isub(uint512,uint512)
/// * irsub(uint512,uint512)
///
/// ### Multiplication
///
/// * omul(uint512,uint256,uint256)
/// * omul(uint512,uint512,uint256)
/// * imul(uint512,uint256)
/// * omul(uint512,uint512,uint512)
/// * imul(uint512,uint512)
///
/// ### Modulo
///
/// * mod(uint512,uint256) returns (uint256) -- mod(uint512,uint512) is not provided for less obvious reasons
/// * omod(uint512,uint512,uint512)
/// * imod(uint512,uint512)
/// * irmod(uint512,uint512)
/// * omodAlt(uint512,uint512,uint512)
/// * imodAlt(uint512,uint512)
/// * irmodAlt(uint512,uint512)
///
/// ### Division
///
/// * div(uint512,uint256) returns (uint256)
/// * div(uint512,uint512) returns (uint256)
/// * odiv(uint512,uint512,uint256)
/// * idiv(uint512,uint256)
/// * odiv(uint512,uint512,uint512)
/// * idiv(uint512,uint512)
/// * irdiv(uint512,uint512)
/// * divAlt(uint512,uint512) returns (uint256) -- divAlt(uint512,uint256) is not provided because div(uint512,uint256) is suitable for chains without MODEXP
/// * odivAlt(uint512,uint512,uint512)
/// * idivAlt(uint512,uint512)
/// * irdivAlt(uint512,uint512)
type uint512 is bytes32;

function alloc() pure returns (uint512 r) {
    assembly ("memory-safe") {
        r := mload(0x40)
        mstore(0x40, add(0x40, r))
    }
}

function tmp() pure returns (uint512 r) {}

library Lib512MathAccessors {
    function from(uint512 r, uint256 x) internal pure returns (uint512 r_out) {
        assembly ("memory-safe") {
            mstore(r, 0x00)
            mstore(add(0x20, r), x)
            r_out := r
        }
    }

    function from(uint512 r, uint256 x_hi, uint256 x_lo) internal pure returns (uint512 r_out) {
        assembly ("memory-safe") {
            mstore(r, x_hi)
            mstore(add(0x20, r), x_lo)
            r_out := r
        }
    }

    function from(uint512 r, uint512 x) internal pure returns (uint512 r_out) {
        assembly ("memory-safe") {
            // Paradoxically, using `mload` and `mstore` here (instead of
            // `mcopy`) produces more optimal code because it gives solc the
            // opportunity to optimize-out the use of memory entirely, in
            // typical usage. As a happy side effect, it also means that we
            // don't have to deal with Cancun hardfork compatibility issues.
            mstore(r, mload(x))
            mstore(add(0x20, r), mload(add(0x20, x)))
            r_out := r
        }
    }

    function into(uint512 x) internal pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            r_hi := mload(x)
            r_lo := mload(add(0x20, x))
        }
    }
}

using Lib512MathAccessors for uint512 global;

library Lib512MathComparisons {
    function isZero(uint512 x) internal pure returns (bool r) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        assembly ("memory-safe") {
            r := iszero(or(x_hi, x_lo))
        }
    }

    function isMax(uint512 x) internal pure returns (bool r) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        assembly ("memory-safe") {
            r := iszero(not(and(x_hi, x_lo)))
        }
    }

    function eq(uint512 x, uint256 y) internal pure returns (bool r) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        assembly ("memory-safe") {
            r := and(iszero(x_hi), eq(x_lo, y))
        }
    }

    function gt(uint512 x, uint256 y) internal pure returns (bool r) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        assembly ("memory-safe") {
            r := or(gt(x_hi, 0x00), gt(x_lo, y))
        }
    }

    function lt(uint512 x, uint256 y) internal pure returns (bool r) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        assembly ("memory-safe") {
            r := and(iszero(x_hi), lt(x_lo, y))
        }
    }

    function ne(uint512 x, uint256 y) internal pure returns (bool) {
        return !eq(x, y);
    }

    function ge(uint512 x, uint256 y) internal pure returns (bool) {
        return !lt(x, y);
    }

    function le(uint512 x, uint256 y) internal pure returns (bool) {
        return !gt(x, y);
    }

    function eq(uint512 x, uint512 y) internal pure returns (bool r) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 y_hi, uint256 y_lo) = y.into();
        assembly ("memory-safe") {
            r := and(eq(x_hi, y_hi), eq(x_lo, y_lo))
        }
    }

    function gt(uint512 x, uint512 y) internal pure returns (bool r) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 y_hi, uint256 y_lo) = y.into();
        assembly ("memory-safe") {
            r := or(gt(x_hi, y_hi), and(eq(x_hi, y_hi), gt(x_lo, y_lo)))
        }
    }

    function lt(uint512 x, uint512 y) internal pure returns (bool r) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 y_hi, uint256 y_lo) = y.into();
        assembly ("memory-safe") {
            r := or(lt(x_hi, y_hi), and(eq(x_hi, y_hi), lt(x_lo, y_lo)))
        }
    }

    function ne(uint512 x, uint512 y) internal pure returns (bool) {
        return !eq(x, y);
    }

    function ge(uint512 x, uint512 y) internal pure returns (bool) {
        return !lt(x, y);
    }

    function le(uint512 x, uint512 y) internal pure returns (bool) {
        return !gt(x, y);
    }
}

using Lib512MathComparisons for uint512 global;

function __eq(uint512 x, uint512 y) pure returns (bool) {
    return x.eq(y);
}

function __gt(uint512 x, uint512 y) pure returns (bool) {
    return x.gt(y);
}

function __lt(uint512 x, uint512 y) pure returns (bool r) {
    return x.lt(y);
}

function __ne(uint512 x, uint512 y) pure returns (bool) {
    return x.ne(y);
}

function __ge(uint512 x, uint512 y) pure returns (bool) {
    return x.ge(y);
}

function __le(uint512 x, uint512 y) pure returns (bool) {
    return x.le(y);
}

using {__eq as ==, __gt as >, __lt as <, __ne as !=, __ge as >=, __le as <=} for uint512 global;

library Lib512MathArithmetic {
    using UnsafeMath for uint256;

    function oadd(uint512 r, uint256 x, uint256 y) internal pure returns (uint512) {
        uint256 r_hi;
        uint256 r_lo;
        assembly ("memory-safe") {
            r_lo := add(x, y)
            // `lt(r_lo, x)` indicates overflow in the lower addition. We can
            // add the bool directly to the integer to perform carry
            r_hi := lt(r_lo, x)
        }
        return r.from(r_hi, r_lo);
    }

    function oadd(uint512 r, uint512 x, uint256 y) internal pure returns (uint512) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        uint256 r_hi;
        uint256 r_lo;
        assembly ("memory-safe") {
            r_lo := add(x_lo, y)
            // `lt(r_lo, x_lo)` indicates overflow in the lower
            // addition. Overflow in the high limb is simply ignored
            r_hi := add(x_hi, lt(r_lo, x_lo))
        }
        return r.from(r_hi, r_lo);
    }

    function iadd(uint512 r, uint256 y) internal pure returns (uint512) {
        return oadd(r, r, y);
    }

    function _add(uint256 x_hi, uint256 x_lo, uint256 y_hi, uint256 y_lo)
        private
        pure
        returns (uint256 r_hi, uint256 r_lo)
    {
        assembly ("memory-safe") {
            r_lo := add(x_lo, y_lo)
            // `lt(r_lo, x_lo)` indicates overflow in the lower
            // addition. Overflow in the high limb is simply ignored.
            r_hi := add(add(x_hi, y_hi), lt(r_lo, x_lo))
        }
    }

    function oadd(uint512 r, uint512 x, uint512 y) internal pure returns (uint512) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 y_hi, uint256 y_lo) = y.into();
        (uint256 r_hi, uint256 r_lo) = _add(x_hi, x_lo, y_hi, y_lo);
        return r.from(r_hi, r_lo);
    }

    function iadd(uint512 r, uint512 y) internal pure returns (uint512) {
        return oadd(r, r, y);
    }

    function _sub(uint256 x_hi, uint256 x_lo, uint256 y) private pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            r_lo := sub(x_lo, y)
            // `gt(r_lo, x_lo)` indicates underflow in the lower subtraction. We
            // can subtract the bool directly from the integer to perform carry.
            r_hi := sub(x_hi, gt(r_lo, x_lo))
        }
    }

    function osub(uint512 r, uint512 x, uint256 y) internal pure returns (uint512) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 r_hi, uint256 r_lo) = _sub(x_hi, x_lo, y);
        return r.from(r_hi, r_lo);
    }

    function isub(uint512 r, uint256 y) internal pure returns (uint512) {
        return osub(r, r, y);
    }

    function _sub(uint256 x_hi, uint256 x_lo, uint256 y_hi, uint256 y_lo)
        private
        pure
        returns (uint256 r_hi, uint256 r_lo)
    {
        assembly ("memory-safe") {
            r_lo := sub(x_lo, y_lo)
            // `gt(r_lo, x_lo)` indicates underflow in the lower subtraction.
            // Underflow in the high limb is simply ignored.
            r_hi := sub(sub(x_hi, y_hi), gt(r_lo, x_lo))
        }
    }

    function osub(uint512 r, uint512 x, uint512 y) internal pure returns (uint512) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 y_hi, uint256 y_lo) = y.into();
        (uint256 r_hi, uint256 r_lo) = _sub(x_hi, x_lo, y_hi, y_lo);
        return r.from(r_hi, r_lo);
    }

    function isub(uint512 r, uint512 y) internal pure returns (uint512) {
        return osub(r, r, y);
    }

    function irsub(uint512 r, uint512 y) internal pure returns (uint512) {
        return osub(r, y, r);
    }

    function sub(uint512 x, uint256 y) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := sub(mload(add(0x20, x)), y)
        }
    }

    function sub(uint512 x, uint512 y) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := sub(mload(add(0x20, x)), mload(add(0x20, y)))
        }
    }

    //// The technique implemented in the following functions for multiplication is
    //// adapted from Remco Bloemen's work https://2π.com/17/full-mul/ .
    //// The original code was released under the MIT license.

    function _mul(uint256 x, uint256 y) private pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            let mm := mulmod(x, y, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            r_lo := mul(x, y)
            r_hi := sub(sub(mm, r_lo), lt(mm, r_lo))
        }
    }

    function omul(uint512 r, uint256 x, uint256 y) internal pure returns (uint512) {
        (uint256 r_hi, uint256 r_lo) = _mul(x, y);
        return r.from(r_hi, r_lo);
    }

    function _mul(uint256 x_hi, uint256 x_lo, uint256 y) private pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            let mm := mulmod(x_lo, y, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            r_lo := mul(x_lo, y)
            r_hi := add(mul(x_hi, y), sub(sub(mm, r_lo), lt(mm, r_lo)))
        }
    }

    function omul(uint512 r, uint512 x, uint256 y) internal pure returns (uint512) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 r_hi, uint256 r_lo) = _mul(x_hi, x_lo, y);
        return r.from(r_hi, r_lo);
    }

    function imul(uint512 r, uint256 y) internal pure returns (uint512) {
        return omul(r, r, y);
    }

    function _mul(uint256 x_hi, uint256 x_lo, uint256 y_hi, uint256 y_lo)
        private
        pure
        returns (uint256 r_hi, uint256 r_lo)
    {
        assembly ("memory-safe") {
            let mm := mulmod(x_lo, y_lo, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            r_lo := mul(x_lo, y_lo)
            r_hi := add(add(mul(x_hi, y_lo), mul(x_lo, y_hi)), sub(sub(mm, r_lo), lt(mm, r_lo)))
        }
    }

    function omul(uint512 r, uint512 x, uint512 y) internal pure returns (uint512) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 y_hi, uint256 y_lo) = y.into();
        (uint256 r_hi, uint256 r_lo) = _mul(x_hi, x_lo, y_hi, y_lo);
        return r.from(r_hi, r_lo);
    }

    function imul(uint512 r, uint512 y) internal pure returns (uint512) {
        return omul(r, r, y);
    }

    function mod(uint512 n, uint256 d) internal pure returns (uint256 r) {
        if (d == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        (uint256 n_hi, uint256 n_lo) = n.into();
        assembly ("memory-safe") {
            r := mulmod(n_hi, sub(0x00, d), d)
            r := addmod(n_lo, r, d)
        }
    }

    function omod(uint512 r, uint512 x, uint512 y) internal view returns (uint512) {
        (uint256 x_hi, uint256 x_lo) = x.into();
        (uint256 y_hi, uint256 y_lo) = y.into();
        assembly ("memory-safe") {
            // We use the MODEXP (5) precompile with an exponent of 1. We encode
            // the arguments to the precompile at the beginning of free memory
            // without allocating. Arguments are encoded as:
            //     [64 32 64 x_hi x_lo 1 y_hi y_lo]
            let ptr := mload(0x40)
            mstore(ptr, 0x40)
            mstore(add(0x20, ptr), 0x20)
            mstore(add(0x40, ptr), 0x40)
            // See comment in `from` about why `mstore` is more efficient than `mcopy`
            mstore(add(0x60, ptr), x_hi)
            mstore(add(0x80, ptr), x_lo)
            mstore(add(0xa0, ptr), 0x01)
            mstore(add(0xc0, ptr), y_hi)
            mstore(add(0xe0, ptr), y_lo)

            // We write the result of MODEXP directly into the output space r.
            pop(staticcall(gas(), 0x05, ptr, 0x100, r, 0x40))
            // The MODEXP precompile can only fail due to out-of-gas. This call
            // consumes only 200 gas, so if it failed, there is only 4 gas
            // remaining in this context. Therefore, we will out-of-gas
            // immediately when we attempt to read the result. We don't bother
            // to check for failure.
        }
        return r;
    }

    function imod(uint512 r, uint512 y) internal view returns (uint512) {
        return omod(r, r, y);
    }

    function irmod(uint512 r, uint512 y) internal view returns (uint512) {
        return omod(r, y, r);
    }

    /// Multiply 512-bit [x_hi x_lo] by 256-bit [y] giving 768-bit [r_ex r_hi r_lo]
    function _mul768(uint256 x_hi, uint256 x_lo, uint256 y)
        private
        pure
        returns (uint256 r_ex, uint256 r_hi, uint256 r_lo)
    {
        assembly ("memory-safe") {
            let mm0 := mulmod(x_lo, y, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            r_lo := mul(x_lo, y)
            let mm1 := mulmod(x_hi, y, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            let r_partial := mul(x_hi, y)
            r_ex := sub(sub(mm1, r_partial), lt(mm1, r_partial))

            r_hi := add(r_partial, sub(sub(mm0, r_lo), lt(mm0, r_lo)))
            // `lt(r_hi, r_partial)` indicates overflow in the addition to form
            // `r_hi`. We can add the bool directly to the integer to perform
            // carry.
            r_ex := add(r_ex, lt(r_hi, r_partial))
        }
    }

    //// The technique implemented in the following functions for division is
    //// adapted from Remco Bloemen's work https://2π.com/21/muldiv/ .
    //// The original code was released under the MIT license.

    function _roundDown(uint256 x_hi, uint256 x_lo, uint256 d) private pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            // Get the remainder [n_hi n_lo] % d (< 2²⁵⁶ - 1)
            // 2**256 % d = -d % 2**256 % d -- https://2π.com/17/512-bit-division/
            let rem := mulmod(x_hi, sub(0x00, d), d)
            rem := addmod(x_lo, rem, d)

            r_hi := sub(x_hi, gt(rem, x_lo))
            r_lo := sub(x_lo, rem)
        }
    }

    function _roundDown(uint256 x_hi, uint256 x_lo, uint256 d_hi, uint256 d_lo)
        private
        view
        returns (uint256 r_hi, uint256 r_lo)
    {
        uint512 r;
        assembly ("memory-safe") {
            // We point `r` to the beginning of free memory WITHOUT allocating.
            // This is not technically "memory-safe" because solc might use that
            // memory for something in between the end of this assembly block
            // and the beginning of the call to `into()`, but empirically and
            // practically speaking that won't and doesn't happen. We save some
            // gas by not bumping the free pointer.
            r := mload(0x40)

            // Get the remainder [x_hi x_lo] % [d_hi d_lo] (< 2⁵¹² - 1) We use
            // the MODEXP (5) precompile with an exponent of 1. We encode the
            // arguments to the precompile at the beginning of free memory
            // without allocating. Conveniently, `r` already points to this
            // region. Arguments are encoded as:
            //     [64 32 64 x_hi x_lo 1 d_hi d_lo]
            mstore(r, 0x40)
            mstore(add(0x20, r), 0x20)
            mstore(add(0x40, r), 0x40)
            mstore(add(0x60, r), x_hi)
            mstore(add(0x80, r), x_lo)
            mstore(add(0xa0, r), 0x01)
            mstore(add(0xc0, r), d_hi)
            mstore(add(0xe0, r), d_lo)

            // The MODEXP precompile can only fail due to out-of-gas. This call
            // consumes only 200 gas, so if it failed, there is only 4 gas
            // remaining in this context. Therefore, we will out-of-gas
            // immediately when we attempt to read the result. We don't bother
            // to check for failure.
            pop(staticcall(gas(), 0x05, r, 0x100, r, 0x40))
        }
        (uint256 rem_hi, uint256 rem_lo) = r.into();
        // Round down by subtracting the remainder from the numerator
        (r_hi, r_lo) = _sub(x_hi, x_lo, rem_hi, rem_lo);
    }

    function _twos(uint256 x) private pure returns (uint256 twos, uint256 twosInv) {
        assembly ("memory-safe") {
            // Compute largest power of two divisor of `x`. `x` is nonzero, so
            // this is always ≥ 1.
            twos := and(sub(0x00, x), x)

            // To shift up (bits from the high limb into the low limb) we need
            // the inverse of `twos`. That is, 2²⁵⁶ / twos.
            //     2**256 / twos = -twos % 2**256 / twos + 1 -- https://2π.com/17/512-bit-division/
            // If `twos` is zero, then `twosInv` becomes one (not possible)
            twosInv := add(div(sub(0x00, twos), twos), 0x01)
        }
    }

    function _toOdd256(uint256 x_hi, uint256 x_lo, uint256 y) private pure returns (uint256 x_lo_out, uint256 y_out) {
        // Factor powers of two out of `y` and apply the same shift to [x_hi
        // x_lo]
        (uint256 twos, uint256 twosInv) = _twos(y);

        assembly ("memory-safe") {
            // Divide `y` by the power of two
            y_out := div(y, twos)

            // Divide [x_hi x_lo] by the power of two
            x_lo_out := or(div(x_lo, twos), mul(x_hi, twosInv))
        }
    }

    function _toOdd256(uint256 x_hi, uint256 x_lo, uint256 y_hi, uint256 y_lo)
        private
        pure
        returns (uint256 x_lo_out, uint256 y_lo_out)
    {
        // Factor powers of two out of `y_lo` and apply the same shift to `x_lo`
        (uint256 twos, uint256 twosInv) = _twos(y_lo);

        assembly ("memory-safe") {
            // Divide [y_hi y_lo] by the power of two, returning only the low limb
            y_lo_out := or(div(y_lo, twos), mul(y_hi, twosInv))

            // Divide [x_hi x_lo] by the power of two, returning only the low limb
            x_lo_out := or(div(x_lo, twos), mul(x_hi, twosInv))
        }
    }

    function _toOdd512(uint256 x_hi, uint256 x_lo, uint256 y)
        private
        pure
        returns (uint256 x_hi_out, uint256 x_lo_out, uint256 y_out)
    {
        // Factor powers of two out of `y` and apply the same shift to [x_hi
        // x_lo]
        (uint256 twos, uint256 twosInv) = _twos(y);

        assembly ("memory-safe") {
            // Divide `y` by the power of two
            y_out := div(y, twos)

            // Divide [x_hi x_lo] by the power of two
            x_hi_out := div(x_hi, twos)
            x_lo_out := or(div(x_lo, twos), mul(x_hi, twosInv))
        }
    }

    function _toOdd512(uint256 x_hi, uint256 x_lo, uint256 y_hi, uint256 y_lo)
        private
        pure
        returns (uint256 x_hi_out, uint256 x_lo_out, uint256 y_hi_out, uint256 y_lo_out)
    {
        // Factor powers of two out of [y_hi y_lo] and apply the same shift to
        // [x_hi x_lo] and [y_hi y_lo]
        (uint256 twos, uint256 twosInv) = _twos(y_lo);

        assembly ("memory-safe") {
            // Divide [y_hi y_lo] by the power of two
            y_hi_out := div(y_hi, twos)
            y_lo_out := or(div(y_lo, twos), mul(y_hi, twosInv))

            // Divide [x_hi x_lo] by the power of two
            x_hi_out := div(x_hi, twos)
            x_lo_out := or(div(x_lo, twos), mul(x_hi, twosInv))
        }
    }

    function _invert256(uint256 d) private pure returns (uint256 inv) {
        assembly ("memory-safe") {
            // Invert `d` mod 2²⁵⁶ -- https://2π.com/18/multiplitcative-inverses/
            // `d` is an odd number (from _toOdd*). It has an inverse modulo
            // 2²⁵⁶ such that d * inv ≡ 1 mod 2²⁵⁶.
            // We use Newton-Raphson iterations compute inv. Thanks to Hensel's
            // lifting lemma, this also works in modular arithmetic, doubling
            // the correct bits in each step. The Newton-Raphson-Hensel step is:
            //    inv_{n+1} = inv_n * (2 - d*inv_n) % 2**512

            // To kick off Newton-Raphson-Hensel iterations, we start with a
            // seed of the inverse that is correct correct for four bits.
            //     d * inv ≡ 1 mod 2⁴
            inv := xor(mul(0x03, d), 0x02)

            // Each Newton-Raphson-Hensel step doubles the number of correct
            // bits in `inv`. After 6 iterations, full convergence is
            // guaranteed.
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2⁸
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2¹⁶
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2³²
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2⁶⁴
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2¹²⁸
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2²⁵⁶
        }
    }

    function _invert512(uint256 d) private pure returns (uint256 inv_hi, uint256 inv_lo) {
        // First, we get the inverse of `d` mod 2²⁵⁶
        inv_lo = _invert256(d);

        // To extend this to the inverse mod 2⁵¹², we perform a more elaborate
        // 7th Newton-Raphson-Hensel iteration with 512 bits of precision.

        // tmp = d * inv_lo % 2**512
        (uint256 tmp_hi, uint256 tmp_lo) = _mul(d, inv_lo);
        // tmp = 2 - tmp % 2**512
        (tmp_hi, tmp_lo) = _sub(0, 2, tmp_hi, tmp_lo);

        assembly ("memory-safe") {
            // inv_hi = inv_lo * tmp / 2**256 % 2**256
            let mm := mulmod(inv_lo, tmp_lo, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            inv_hi := add(mul(inv_lo, tmp_hi), sub(sub(mm, inv_lo), lt(mm, inv_lo)))
        }
    }

    function _invert512(uint256 d_hi, uint256 d_lo) private pure returns (uint256 inv_hi, uint256 inv_lo) {
        // First, we get the inverse of `d` mod 2²⁵⁶
        inv_lo = _invert256(d_lo);

        // To extend this to the inverse mod 2⁵¹², we perform a more elaborate
        // 7th Newton-Raphson-Hensel iteration with 512 bits of precision.

        // tmp = d * inv_lo % 2**512
        (uint256 tmp_hi, uint256 tmp_lo) = _mul(d_hi, d_lo, inv_lo);
        // tmp = 2 - tmp % 2**512
        (tmp_hi, tmp_lo) = _sub(0, 2, tmp_hi, tmp_lo);

        assembly ("memory-safe") {
            // inv_hi = inv_lo * tmp / 2**256 % 2**256
            let mm := mulmod(inv_lo, tmp_lo, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            inv_hi := add(mul(inv_lo, tmp_hi), sub(sub(mm, inv_lo), lt(mm, inv_lo)))
        }
    }

    function div(uint512 n, uint256 d) internal pure returns (uint256) {
        if (d == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        (uint256 n_hi, uint256 n_lo) = n.into();
        if (n_hi == 0) {
            return n_lo.unsafeDiv(d);
        }

        // Round the numerator down to a multiple of the denominator. This makes
        // the division exact without affecting the result.
        (n_hi, n_lo) = _roundDown(n_hi, n_lo, d);

        // Make `d` odd so that it has a multiplicative inverse mod 2²⁵⁶
        // After this we can discard `n_hi` because our result is only 256 bits
        (n_lo, d) = _toOdd256(n_hi, n_lo, d);

        // We perform division by multiplying by the multiplicative inverse of
        // the denominator mod 2²⁵⁶. Since `d` is odd, this inverse
        // exists. Compute that inverse
        d = _invert256(d);

        unchecked {
            // Because the division is now exact (we rounded `n` down to a
            // multiple of `d`), we perform it by multiplying with the modular
            // inverse of the denominator. This is the correct result mod 2²⁵⁶.
            return n_lo * d;
        }
    }

    function _gt(uint256 x_hi, uint256 x_lo, uint256 y_hi, uint256 y_lo) private pure returns (bool r) {
        assembly ("memory-safe") {
            r := or(gt(x_hi, y_hi), and(eq(x_hi, y_hi), gt(x_lo, y_lo)))
        }
    }

    function div(uint512 n, uint512 d) internal view returns (uint256) {
        (uint256 d_hi, uint256 d_lo) = d.into();
        if (d_hi == 0) {
            return div(n, d_lo);
        }
        (uint256 n_hi, uint256 n_lo) = n.into();
        if (d_lo == 0) {
            return n_hi.unsafeDiv(d_hi);
        }
        if (_gt(d_hi, d_lo, n_hi, n_lo)) {
            // TODO: this optimization may not be overall optimizing
            return 0;
        }

        // Round the numerator down to a multiple of the denominator. This makes
        // the division exact without affecting the result.
        (n_hi, n_lo) = _roundDown(n_hi, n_lo, d_hi, d_lo);

        // Make `d_lo` odd so that it has a multiplicative inverse mod 2²⁵⁶
        // After this we can discard `n_hi` and `d_hi` because our result is
        // only 256 bits
        (n_lo, d_lo) = _toOdd256(n_hi, n_lo, d_hi, d_lo);

        // We perform division by multiplying by the multiplicative inverse of
        // the denominator mod 2²⁵⁶. Since `d_lo` is odd, this inverse
        // exists. Compute that inverse
        d_lo = _invert256(d_lo);

        unchecked {
            // Because the division is now exact (we rounded `n` down to a
            // multiple of `d`), we perform it by multiplying with the modular
            // inverse of the denominator. This is the correct result mod 2²⁵⁶.
            return n_lo * d_lo;
        }
    }

    function odiv(uint512 r, uint512 x, uint256 y) internal pure returns (uint512) {
        if (y == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        (uint256 x_hi, uint256 x_lo) = x.into();
        if (x_hi == 0) {
            return r.from(0, x_lo.unsafeDiv(y));
        }

        // Round the numerator down to a multiple of the denominator. This makes
        // the division exact without affecting the result.
        (x_hi, x_lo) = _roundDown(x_hi, x_lo, y);

        // Make `y` odd so that it has a multiplicative inverse mod 2⁵¹²
        (x_hi, x_lo, y) = _toOdd512(x_hi, x_lo, y);

        // We perform division by multiplying by the multiplicative inverse of
        // the denominator mod 2⁵¹². Since `y` is odd, this inverse
        // exists. Compute that inverse
        (uint256 inv_hi, uint256 inv_lo) = _invert512(y);

        // Because the division is now exact (we rounded `x` down to a multiple
        // of `y`), we perform it by multiplying with the modular inverse of the
        // denominator.
        (uint256 r_hi, uint256 r_lo) = _mul(x_hi, x_lo, inv_hi, inv_lo);
        return r.from(r_hi, r_lo);
    }

    function idiv(uint512 r, uint256 y) internal pure returns (uint512) {
        return odiv(r, r, y);
    }

    function odiv(uint512 r, uint512 x, uint512 y) internal view returns (uint512) {
        (uint256 y_hi, uint256 y_lo) = y.into();
        if (y_hi == 0) {
            return odiv(r, x, y_lo);
        }
        (uint256 x_hi, uint256 x_lo) = x.into();
        if (y_lo == 0) {
            return r.from(0, x_hi.unsafeDiv(y_hi));
        }
        if (_gt(y_hi, y_lo, x_hi, x_lo)) {
            // TODO: this optimization may not be overall optimizing
            return r.from(0, 0);
        }

        // Round the numerator down to a multiple of the denominator. This makes
        // the division exact without affecting the result.
        (x_hi, x_lo) = _roundDown(x_hi, x_lo, y_hi, y_lo);

        // Make `y` odd so that it has a multiplicative inverse mod 2⁵¹²
        (x_hi, x_lo, y_hi, y_lo) = _toOdd512(x_hi, x_lo, y_hi, y_lo);

        // We perform division by multiplying by the multiplicative inverse of
        // the denominator mod 2⁵¹². Since `y` is odd, this inverse
        // exists. Compute that inverse
        (y_hi, y_lo) = _invert512(y_hi, y_lo);

        // Because the division is now exact (we rounded `x` down to a multiple
        // of `y`), we perform it by multiplying with the modular inverse of the
        // denominator.
        (uint256 r_hi, uint256 r_lo) = _mul(x_hi, x_lo, y_hi, y_lo);
        return r.from(r_hi, r_lo);
    }

    function idiv(uint512 r, uint512 y) internal view returns (uint512) {
        return odiv(r, r, y);
    }

    function irdiv(uint512 r, uint512 y) internal view returns (uint512) {
        return odiv(r, y, r);
    }

    function _gt(uint256 x_ex, uint256 x_hi, uint256 x_lo, uint256 y_ex, uint256 y_hi, uint256 y_lo)
        private
        pure
        returns (bool r)
    {
        assembly ("memory-safe") {
            r :=
                or(
                    or(gt(x_ex, y_ex), and(eq(x_ex, y_ex), gt(x_hi, y_hi))),
                    and(and(eq(x_ex, y_ex), eq(x_hi, y_hi)), gt(x_lo, y_lo))
                )
        }
    }

    /// The technique implemented in the following helper function for Knuth
    /// Algorithm D (a modification of the citation further below) is adapted
    /// from ridiculous fish's (aka corydoras) work
    /// https://ridiculousfish.com/blog/posts/labor-of-division-episode-iv.html
    /// and
    /// https://ridiculousfish.com/blog/posts/labor-of-division-episode-v.html .

    function _correctQ(uint256 q, uint256 r, uint256 x_next, uint256 y_next, uint256 y_whole)
        private
        pure
        returns (uint256 q_out)
    {
        assembly ("memory-safe") {
            let c1 := mul(q, y_next)
            let c2 := or(shl(0x80, r), x_next)
            q_out := sub(q, shl(gt(sub(c1, c2), y_whole), gt(c1, c2)))
        }
    }

    /// The technique implemented in the following function for division is
    /// adapted from Donald Knuth, The Art of Computer Programming (TAOCP)
    /// Volume 2, Section 4.3.1, Algorithm D.

    function _algorithmD(uint256 x_hi, uint256 x_lo, uint256 y_hi, uint256 y_lo) private pure returns (uint256 q) {
        // We treat `x` and `y` each as ≤4-limb bigints where each limb is half
        // a machine word (128 bits). This lets us perform 2-limb ÷ 1-limb
        // divisions as a single operation (`div`) as required by Algorithm
        // D. It also simplifies/optimizes some of the multiplications.

        if (y_hi >> 128 != 0) {
            // y is 4 limbs, x is 4 limbs, q is 1 limb

            // Normalize. Ensure the uppermost limb of y ≥ 2¹²⁷ (equivalently
            // y_hi >= 2**255). This is step D1 of Algorithm D
            // The author's copy of TAOCP (3rd edition) states to set `d = (2 **
            // 128 - 1) // y_hi`, however this is incorrect. Setting `d` in this
            // fashion may result in overflow in the subsequent `_mul`. Setting
            // `d` as implemented below still satisfies the postcondition (`y_hi
            // >> 128 >= 1 << 127`) but never results in overflow.
            uint256 d = uint256(1 << 128).unsafeDiv((y_hi >> 128).unsafeInc());
            uint256 x_ex;
            (x_ex, x_hi, x_lo) = _mul768(x_hi, x_lo, d);
            (y_hi, y_lo) = _mul(y_hi, y_lo, d);

            // `n_approx` is the 2 most-significant limbs of x, after
            // normalization
            uint256 n_approx = (x_ex << 128) | (x_hi >> 128);
            // `d_approx` is the most significant limb of y, after normalization
            uint256 d_approx = y_hi >> 128;
            // Normalization ensures that result of this division is an
            // approximation of the most significant (and only) limb of the
            // quotient and is too high by at most 3. This is the "Calculate
            // q-hat" (D3) step of Algorithm D. (did you know that U+0302,
            // COMBINING CIRCUMFLEX ACCENT cannot be combined with q? shameful)
            q = n_approx.unsafeDiv(d_approx);
            uint256 r_hat = n_approx.unsafeMod(d_approx);

            // The process of `_correctQ` subtracts up to 2 from `q`, to make it
            // more accurate. This is still part of the "Calculate q-hat" (D3)
            // step of Algorithm D.
            q = _correctQ(q, r_hat, x_hi & type(uint128).max, y_hi & type(uint128).max, y_hi);

            // This final, low-probability, computationally-expensive correction
            // conditionally subtracts 1 from `q` to make it exactly the
            // most-significant limb of the quotient. This is the "Multiply and
            // subtract" (D4), "Test remainder" (D5), and "Add back" (D6) steps
            // of Algorithm D, with substantial shortcutting
            {
                (uint256 tmp_ex, uint256 tmp_hi, uint256 tmp_lo) = _mul768(y_hi, y_lo, q);
                bool neg = _gt(tmp_ex, tmp_hi, tmp_lo, x_ex, x_hi, x_lo);
                assembly ("memory-safe") {
                    q := sub(q, neg)
                }
            }
        } else {
            // y is 3 limbs

            // Normalize. Ensure the most significant limb of y ≥ 2¹²⁷ (step D1)
            // See above comment about the error in TAOCP.
            uint256 d = uint256(1 << 128).unsafeDiv(y_hi.unsafeInc());
            (y_hi, y_lo) = _mul(y_hi, y_lo, d);
            // `y_next` is the second-most-significant, nonzero, normalized limb
            // of y
            uint256 y_next = y_lo >> 128;
            // `y_whole` is the 2 most-significant, nonzero, normalized limbs of
            // y
            uint256 y_whole = (y_hi << 128) | y_next;

            if (x_hi >> 128 != 0) {
                // x is 4 limbs, q is 2 limbs

                // Finish normalizing (step D1)
                uint256 x_ex;
                (x_ex, x_hi, x_lo) = _mul768(x_hi, x_lo, d);

                uint256 n_approx = (x_ex << 128) | (x_hi >> 128);
                // As before, `q_hat` is the most significant limb of the
                // quotient and too high by at most 3 (step D3)
                uint256 q_hat = n_approx.unsafeDiv(y_hi);
                uint256 r_hat = n_approx.unsafeMod(y_hi);

                // Subtract up to 2 from `q_hat`, improving our estimate (step
                // D3)
                q_hat = _correctQ(q_hat, r_hat, x_hi & type(uint128).max, y_next, y_whole);
                q = q_hat << 128;

                {
                    // "Multiply and subtract" (D4) step of Algorithm D
                    (uint256 tmp_hi, uint256 tmp_lo) = _mul(y_hi, y_lo, q_hat);
                    uint256 tmp_ex = tmp_hi >> 128;
                    tmp_hi = (tmp_hi << 128) | (tmp_lo >> 128);
                    tmp_lo <<= 128;

                    // "Test remainder" (D5) step of Algorithm D
                    bool neg = _gt(tmp_ex, tmp_hi, tmp_lo, x_ex, x_hi, x_lo);
                    // Finish step D4
                    (x_hi, x_lo) = _sub(x_hi, x_lo, tmp_hi, tmp_lo);

                    // "Add back" (D6) step of Algorithm D
                    if (neg) {
                        // This branch is quite rare, so it's gas-advantageous
                        // to actually branch and usually skip the costly `_add`
                        unchecked {
                            q -= 1 << 128;
                        }
                        (x_hi, x_lo) = _add(x_hi, x_lo, y_whole, y_lo << 128);
                    }
                }
                // `x_ex` is now zero (implicitly)

                // Run another loop (steps D3 through D6) of Algorithm D to get
                // the lower limb of the quotient
                q_hat = x_hi.unsafeDiv(y_hi);
                r_hat = x_hi.unsafeMod(y_hi);

                q_hat = _correctQ(q_hat, r_hat, x_lo >> 128, y_next, y_whole);

                {
                    (uint256 tmp_hi, uint256 tmp_lo) = _mul(y_hi, y_lo, q_hat);
                    bool neg = _gt(tmp_hi, tmp_lo, x_hi, x_lo);
                    assembly ("memory-safe") {
                        q_hat := sub(q_hat, neg)
                    }
                }

                q |= q_hat;
            } else {
                // x is 3 limbs, q is 1 limb

                // Finish normalizing (step D1)
                (x_hi, x_lo) = _mul(x_hi, x_lo, d);

                // `q` is the most significant (and only) limb of the quotient
                // and too high by at most 3 (step D3)
                q = x_hi.unsafeDiv(y_hi);
                uint256 r_hat = x_hi.unsafeMod(y_hi);

                // Subtract up to 2 from `q`, improving our estimate (step D3)
                q = _correctQ(q, r_hat, x_lo >> 128, y_next, y_whole);

                // Subtract up to 1 from `q` to make it exact (steps D4 through
                // D6)
                {
                    (uint256 tmp_hi, uint256 tmp_lo) = _mul(y_hi, y_lo, q);
                    bool neg = _gt(tmp_hi, tmp_lo, x_hi, x_lo);
                    assembly ("memory-safe") {
                        q := sub(q, neg)
                    }
                }
            }
        }
        // All other cases are handled by the checks that y ≥ 2²⁵⁶ (equivalently
        // y_hi != 0) and that x ≥ y
    }

    /// Modified from Solady (https://github.com/Vectorized/solady/blob/a3d6a974f9c9f00dcd95b235619a209a63c61d94/src/utils/LibBit.sol#L33-L45)
    /// The original code was released under the MIT license.
    function _clzLower(uint256 x) private pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := shl(0x06, lt(0xffffffffffffffff, x))
            r := or(r, shl(0x05, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(0x04, lt(0xffff, shr(r, x))))
            r := or(r, shl(0x03, lt(0xff, shr(r, x))))
            // We use a 5-bit deBruijn Sequence to convert `x`'s 8
            // most-significant bits into an index. We then index the lookup
            // table (bytewise) by the deBruijn symbol to obtain the bitwise
            // inverse of its logarithm.
            r :=
                xor(
                    r,
                    byte(
                        and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                        0x7879797a797d7a7b797d7c7d7a7b7c7e797a7d7a7c7c7b7e7a7a7c7b7f7f7f7f
                    )
                )
        }
    }

    function _clzUpper(uint256 x) private pure returns (uint256) {
        return _clzLower(x >> 128);
    }

    function _shl(uint256 x_hi, uint256 x_lo, uint256 s) private pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            r_hi := or(shl(s, x_hi), shr(sub(0x100, s), x_lo))
            r_lo := shl(s, x_lo)
        }
    }

    function _shl768(uint256 x_hi, uint256 x_lo, uint256 s)
        private
        pure
        returns (uint256 r_ex, uint256 r_hi, uint256 r_lo)
    {
        assembly ("memory-safe") {
            let neg_s := sub(0x100, s)
            r_ex := shr(neg_s, x_hi)
            r_hi := or(shl(s, x_hi), shr(neg_s, x_lo))
            r_lo := shl(s, x_lo)
        }
    }

    function _shr(uint256 x_hi, uint256 x_lo, uint256 s) private pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            r_hi := shr(s, x_hi)
            r_lo := or(shl(sub(0x100, s), x_hi), shr(s, x_lo))
        }
    }

    // This function is a different modification of Knuth's Algorithm D. In this
    // case, we're only interested in the (normalized) remainder instead of the
    // quotient. We also substitute the normalization by division for
    // normalization by shifting because it makes un-normalization more
    // gas-efficient.

    function _algorithmDRemainder(uint256 x_hi, uint256 x_lo, uint256 y_hi, uint256 y_lo)
        private
        pure
        returns (uint256, uint256)
    {
        // We treat `x` and `y` each as ≤4-limb bigints where each limb is half
        // a machine word (128 bits). This lets us perform 2-limb ÷ 1-limb
        // divisions as a single operation (`div`) as required by Algorithm D.

        uint256 s;
        if (y_hi >> 128 != 0) {
            // y is 4 limbs, x is 4 limbs

            // Normalize. Ensure the uppermost limb of y ≥ 2¹²⁷ (equivalently
            // y_hi >= 2**255). This is step D1 of Algorithm D Unlike the
            // preceeding implementation of Algorithm D, we use a binary shift
            // instead of a multiply to normalize. This performs a costly "count
            // leading zeroes" operation, but it lets us transform an
            // even-more-costly division-by-inversion operation later into a
            // simple shift. This still ultimately satisfies the postcondition
            // (y_hi >> 128 >= 1 << 127) without overflowing.
            s = _clzUpper(y_hi);
            uint256 x_ex;
            (x_ex, x_hi, x_lo) = _shl768(x_hi, x_lo, s);
            (y_hi, y_lo) = _shl(y_hi, y_lo, s);

            // `n_approx` is the 2 most-significant limbs of x, after
            // normalization
            uint256 n_approx = (x_ex << 128) | (x_hi >> 128); // TODO: this can probably be optimized (combined with `_shl`)
            // `d_approx` is the most significant limb of y, after normalization
            uint256 d_approx = y_hi >> 128; // TODO: this can probably be optimized (combined with `_shl`)
            // Normalization ensures that result of this division is an
            // approximation of the most significant (and only) limb of the
            // quotient and is too high by at most 3. This is the "Calculate
            // q-hat" (D3) step of Algorithm D. (did you know that U+0302,
            // COMBINING CIRCUMFLEX ACCENT cannot be combined with q? shameful)
            uint256 q_hat = n_approx.unsafeDiv(d_approx);
            uint256 r_hat = n_approx.unsafeMod(d_approx);

            // The process of `_correctQ` subtracts up to 2 from `q_hat`, to
            // make it more accurate. This is still part of the "Calculate
            // q-hat" (D3) step of Algorithm D.
            q_hat = _correctQ(q_hat, r_hat, x_hi & type(uint128).max, y_hi & type(uint128).max, y_hi);

            {
                // This penultimate correction subtracts q-hat × y from x to
                // obtain the normalized remainder. This is the "Multiply and
                // subtract" (D4) and "Test remainder" (D5) steps of Algorithm
                // D, with some shortcutting
                (uint256 tmp_ex, uint256 tmp_hi, uint256 tmp_lo) = _mul768(y_hi, y_lo, q_hat);
                bool neg = _gt(tmp_ex, tmp_hi, tmp_lo, x_ex, x_hi, x_lo);
                (x_hi, x_lo) = _sub(x_hi, x_lo, tmp_hi, tmp_lo);
                // `x_ex` is now implicitly zero (or signals a carry that we
                // will clear in the next step)

                // Because `q_hat` may be too high by 1, we have to detect
                // underflow from the previous step and correct it. This is the
                // "Add back" (D6) step of Algorithm D
                if (neg) {
                    (x_hi, x_lo) = _add(x_hi, x_lo, y_hi, y_lo);
                }
            }
        } else {
            // y is 3 limbs

            // Normalize. Ensure the most significant limb of y ≥ 2¹²⁷ (step D1)
            // See above comment about the use of a shift instead of division.
            s = _clzLower(y_hi);
            (y_hi, y_lo) = _shl(y_hi, y_lo, s);
            // `y_next` is the second-most-significant, nonzero, normalized limb
            // of y
            uint256 y_next = y_lo >> 128; // TODO: this can probably be optimized (combined with `_shl`)
            // `y_whole` is the 2 most-significant, nonzero, normalized limbs of
            // y
            uint256 y_whole = (y_hi << 128) | y_next; // TODO: this can probably be optimized (combined with `_shl`)

            if (x_hi >> 128 != 0) {
                // x is 4 limbs; we have to run 2 iterations of Algorithm D to
                // fully divide out by y

                // Finish normalizing (step D1)
                uint256 x_ex;
                (x_ex, x_hi, x_lo) = _shl768(x_hi, x_lo, s);

                uint256 n_approx = (x_ex << 128) | (x_hi >> 128); // TODO: this can probably be optimized (combined with `_shl768`)
                // As before, `q_hat` is the most significant limb of the
                // quotient and too high by at most 3 (step D3)
                uint256 q_hat = n_approx.unsafeDiv(y_hi);
                uint256 r_hat = n_approx.unsafeMod(y_hi);

                // Subtract up to 2 from `q_hat`, improving our estimate (step
                // D3)
                q_hat = _correctQ(q_hat, r_hat, x_hi & type(uint128).max, y_next, y_whole);

                // Subtract up to 1 from q-hat to make it exactly the
                // most-significant limb of the quotient and subtract q-hat × y
                // from x to clear the most-significant limb of x.
                {
                    // "Multiply and subtract" (D4) step of Algorithm D
                    (uint256 tmp_hi, uint256 tmp_lo) = _mul(y_hi, y_lo, q_hat);
                    uint256 tmp_ex = tmp_hi >> 128;
                    tmp_hi = (tmp_hi << 128) | (tmp_lo >> 128);
                    tmp_lo <<= 128;

                    // "Test remainder" (D5) step of Algorithm D
                    bool neg = _gt(tmp_ex, tmp_hi, tmp_lo, x_ex, x_hi, x_lo);
                    // Finish step D4
                    (x_hi, x_lo) = _sub(x_hi, x_lo, tmp_hi, tmp_lo);

                    // "Add back" (D6) step of Algorithm D. We implicitly
                    // subtract 1 from `q_hat`, but elide explicitly
                    // representing that because `q_hat` is no longer needed.
                    if (neg) {
                        // This branch is quite rare, so it's gas-advantageous
                        // to actually branch and usually skip the costly `_add`
                        (x_hi, x_lo) = _add(x_hi, x_lo, y_whole, y_lo << 128);
                    }
                }
                // `x_ex` is now zero (implicitly)
                // [x_hi x_lo] now represents the partial, normalized remainder.

                // Run another loop (steps D3 through D6) of Algorithm D to get
                // the lower limb of the quotient
                // Step D3
                q_hat = x_hi.unsafeDiv(y_hi);
                r_hat = x_hi.unsafeMod(y_hi);

                // Step D3
                q_hat = _correctQ(q_hat, r_hat, x_lo >> 128, y_next, y_whole);

                // Again, implicitly correct q-hat to make it exactly the
                // least-significant limb of the quotient. Subtract q-hat × y
                // from x to obtain the normalized remainder.
                {
                    // Steps D4 and D5
                    (uint256 tmp_hi, uint256 tmp_lo) = _mul(y_hi, y_lo, q_hat);
                    bool neg = _gt(tmp_hi, tmp_lo, x_hi, x_lo);
                    (x_hi, x_lo) = _sub(x_hi, x_lo, tmp_hi, tmp_lo);

                    // Step D6
                    if (neg) {
                        (x_hi, x_lo) = _add(x_hi, x_lo, y_hi, y_lo);
                    }
                }
            } else {
                // x is 3 limbs

                // Finish normalizing (step D1)
                (x_hi, x_lo) = _shl(x_hi, x_lo, s);

                // `q_hat` is the most significant (and only) limb of the
                // quotient and too high by at most 3 (step D3)
                uint256 q_hat = x_hi.unsafeDiv(y_hi);
                uint256 r_hat = x_hi.unsafeMod(y_hi);

                // Subtract up to 2 from `q_hat`, improving our estimate (step
                // D3)
                q_hat = _correctQ(q_hat, r_hat, x_lo >> 128, y_next, y_whole);

                // Make `q_hat` exact (implicitly) and subtract q-hat × y from x
                // to obtain the normalized remainder. (steps D4 through D6)
                {
                    (uint256 tmp_hi, uint256 tmp_lo) = _mul(y_hi, y_lo, q_hat);
                    bool neg = _gt(tmp_hi, tmp_lo, x_hi, x_lo);
                    (x_hi, x_lo) = _sub(x_hi, x_lo, tmp_hi, tmp_lo);
                    if (neg) {
                        (x_hi, x_lo) = _add(x_hi, x_lo, y_hi, y_lo);
                    }
                }
            }
        }
        // All other cases are handled by the checks that y ≥ 2²⁵⁶ (equivalently
        // y_hi != 0) and that x ≥ y

        // The second-most-significant limb of normalized x is now zero
        // (equivalently x_hi < 2**128), but because the entire machine is not
        // guaranteed to be cleared, we can't optimize any further.

        // [x_hi x_lo] now represents remainder × 2ˢ (the normalized remainder);
        // we shift right by `s` (un-normalize) to obtain the result.
        return _shr(x_hi, x_lo, s);
    }

    function odivAlt(uint512 r, uint512 x, uint512 y) internal pure returns (uint512) {
        (uint256 y_hi, uint256 y_lo) = y.into();
        if (y_hi == 0) {
            // This is the only case where we can have a 2-word quotient
            return odiv(r, x, y_lo);
        }
        (uint256 x_hi, uint256 x_lo) = x.into();
        if (y_lo == 0) {
            uint256 r_lo = x_hi.unsafeDiv(y_hi);
            return r.from(0, r_lo);
        }
        if (_gt(y_hi, y_lo, x_hi, x_lo)) {
            return r.from(0, 0);
        }

        // At this point, we know that both `x` and `y` are fully represented by
        // 2 words. There is no simpler representation for the problem. We must
        // use Knuth's Algorithm D.
        {
            uint256 r_lo = _algorithmD(x_hi, x_lo, y_hi, y_lo);
            return r.from(0, r_lo);
        }
    }

    function idivAlt(uint512 r, uint512 y) internal pure returns (uint512) {
        return odivAlt(r, r, y);
    }

    function irdivAlt(uint512 r, uint512 y) internal pure returns (uint512) {
        return odivAlt(r, y, r);
    }

    function divAlt(uint512 x, uint512 y) internal pure returns (uint256) {
        (uint256 y_hi, uint256 y_lo) = y.into();
        if (y_hi == 0) {
            return div(x, y_lo);
        }
        (uint256 x_hi, uint256 x_lo) = x.into();
        if (y_lo == 0) {
            return x_hi.unsafeDiv(y_hi);
        }
        if (_gt(y_hi, y_lo, x_hi, x_lo)) {
            return 0;
        }

        // At this point, we know that both `x` and `y` are fully represented by
        // 2 words. There is no simpler representation for the problem. We must
        // use Knuth's Algorithm D.
        return _algorithmD(x_hi, x_lo, y_hi, y_lo);
    }

    function omodAlt(uint512 r, uint512 x, uint512 y) internal pure returns (uint512) {
        (uint256 y_hi, uint256 y_lo) = y.into();
        if (y_hi == 0) {
            uint256 r_lo = mod(x, y_lo);
            return r.from(0, r_lo);
        }
        (uint256 x_hi, uint256 x_lo) = x.into();
        if (y_lo == 0) {
            uint256 r_hi = x_hi.unsafeMod(y_hi);
            return r.from(r_hi, x_lo);
        }
        if (_gt(y_hi, y_lo, x_hi, x_lo)) {
            return r.from(x_hi, x_lo);
        }

        // At this point, we know that both `x` and `y` are fully represented by
        // 2 words. There is no simpler representation for the problem. We must
        // use Knuth's Algorithm D.
        {
            (uint256 r_hi, uint256 r_lo) = _algorithmDRemainder(x_hi, x_lo, y_hi, y_lo);
            return r.from(r_hi, r_lo);
        }
    }

    function imodAlt(uint512 r, uint512 y) internal pure returns (uint512) {
        return omodAlt(r, r, y);
    }

    function irmodAlt(uint512 r, uint512 y) internal pure returns (uint512) {
        return omodAlt(r, y, r);
    }
}

using Lib512MathArithmetic for uint512 global;

library Lib512MathUserDefinedHelpers {
    function checkNull(uint512 x, uint512 y) internal pure {
        assembly ("memory-safe") {
            if iszero(mul(x, y)) {
                mstore(0x00, 0x4e487b71) // selector for `Panic(uint256)`
                mstore(0x20, 0x01) // code for "assertion failure"
            }
        }
    }

    function smuggleToPure(function (uint512, uint512, uint512) internal view returns (uint512) f)
        internal
        pure
        returns (function (uint512, uint512, uint512) internal pure returns (uint512) r)
    {
        assembly ("memory-safe") {
            r := f
        }
    }

    function omod(uint512 r, uint512 x, uint512 y) internal view returns (uint512) {
        return r.omod(x, y);
    }

    function odiv(uint512 r, uint512 x, uint512 y) internal view returns (uint512) {
        return r.odiv(x, y);
    }
}

function __add(uint512 x, uint512 y) pure returns (uint512 r) {
    Lib512MathUserDefinedHelpers.checkNull(x, y);
    r.oadd(x, y);
}

function __sub(uint512 x, uint512 y) pure returns (uint512 r) {
    Lib512MathUserDefinedHelpers.checkNull(x, y);
    r.osub(x, y);
}

function __mul(uint512 x, uint512 y) pure returns (uint512 r) {
    Lib512MathUserDefinedHelpers.checkNull(x, y);
    r.omul(x, y);
}

function __mod(uint512 x, uint512 y) pure returns (uint512 r) {
    Lib512MathUserDefinedHelpers.checkNull(x, y);
    Lib512MathUserDefinedHelpers.smuggleToPure(Lib512MathUserDefinedHelpers.omod)(r, x, y);
}

function __div(uint512 x, uint512 y) pure returns (uint512 r) {
    Lib512MathUserDefinedHelpers.checkNull(x, y);
    Lib512MathUserDefinedHelpers.smuggleToPure(Lib512MathUserDefinedHelpers.odiv)(r, x, y);
}

using {__add as +, __sub as -, __mul as *, __mod as %, __div as / } for uint512 global;

struct uint512_external {
    uint256 hi;
    uint256 lo;
}

library Lib512MathExternal {
    function from(uint512 r, uint512_external memory x) internal pure returns (uint512) {
        assembly ("memory-safe") {
            mstore(r, mload(x))
            mstore(add(0x20, r), mload(add(0x20, x)))
        }
        return r;
    }

    function into(uint512_external memory x) internal pure returns (uint512 r) {
        assembly ("memory-safe") {
            r := x
        }
    }

    function toExternal(uint512 x) internal pure returns (uint512_external memory r) {
        assembly ("memory-safe") {
            if iszero(eq(mload(0x40), add(0x40, r))) { revert(0x00, 0x00) }
            mstore(0x40, r)
            r := x
        }
    }
}

using Lib512MathExternal for uint512 global;
using Lib512MathExternal for uint512_external global;

// src/utils/AddressDerivation.sol

library AddressDerivation {
    using UnsafeMath for uint256;

    uint256 internal constant _SECP256K1_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 internal constant _SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 internal constant SECP256K1_GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint256 internal constant SECP256K1_GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;

    error InvalidCurve(uint256 x, uint256 y);

    // keccak256(abi.encodePacked(ECMUL([x, y], k)))[12:]
    function deriveEOA(uint256 x, uint256 y, uint256 k) internal pure returns (address) {
        if (k == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        if (k >= _SECP256K1_N || x >= _SECP256K1_P || y >= _SECP256K1_P) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }

        // +/-7 are neither square nor cube mod p, so we only have to check one
        // coordinate against 0. if it is 0, then the other is too (the point at
        // infinity) or the point is invalid
        if (
            x == 0
                || y.unsafeMulMod(y, _SECP256K1_P)
                    != x.unsafeMulMod(x, _SECP256K1_P).unsafeMulMod(x, _SECP256K1_P).unsafeAddMod(7, _SECP256K1_P)
        ) {
            revert InvalidCurve(x, y);
        }

        unchecked {
            // https://ethresear.ch/t/you-can-kinda-abuse-ecrecover-to-do-ecmul-in-secp256k1-today/2384
            return ecrecover(
                bytes32(0), uint8(27 + (y & 1)), bytes32(x), bytes32(UnsafeMath.unsafeMulMod(x, k, _SECP256K1_N))
            );
        }
    }

    // keccak256(RLP([deployer, nonce]))[12:]
    function deriveContract(address deployer, uint64 nonce) internal pure returns (address result) {
        if (nonce == 0) {
            assembly ("memory-safe") {
                mstore(
                    0x00,
                    or(
                        0xd694000000000000000000000000000000000000000080,
                        shl(8, and(0xffffffffffffffffffffffffffffffffffffffff, deployer))
                    )
                )
                result := keccak256(0x09, 0x17)
            }
        } else if (nonce < 0x80) {
            assembly ("memory-safe") {
                // we don't care about dirty bits in `deployer`; they'll be overwritten later
                mstore(0x14, deployer)
                mstore(0x00, 0xd694)
                mstore8(0x34, nonce)
                result := keccak256(0x1e, 0x17)
            }
        } else {
            // compute ceil(log_256(nonce)) + 1
            uint256 nonceLength = 8;
            unchecked {
                if ((uint256(nonce) >> 32) != 0) {
                    nonceLength += 32;
                    if (nonce == type(uint64).max) {
                        Panic.panic(Panic.ARITHMETIC_OVERFLOW);
                    }
                }
                if ((uint256(nonce) >> 8) >= (1 << nonceLength)) {
                    nonceLength += 16;
                }
                if (uint256(nonce) >= (1 << nonceLength)) {
                    nonceLength += 8;
                }
                // ceil
                if ((uint256(nonce) << 8) >= (1 << nonceLength)) {
                    nonceLength += 8;
                }
                // bytes, not bits
                nonceLength >>= 3;
            }
            assembly ("memory-safe") {
                // we don't care about dirty bits in `deployer` or `nonce`. they'll be overwritten later
                mstore(nonceLength, nonce)
                mstore8(0x20, add(0x7f, nonceLength))
                mstore(0x00, deployer)
                mstore8(0x0a, add(0xd5, nonceLength))
                mstore8(0x0b, 0x94)
                result := keccak256(0x0a, add(0x16, nonceLength))
            }
        }
    }

    // keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initHash))[12:]
    function deriveDeterministicContract(address deployer, bytes32 salt, bytes32 initHash)
        internal
        pure
        returns (address result)
    {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            // we don't care about dirty bits in `deployer`; they'll be overwritten later
            mstore(ptr, deployer)
            mstore8(add(ptr, 0x0b), 0xff)
            mstore(add(ptr, 0x20), salt)
            mstore(add(ptr, 0x40), initHash)
            result := keccak256(add(ptr, 0x0b), 0x55)
        }
    }
}

// src/vendor/FullMath.sol

/// @title Contains 512-bit math functions
/// @notice Facilitates multiplication and division that can have overflow of an intermediate value without any loss of precision
/// @dev Handles "phantom overflow" i.e., allows multiplication and division where an intermediate value overflows 256 bits
/// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
library FullMath {
    using UnsafeMath for uint256;

    /// @notice 512-bit multiply [prod1 prod0] = a * b
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return prod0 Least significant 256 bits of the product
    /// @return prod1 Most significant 256 bits of the product
    /// @return remainder Remainder of full-precision division
    function _mulDivSetup(uint256 a, uint256 b, uint256 denominator)
        private
        pure
        returns (uint256 prod0, uint256 prod1, uint256 remainder)
    {
        // Compute the product mod 2**256 and mod 2**256 - 1 then use the Chinese
        // Remainder Theorem to reconstruct the 512 bit result. The result is stored
        // in two 256 variables such that product = prod1 * 2**256 + prod0
        assembly ("memory-safe") {
            // Full-precision multiplication
            {
                let mm := mulmod(a, b, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            remainder := mulmod(a, b, denominator)
        }
    }

    /// @notice 512-bit by 256-bit division.
    /// @param prod0 Least significant 256 bits of the product
    /// @param prod1 Most significant 256 bits of the product
    /// @param denominator The divisor
    /// @param remainder Remainder of full-precision division
    /// @return The 256-bit result
    /// @dev Overflow and division by zero aren't checked and are GIGO errors
    function _mulDivInvert(uint256 prod0, uint256 prod1, uint256 denominator, uint256 remainder)
        private
        pure
        returns (uint256)
    {
        uint256 inv;
        assembly ("memory-safe") {
            // Make division exact by rounding [prod1 prod0] down to a multiple of
            // denominator
            // Subtract 256 bit number from 512 bit number
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)

            // Factor powers of two out of denominator
            {
                // Compute largest power of two divisor of denominator.
                // Always >= 1.
                let twos := and(sub(0, denominator), denominator)

                // Divide denominator by power of two
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by the factors of two
                prod0 := div(prod0, twos)
                // Shift in bits from prod1 into prod0. For this we need to flip `twos`
                // such that it is 2**256 / twos.
                // If twos is zero, then it becomes one
                twos := add(div(sub(0, twos), twos), 1)
                prod0 := or(prod0, mul(prod1, twos))
            }

            // Invert denominator mod 2**256
            // Now that denominator is an odd number, it has an inverse modulo 2**256
            // such that denominator * inv = 1 mod 2**256.
            // Compute the inverse by starting with a seed that is correct correct for
            // four bits. That is, denominator * inv = 1 mod 2**4
            inv := xor(mul(3, denominator), 2)

            // Now use Newton-Raphson iteration to improve the precision.
            // Thanks to Hensel's lifting lemma, this also works in modular
            // arithmetic, doubling the correct bits in each step.
            inv := mul(inv, sub(2, mul(denominator, inv))) // inverse mod 2**8
            inv := mul(inv, sub(2, mul(denominator, inv))) // inverse mod 2**16
            inv := mul(inv, sub(2, mul(denominator, inv))) // inverse mod 2**32
            inv := mul(inv, sub(2, mul(denominator, inv))) // inverse mod 2**64
            inv := mul(inv, sub(2, mul(denominator, inv))) // inverse mod 2**128
            inv := mul(inv, sub(2, mul(denominator, inv))) // inverse mod 2**256
        }

        // Because the division is now exact we can divide by multiplying with the
        // modular inverse of denominator. This will give us the correct result
        // modulo 2**256. Since the precoditions guarantee that the outcome is less
        // than 2**256, this is the final result.  We don't need to compute the high
        // bits of the result and prod1 is no longer required.
        unchecked {
            return prod0 * inv;
        }
    }

    /// @notice Calculates a×b÷denominator with full precision then rounds towards 0. Throws if result overflows a uint256 or denominator == 0
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return The 256-bit result
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        (uint256 prod0, uint256 prod1, uint256 remainder) = _mulDivSetup(a, b, denominator);
        // Make sure the result is less than 2**256.
        // Also prevents denominator == 0
        if (denominator <= prod1) {
            Panic.panic(denominator == 0 ? Panic.DIVISION_BY_ZERO : Panic.ARITHMETIC_OVERFLOW);
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            return prod0.unsafeDiv(denominator);
        }
        return _mulDivInvert(prod0, prod1, denominator, remainder);
    }

    /// @notice Calculates a×b÷denominator with full precision then rounds towards 0. Overflowing a uint256 or denominator == 0 are GIGO errors
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @return The 256-bit result
    function unsafeMulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        (uint256 prod0, uint256 prod1, uint256 remainder) = _mulDivSetup(a, b, denominator);
        // Overflow and zero-division checks are skipped
        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            return prod0.unsafeDiv(denominator);
        }
        return _mulDivInvert(prod0, prod1, denominator, remainder);
    }

    /// @notice Calculates a×b÷denominator with full precision then rounds towards 0. Overflowing a uint256 or denominator == 0 are GIGO errors
    /// @param a The multiplicand
    /// @param b The multiplier
    /// @param denominator The divisor
    /// @dev This is the branchless, straight line version of `unsafeMulDiv`. If we know that `prod1 != 0` this may be faster. Also this gives Solc a better chance to optimize.
    /// @return The 256-bit result
    function unsafeMulDivAlt(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        (uint256 prod0, uint256 prod1, uint256 remainder) = _mulDivSetup(a, b, denominator);
        return _mulDivInvert(prod0, prod1, denominator, remainder);
    }
}

// src/core/Permit2PaymentAbstract.sol

abstract contract Permit2PaymentAbstract is AbstractContext {
    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    function _isRestrictedTarget(address) internal view virtual returns (bool);

    function _operator() internal view virtual returns (address);

    function _permitToSellAmountCalldata(ISignatureTransfer.PermitTransferFrom calldata permit)
        internal
        view
        virtual
        returns (uint256 sellAmount);

    function _permitToSellAmount(ISignatureTransfer.PermitTransferFrom memory permit)
        internal
        view
        virtual
        returns (uint256 sellAmount);

    function _permitToTransferDetails(ISignatureTransfer.PermitTransferFrom memory permit, address recipient)
        internal
        view
        virtual
        returns (ISignatureTransfer.SignatureTransferDetails memory transferDetails, uint256 sellAmount);

    function _transferFromIKnowWhatImDoing(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        address from,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory sig,
        bool isForwarded
    ) internal virtual;

    function _transferFromIKnowWhatImDoing(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        address from,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory sig
    ) internal virtual;

    function _transferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        bytes memory sig,
        bool isForwarded
    ) internal virtual;

    function _transferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        bytes memory sig
    ) internal virtual;

    function _setOperatorAndCall(
        address target,
        bytes memory data,
        uint32 selector,
        function (bytes calldata) internal returns (bytes memory) callback
    ) internal virtual returns (bytes memory);

    modifier metaTx(address msgSender, bytes32 witness) virtual;

    modifier takerSubmitted() virtual;

    function _allowanceHolderTransferFrom(address token, address owner, address recipient, uint256 amount)
        internal
        virtual;
}

// src/core/FlashAccountingCommon.sol

/// This library is a highly-optimized, in-memory, enumerable mapping from tokens to amounts. It
/// consists of 2 components that must be kept synchronized. There is a `memory` array of `Note`
/// (aka `Note[] memory`) that has up to `MAX_TOKENS` pre-allocated. And there is an implicit heap
/// packed at the end of the array that stores the `Note`s. Each `Note` has a backpointer that knows
/// its location in the `Notes[] memory`. While the length of the `Notes[]` array grows and shrinks
/// as tokens are added and retired, heap objects are only cleared/deallocated when the context
/// returns. Looking up the `Note` object corresponding to a token uses the perfect hash formed by
/// `hashMul` and `hashMod`. Pay special attention to these parameters. See further below for
/// recommendations on how to select values for them. A hash collision will result in a revert with
/// signature `TokenHashCollision(address,address)`.
library NotesLib {
    uint256 private constant _ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

    /// This is the maximum number of tokens that may be involved in an action. Increasing or
    /// decreasing this value requires no other changes elsewhere in this file.
    uint256 internal constant MAX_TOKENS = 8;

    type NotePtr is uint256;
    type NotePtrPtr is uint256;

    struct Note {
        uint256 amount;
        IERC20 token;
        NotePtrPtr backPtr;
    }

    function construct() internal pure returns (Note[] memory r) {
        assembly ("memory-safe") {
            r := mload(0x40)
            // set the length of `r` to zero
            mstore(r, 0x00)
            // zeroize the heap
            codecopy(add(add(0x20, shl(0x05, MAX_TOKENS)), r), codesize(), mul(0x60, MAX_TOKENS))
            // allocate memory
            mstore(0x40, add(add(0x20, shl(0x07, MAX_TOKENS)), r))
        }
    }

    function eq(Note memory x, Note memory y) internal pure returns (bool r) {
        assembly ("memory-safe") {
            r := eq(x, y)
        }
    }

    function unsafeGet(Note[] memory a, uint256 i) internal pure returns (IERC20 retToken, uint256 retAmount) {
        assembly ("memory-safe") {
            let x := mload(add(add(0x20, shl(0x05, i)), a))
            retToken := mload(add(0x20, x))
            retAmount := mload(x)
        }
    }

    //// How to generate a perfect hash:
    ////
    //// The arguments `hashMul` and `hashMod` are required to form a perfect hash for a table with
    //// size `NotesLib.MAX_TOKENS` when applied to all the tokens involved in fills. The hash
    //// function is constructed as `uint256 hash = mulmod(uint256(uint160(address(token))),
    //// hashMul, hashMod) % NotesLib.MAX_TOKENS`.
    ////
    //// The "simple" or "obvious" way to do this is to simply try random 128-bit numbers for both
    //// `hashMul` and `hashMod` until you obtain a function that has no collisions when applied to
    //// the tokens involved in fills. A substantially more optimized algorithm can be obtained by
    //// selecting several (at least 10) prime values for `hashMod`, precomputing the limb moduluses
    //// for each value, and then selecting randomly from among them. The author recommends using
    //// the 10 largest 64-bit prime numbers: 2^64 - {59, 83, 95, 179, 189, 257, 279, 323, 353,
    //// 363}. `hashMul` can then be selected randomly or via some other optimized method.
    ////
    //// Note that in spite of the fact that some AMMs represent Ether (or the native asset of the
    //// chain) as `address(0)`, we represent Ether as `SettlerAbstract.ETH_ADDRESS` (the address of
    //// all `e`s) for homogeneity with other parts of the codebase, and because the decision to
    //// represent Ether as `address(0)` was stupid in the first place. `address(0)` represents the
    //// absence of a thing, not a special case of the thing. It creates confusion with
    //// uninitialized memory, storage, and variables.
    function get(Note[] memory a, IERC20 newToken, uint256 hashMul, uint256 hashMod)
        internal
        pure
        returns (NotePtr x)
    {
        assembly ("memory-safe") {
            newToken := and(_ADDRESS_MASK, newToken)
            x := add(add(0x20, shl(0x05, MAX_TOKENS)), a) // `x` now points at the first `Note` on the heap
            x := add(mod(mulmod(newToken, hashMul, hashMod), mul(0x60, MAX_TOKENS)), x) // combine with token hash
            // `x` now points at the exact `Note` object we want; let's check it to be sure, though
            let x_token_ptr := add(0x20, x)

            // check that we haven't encountered a hash collision. checking for a hash collision is
            // equivalent to checking for array out-of-bounds or overflow.
            {
                let old_token := mload(x_token_ptr)
                if mul(or(mload(add(0x40, x)), old_token), xor(old_token, newToken)) {
                    mstore(0x00, 0x9a62e8b4) // selector for `TokenHashCollision(address,address)`
                    mstore(0x20, old_token)
                    mstore(0x40, newToken)
                    revert(0x1c, 0x44)
                }
            }

            // zero `newToken` is a footgun; check for it
            if iszero(newToken) {
                mstore(0x00, 0xad1991f5) // selector for `ZeroToken()`
                revert(0x1c, 0x04)
            }

            // initialize the token (possibly redundant)
            mstore(x_token_ptr, newToken)
        }
    }

    function add(Note[] memory a, Note memory x) internal pure {
        assembly ("memory-safe") {
            let backptr_ptr := add(0x40, x)
            let backptr := mload(backptr_ptr)
            if iszero(backptr) {
                let len := add(0x01, mload(a))
                // We don't need to check for overflow or out-of-bounds access here; the checks in
                // `get` above for token collision handle that for us. It's not possible to `get`
                // more than `MAX_TOKENS` tokens
                mstore(a, len)
                backptr := add(shl(0x05, len), a)
                mstore(backptr, x)
                mstore(backptr_ptr, backptr)
            }
        }
    }

    function del(Note[] memory a, Note memory x) internal pure {
        assembly ("memory-safe") {
            let x_backptr_ptr := add(0x40, x)
            let x_backptr := mload(x_backptr_ptr)
            if x_backptr {
                // Clear the backpointer in the referred-to `Note`
                mstore(x_backptr_ptr, 0x00)
                // We do not deallocate `x`

                // Decrement the length of `a`
                let len := mload(a)
                mstore(a, sub(len, 0x01))

                // Check if this is a "swap and pop" or just a "pop"
                let end_ptr := add(shl(0x05, len), a)
                if iszero(eq(end_ptr, x_backptr)) {
                    // Overwrite the vacated indirection pointer `x_backptr` with the value at the end.
                    let end := mload(end_ptr)
                    mstore(x_backptr, end)

                    // Fix up the backpointer in `end` to point to the new location of the indirection
                    // pointer.
                    let end_backptr_ptr := add(0x40, end)
                    mstore(end_backptr_ptr, x_backptr)
                }
            }
        }
    }
}

library StateLib {
    using NotesLib for NotesLib.Note;
    using NotesLib for NotesLib.Note[];

    struct State {
        NotesLib.Note buy;
        NotesLib.Note sell;
        NotesLib.Note globalSell;
        uint256 globalSellAmount;
        uint256 _hashMul;
        uint256 _hashMod;
    }

    function construct(State memory state, IERC20 token, uint256 hashMul, uint256 hashMod)
        internal
        pure
        returns (NotesLib.Note[] memory notes)
    {
        assembly ("memory-safe") {
            // Solc is real dumb and has allocated a bunch of extra memory for us. Thanks solc.
            mstore(0x40, add(0xc0, state))
        }
        // All the pointers in `state` are now pointing into unallocated memory
        notes = NotesLib.construct();
        // The pointers in `state` are now illegally aliasing elements in `notes`
        NotesLib.NotePtr notePtr = notes.get(token, hashMul, hashMod);

        // Here we actually set the pointers into a legal area of memory
        setBuy(state, notePtr);
        setSell(state, notePtr);
        assembly ("memory-safe") {
            // Set `state.globalSell`
            mstore(add(0x40, state), notePtr)
        }
        state._hashMul = hashMul;
        state._hashMod = hashMod;
    }

    function setSell(State memory state, NotesLib.NotePtr notePtr) private pure {
        assembly ("memory-safe") {
            mstore(add(0x20, state), notePtr)
        }
    }

    function setSell(State memory state, NotesLib.Note[] memory notes, IERC20 token) internal pure {
        setSell(state, notes.get(token, state._hashMul, state._hashMod));
    }

    function setBuy(State memory state, NotesLib.NotePtr notePtr) private pure {
        assembly ("memory-safe") {
            mstore(state, notePtr)
        }
    }

    function setBuy(State memory state, NotesLib.Note[] memory notes, IERC20 token) internal pure {
        setBuy(state, notes.get(token, state._hashMul, state._hashMod));
    }
}

library Encoder {
    uint256 internal constant BASIS = 10_000;

    function encode(
        uint32 unlockSelector,
        address recipient,
        IERC20 sellToken,
        uint256 bps,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        uint256 amountOutMin
    ) internal view returns (bytes memory data) {
        if (bps > BASIS) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        if (amountOutMin > uint128(type(int128).max)) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        hashMul *= 96;
        hashMod *= 96;
        if (hashMul > type(uint128).max) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        if (hashMod > type(uint128).max) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        assembly ("memory-safe") {
            data := mload(0x40)

            let pathLen := mload(fills)
            mcopy(add(0xd3, data), add(0x20, fills), pathLen)

            mstore(add(0xb3, data), bps)
            mstore(add(0xb1, data), sellToken)
            mstore(add(0x9d, data), address()) // payer
            // feeOnTransfer (1 byte)

            mstore(add(0x88, data), hashMod)
            mstore(add(0x78, data), hashMul)
            mstore(add(0x68, data), amountOutMin)
            mstore(add(0x58, data), recipient)
            mstore(add(0x44, data), add(0x6f, pathLen))
            mstore(add(0x24, data), 0x20)
            mstore(add(0x04, data), and(0xffffffff, unlockSelector))
            mstore(data, add(0xb3, pathLen))
            mstore8(add(0xa8, data), feeOnTransfer)

            mstore(0x40, add(data, add(0xd3, pathLen)))
        }
    }

    function encodeVIP(
        uint32 unlockSelector,
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        bool isForwarded,
        uint256 amountOutMin
    ) internal pure returns (bytes memory data) {
        if (amountOutMin > uint128(type(int128).max)) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        hashMul *= 96;
        hashMod *= 96;
        if (hashMul > type(uint128).max) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        if (hashMod > type(uint128).max) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        assembly ("memory-safe") {
            data := mload(0x40)

            let pathLen := mload(fills)
            let sigLen := mload(sig)

            {
                let ptr := add(0x132, data)

                // sig length as 3 bytes goes at the end of the callback
                mstore(sub(add(sigLen, add(pathLen, ptr)), 0x1d), sigLen)

                // fills go at the end of the header
                mcopy(ptr, add(0x20, fills), pathLen)
                ptr := add(pathLen, ptr)

                // signature comes after the fills
                mcopy(ptr, add(0x20, sig), sigLen)
                ptr := add(sigLen, ptr)

                mstore(0x40, add(0x03, ptr))
            }

            mstore8(add(0x131, data), isForwarded)
            mcopy(add(0xf1, data), add(0x20, permit), 0x40)
            mcopy(add(0xb1, data), mload(permit), 0x40) // aliases `payer` on purpose
            mstore(add(0x9d, data), 0x00) // payer
            // feeOnTransfer (1 byte)

            mstore(add(0x88, data), hashMod)
            mstore(add(0x78, data), hashMul)
            mstore(add(0x68, data), amountOutMin)
            mstore(add(0x58, data), recipient)
            mstore(add(0x44, data), add(0xd1, add(pathLen, sigLen)))
            mstore(add(0x24, data), 0x20)
            mstore(add(0x04, data), and(0xffffffff, unlockSelector))
            mstore(data, add(0x115, add(pathLen, sigLen)))

            mstore8(add(0xa8, data), feeOnTransfer)
        }
    }
}

library Decoder {
    using SafeTransferLib for IERC20;
    using UnsafeMath for uint256;
    using NotesLib for NotesLib.Note;
    using NotesLib for NotesLib.Note[];
    using StateLib for StateLib.State;

    uint256 internal constant BASIS = 10_000;
    IERC20 internal constant ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// Update `state` for the next fill packed in `data`. This also may allocate/append `Note`s
    /// into `notes`. Returns the suffix of the bytes that are not consumed in the decoding
    /// process. The first byte of `data` describes which of the compact representations for the hop
    /// is used.
    ///
    ///   0 -> sell and buy tokens remain unchanged from the previous fill (pure multiplex)
    ///   1 -> sell token remains unchanged from the previous fill, buy token is read from `data` (diamond multiplex)
    ///   2 -> sell token becomes the buy token from the previous fill, new buy token is read from `data` (multihop)
    ///   3 -> both sell and buy token are read from `data`
    ///
    /// This function is responsible for calling `NotesLib.get(Note[] memory, IERC20, uint256,
    /// uint256)` (via `StateLib.setSell` and `StateLib.setBuy`), which maintains the `notes` array
    /// and heap.
    function updateState(StateLib.State memory state, NotesLib.Note[] memory notes, bytes calldata data)
        internal
        pure
        returns (bytes calldata)
    {
        bytes32 dataWord;
        assembly ("memory-safe") {
            dataWord := calldataload(data.offset)
        }
        uint256 dataConsumed = 1;

        uint256 caseKey = uint256(dataWord) >> 248;
        if (caseKey != 0) {
            notes.add(state.buy);

            if (caseKey > 1) {
                if (state.sell.amount == 0) {
                    notes.del(state.sell);
                }
                if (caseKey == 2) {
                    state.sell = state.buy;
                } else {
                    assert(caseKey == 3);

                    IERC20 sellToken = IERC20(address(uint160(uint256(dataWord) >> 88)));
                    assembly ("memory-safe") {
                        dataWord := calldataload(add(0x14, data.offset))
                    }
                    unchecked {
                        dataConsumed += 20;
                    }

                    state.setSell(notes, sellToken);
                }
            }

            IERC20 buyToken = IERC20(address(uint160(uint256(dataWord) >> 88)));
            unchecked {
                dataConsumed += 20;
            }

            state.setBuy(notes, buyToken);
            if (state.buy.eq(state.globalSell)) {
                revert BoughtSellToken(state.globalSell.token);
            }
        }

        assembly ("memory-safe") {
            data.offset := add(dataConsumed, data.offset)
            data.length := sub(data.length, dataConsumed)
            // we don't check for array out-of-bounds here; we will check it later in `_getHookData`
        }

        return data;
    }

    function overflowCheck(bytes calldata data) internal pure {
        if (data.length > 16777215) {
            Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
        }
    }

    /// Decode an ABI-ish encoded `bytes` from `data`. It is "-ish" in the sense that the encoding
    /// of the length doesn't take up an entire word. The length is encoded as only 3 bytes (2^24
    /// bytes of calldata consumes ~67M gas, much more than the block limit). The payload is also
    /// unpadded. The next fill's `bps` is encoded immediately after the `hookData` payload.
    function decodeBytes(bytes calldata data) internal pure returns (bytes calldata retData, bytes calldata hookData) {
        assembly ("memory-safe") {
            hookData.length := shr(0xe8, calldataload(data.offset))
            hookData.offset := add(0x03, data.offset)
            let hop := add(0x03, hookData.length)

            retData.offset := add(data.offset, hop)
            retData.length := sub(data.length, hop)
        }
    }

    function decodeHeader(bytes calldata data)
        internal
        pure
        returns (
            bytes calldata newData,
            // These values are user-supplied
            address recipient,
            uint256 minBuyAmount,
            uint256 hashMul,
            uint256 hashMod,
            bool feeOnTransfer,
            // `payer` is special and is authenticated
            address payer
        )
    {
        // These values are user-supplied
        assembly ("memory-safe") {
            recipient := shr(0x60, calldataload(data.offset))
            let packed := calldataload(add(0x14, data.offset))
            minBuyAmount := shr(0x80, packed)
            hashMul := and(0xffffffffffffffffffffffffffffffff, packed)
            packed := calldataload(add(0x34, data.offset))
            hashMod := shr(0x80, packed)
            feeOnTransfer := iszero(iszero(and(0x1000000000000000000000000000000, packed)))

            data.offset := add(0x45, data.offset)
            data.length := sub(data.length, 0x45)
            // we don't check for array out-of-bounds here; we will check it later in `initialize`
        }

        // `payer` is special and is authenticated
        assembly ("memory-safe") {
            payer := shr(0x60, calldataload(data.offset))

            data.offset := add(0x14, data.offset)
            data.length := sub(data.length, 0x14)
            // we don't check for array out-of-bounds here; we will check it later in `initialize`
        }

        newData = data;
    }

    function initialize(bytes calldata data, uint256 hashMul, uint256 hashMod, address payer)
        internal
        view
        returns (
            bytes calldata newData,
            StateLib.State memory state,
            NotesLib.Note[] memory notes,
            ISignatureTransfer.PermitTransferFrom calldata permit,
            bool isForwarded,
            bytes calldata sig
        )
    {
        {
            IERC20 sellToken;
            assembly ("memory-safe") {
                sellToken := shr(0x60, calldataload(data.offset))
            }
            // We don't advance `data` here because there's a special interaction between `payer`
            // (which is the 20 bytes in calldata immediately before `data`), `sellToken`, and
            // `permit` that's handled below.
            notes = state.construct(sellToken, hashMul, hashMod);
        }

        // This assembly block is just here to appease the compiler. We only use `permit` and `sig`
        // in the codepaths where they are set away from the values initialized here.
        assembly ("memory-safe") {
            permit := calldatasize()
            sig.offset := calldatasize()
            sig.length := 0x00
        }

        if (state.globalSell.token == ETH_ADDRESS) {
            assert(payer == address(this));

            uint16 bps;
            assembly ("memory-safe") {
                // `data` hasn't been advanced from decoding `sellToken` above. so we have to
                // implicitly advance it by 20 bytes to decode `bps` then advance by 22 bytes

                bps := shr(0x50, calldataload(data.offset))

                data.offset := add(0x16, data.offset)
                data.length := sub(data.length, 0x16)
                // We check for array out-of-bounds below
            }

            unchecked {
                state.globalSell.amount = (address(this).balance * bps).unsafeDiv(BASIS);
            }
        } else {
            if (payer == address(this)) {
                uint16 bps;
                assembly ("memory-safe") {
                    // `data` hasn't been advanced from decoding `sellToken` above. so we have to
                    // implicitly advance it by 20 bytes to decode `bps` then advance by 22 bytes

                    bps := shr(0x50, calldataload(data.offset))

                    data.offset := add(0x16, data.offset)
                    data.length := sub(data.length, 0x16)
                    // We check for array out-of-bounds below
                }

                unchecked {
                    state.globalSell.amount =
                        (state.globalSell.token.fastBalanceOf(address(this)) * bps).unsafeDiv(BASIS);
                }
            } else {
                assert(payer == address(0));

                assembly ("memory-safe") {
                    // this is super dirty, but it works because although `permit` is aliasing in
                    // the middle of `payer`, because `payer` is all zeroes, it's treated as padding
                    // for the first word of `permit`, which is the sell token
                    permit := sub(data.offset, 0x0c)
                    isForwarded := and(0x01, calldataload(add(0x55, data.offset)))

                    // `sig` is packed at the end of `data`, in "reverse ABI-ish encoded" fashion
                    sig.offset := sub(add(data.offset, data.length), 0x03)
                    sig.length := shr(0xe8, calldataload(sig.offset))
                    sig.offset := sub(sig.offset, sig.length)

                    // Remove `permit` and `isForwarded` from the front of `data`
                    data.offset := add(0x75, data.offset)
                    if gt(data.offset, sig.offset) { revert(0x00, 0x00) }

                    // Remove `sig` from the back of `data`
                    data.length := sub(sub(data.length, 0x78), sig.length)
                    // We check for array out-of-bounds below
                }
            }
        }

        Decoder.overflowCheck(data);
        newData = data;
    }
}

library Take {
    using UnsafeMath for uint256;
    using NotesLib for NotesLib.Note;
    using NotesLib for NotesLib.Note[];

    function _callSelector(uint256 selector, IERC20 token, address to, uint256 amount) internal {
        assembly ("memory-safe") {
            token := and(0xffffffffffffffffffffffffffffffffffffffff, token)
            if iszero(amount) {
                mstore(0x00, 0xcbf0dbf5) // selector for `ZeroBuyAmount(address)`
                mstore(0x20, token)
                revert(0x1c, 0x24)
            }
            let ptr := mload(0x40)
            mstore(ptr, selector)
            if eq(token, 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee) { token := 0x00 }
            mstore(add(0x20, ptr), token)
            mstore(add(0x40, ptr), and(0xffffffffffffffffffffffffffffffffffffffff, to))
            mstore(add(0x60, ptr), amount)
            if iszero(call(gas(), caller(), 0x00, add(0x1c, ptr), 0x64, 0x00, 0x00)) {
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
        }
    }

    /// `take` is responsible for removing the accumulated credit in each token from the vault. The
    /// current `state.buy` is the global buy token. We return the settled amount of that token
    /// (`buyAmount`), after checking it against the slippage limit (`minBuyAmount`). Each token
    /// with credit causes a corresponding call to `msg.sender.<selector>(token, recipient,
    /// amount)`.
    function take(
        StateLib.State memory state,
        NotesLib.Note[] memory notes,
        uint32 selector,
        address recipient,
        uint256 minBuyAmount
    ) internal returns (uint256 buyAmount) {
        notes.del(state.buy);
        if (state.sell.amount == 0) {
            notes.del(state.sell);
        }

        uint256 length = notes.length;
        // `length` of zero implies that we fully liquidated the global sell token (there is no
        // `amount` remaining) and that the only token in which we have credit is the global buy
        // token. We're about to `take` that token below.
        if (length != 0) {
            {
                NotesLib.Note memory firstNote = notes[0]; // out-of-bounds is impossible
                if (!firstNote.eq(state.globalSell)) {
                    // The global sell token being in a position other than the 1st would imply that
                    // at some point we _bought_ that token. This is illegal and results in a revert
                    // with reason `BoughtSellToken(address)`.
                    _callSelector(selector, firstNote.token, address(this), firstNote.amount);
                }
            }
            for (uint256 i = 1; i < length; i = i.unsafeInc()) {
                (IERC20 token, uint256 amount) = notes.unsafeGet(i);
                _callSelector(selector, token, address(this), amount);
            }
        }

        // The final token to be bought is considered the global buy token. We bypass `notes` and
        // read it directly from `state`. Check the slippage limit. Transfer to the recipient.
        {
            IERC20 buyToken = state.buy.token;
            buyAmount = state.buy.amount;
            if (buyAmount < minBuyAmount) {
                revert TooMuchSlippage(buyToken, minBuyAmount, buyAmount);
            }
            _callSelector(selector, buyToken, recipient, buyAmount);
        }
    }
}

// src/SettlerAbstract.sol

abstract contract SettlerAbstract is Permit2PaymentAbstract {
    // Permit2 Witness for meta transactions
    string internal constant SLIPPAGE_AND_ACTIONS_TYPE =
        "SlippageAndActions(address recipient,address buyToken,uint256 minAmountOut,bytes[] actions)";
    bytes32 internal constant SLIPPAGE_AND_ACTIONS_TYPEHASH =
        0x615e8d716cef7295e75dd3f1f10d679914ad6d7759e8e9459f0109ef75241701;
    uint256 internal constant BASIS = 10_000;
    IERC20 internal constant ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    constructor() {
        assert(SLIPPAGE_AND_ACTIONS_TYPEHASH == keccak256(bytes(SLIPPAGE_AND_ACTIONS_TYPE)));
    }

    function _hasMetaTxn() internal pure virtual returns (bool);

    function _dispatch(uint256 i, uint256 action, bytes calldata data) internal virtual returns (bool);

    function _div512to256(uint512 n, uint512 d) internal view virtual returns (uint256);
}

// src/core/UniswapV4Types.sol

type IHooks is address;

/// @dev Two `int128` values packed into a single `int256` where the upper 128 bits represent the amount0
/// and the lower 128 bits represent the amount1.
type BalanceDelta is int256;

using BalanceDeltaLibrary for BalanceDelta global;

/// @notice Library for getting the amount0 and amount1 deltas from the BalanceDelta type
library BalanceDeltaLibrary {
    function amount0(BalanceDelta balanceDelta) internal pure returns (int128 _amount0) {
        assembly ("memory-safe") {
            _amount0 := sar(128, balanceDelta)
        }
    }

    function amount1(BalanceDelta balanceDelta) internal pure returns (int128 _amount1) {
        assembly ("memory-safe") {
            _amount1 := signextend(15, balanceDelta)
        }
    }
}

interface IPoolManager {
    /// @notice All interactions on the contract that account deltas require unlocking. A caller that calls `unlock` must implement
    /// `IUnlockCallback(msg.sender).unlockCallback(data)`, where they interact with the remaining functions on this contract.
    /// @dev The only functions callable without an unlocking are `initialize` and `updateDynamicLPFee`
    /// @param data Any data to pass to the callback, via `IUnlockCallback(msg.sender).unlockCallback(data)`
    /// @return The data returned by the call to `IUnlockCallback(msg.sender).unlockCallback(data)`
    function unlock(bytes calldata data) external returns (bytes memory);

    /// @notice Returns the key for identifying a pool
    struct PoolKey {
        /// @notice The lower token of the pool, sorted numerically
        IERC20 token0;
        /// @notice The higher token of the pool, sorted numerically
        IERC20 token1;
        /// @notice The pool LP fee, capped at 1_000_000. If the highest bit is 1, the pool has a dynamic fee and must be exactly equal to 0x800000
        uint24 fee;
        /// @notice Ticks that involve positions must be a multiple of tick spacing
        int24 tickSpacing;
        /// @notice The hooks of the pool
        IHooks hooks;
    }

    struct SwapParams {
        /// Whether to swap token0 for token1 or vice versa
        bool zeroForOne;
        /// The desired input amount if negative (exactIn), or the desired output amount if positive (exactOut)
        int256 amountSpecified;
        /// The sqrt price at which, if reached, the swap will stop executing
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swap against the given pool
    /// @param key The pool to swap in
    /// @param params The parameters for swapping
    /// @param hookData The data to pass through to the swap hooks
    /// @return swapDelta The balance delta of the address swapping
    /// @dev Swapping on low liquidity pools may cause unexpected swap amounts when liquidity available is less than amountSpecified.
    /// Additionally note that if interacting with hooks that have the BEFORE_SWAP_RETURNS_DELTA_FLAG or AFTER_SWAP_RETURNS_DELTA_FLAG
    /// the hook may alter the swap input/output. Integrators should perform checks on the returned swapDelta.
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta swapDelta);

    /// @notice Writes the current ERC20 balance of the specified token to transient storage
    /// This is used to checkpoint balances for the manager and derive deltas for the caller.
    /// @dev This MUST be called before any ERC20 tokens are sent into the contract, but can be skipped
    /// for native tokens because the amount to settle is determined by the sent value.
    /// However, if an ERC20 token has been synced and not settled, and the caller instead wants to settle
    /// native funds, this function can be called with the native currency to then be able to settle the native currency
    function sync(IERC20 token) external;

    /// @notice Called by the user to net out some value owed to the user
    /// @dev Can also be used as a mechanism for _free_ flash loans
    /// @param token The token to withdraw from the pool manager
    /// @param to The address to withdraw to
    /// @param amount The amount of token to withdraw
    function take(IERC20 token, address to, uint256 amount) external;

    /// @notice Called by the user to pay what is owed
    /// @return paid The amount of token settled
    function settle() external payable returns (uint256 paid);
}

/// Solc emits code that is both gas inefficient and codesize bloated. By reimplementing these
/// function calls in Yul, we obtain significant improvements. Solc also emits an EXTCODESIZE check
/// when an external function doesn't return anything (`sync`). Obviously, we know that POOL_MANAGER
/// has code, so this omits those checks. Also, for compatibility, these functions identify
/// `SettlerAbstract.ETH_ADDRESS` (the address of all `e`s) and replace it with `address(0)`.
library UnsafePoolManager {
    function unsafeSync(IPoolManager poolManager, IERC20 token) internal {
        // It is the responsibility of the calling code to determine whether `token` is
        // `ETH_ADDRESS` and substitute it with `IERC20(address(0))` appropriately. This delegation
        // of responsibility is required because a call to `unsafeSync(0)` must be followed by a
        // value-bearing call to `unsafeSettle` instead of using `IERC20.safeTransfer`
        assembly ("memory-safe") {
            mstore(0x14, token)
            mstore(0x00, 0xa5841194000000000000000000000000) // selector for `sync(address)`
            if iszero(call(gas(), poolManager, 0x00, 0x10, 0x24, 0x00, 0x00)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
        }
    }

    function unsafeSwap(
        IPoolManager poolManager,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bytes calldata hookData
    ) internal returns (BalanceDelta r) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, 0xf3cd914c) // selector for `swap((address,address,uint24,int24,address),(bool,int256,uint160),bytes)`
            let token0 := mload(key)
            if eq(token0, 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee) { token0 := 0x00 }
            mstore(add(0x20, ptr), token0)
            mcopy(add(0x40, ptr), add(0x20, key), 0x80)
            mcopy(add(0xc0, ptr), params, 0x60)
            mstore(add(0x120, ptr), 0x120)
            mstore(add(0x140, ptr), hookData.length)
            calldatacopy(add(0x160, ptr), hookData.offset, hookData.length)
            if iszero(call(gas(), poolManager, 0x00, add(0x1c, ptr), add(0x144, hookData.length), 0x00, 0x20)) {
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            r := mload(0x00)
        }
    }

    function unsafeSettle(IPoolManager poolManager, uint256 value) internal returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x00, 0x11da60b4) // selector for `settle()`
            if iszero(call(gas(), poolManager, value, 0x1c, 0x04, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            r := mload(0x00)
        }
    }

    function unsafeSettle(IPoolManager poolManager) internal returns (uint256) {
        return unsafeSettle(poolManager, 0);
    }
}

/// @notice Interface for the callback executed when an address unlocks the pool manager
interface IUnlockCallback {
    /// @notice Called by the pool manager on `msg.sender` when the manager is unlocked
    /// @param data The data that was passed to the call to unlock
    /// @return Any data that you want to be returned from the unlock call
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

// src/core/UniswapV4Addresses.sol

IPoolManager constant MAINNET_POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
IPoolManager constant ARBITRUM_POOL_MANAGER = IPoolManager(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
IPoolManager constant AVALANCHE_POOL_MANAGER = IPoolManager(0x06380C0e0912312B5150364B9DC4542BA0DbBc85);
IPoolManager constant BASE_POOL_MANAGER = IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b);
IPoolManager constant BLAST_POOL_MANAGER = IPoolManager(0x1631559198A9e474033433b2958daBC135ab6446);
IPoolManager constant BNB_POOL_MANAGER = IPoolManager(0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF);
IPoolManager constant OPTIMISM_POOL_MANAGER = IPoolManager(0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3);
IPoolManager constant POLYGON_POOL_MANAGER = IPoolManager(0x67366782805870060151383F4BbFF9daB53e5cD6);
IPoolManager constant WORLDCHAIN_POOL_MANAGER = IPoolManager(0xb1860D529182ac3BC1F51Fa2ABd56662b7D13f33);

// src/core/DodoV1.sol

interface IDodoV1 {
    function sellBaseToken(uint256 amount, uint256 minReceiveQuote, bytes calldata data) external returns (uint256);

    function buyBaseToken(uint256 amount, uint256 maxPayQuote, bytes calldata data) external returns (uint256);

    function _R_STATUS_() external view returns (uint8);

    function _QUOTE_BALANCE_() external view returns (uint256);

    function _BASE_BALANCE_() external view returns (uint256);

    function _K_() external view returns (uint256);

    function _MT_FEE_RATE_() external view returns (uint256);

    function _LP_FEE_RATE_() external view returns (uint256);

    function getExpectedTarget() external view returns (uint256 baseTarget, uint256 quoteTarget);

    function getOraclePrice() external view returns (uint256);

    function _BASE_TOKEN_() external view returns (IERC20);

    function _QUOTE_TOKEN_() external view returns (IERC20);
}

library Math_1 {
    using UnsafeMath for uint256;

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        unchecked {
            uint256 z = x / 2 + 1;
            y = x;
            while (z < y) {
                y = z;
                z = (x.unsafeDiv(z) + z) / 2;
            }
        }
    }
}

library DecimalMath {
    using UnsafeMath for uint256;
    using Math_1 for uint256;

    uint256 constant ONE = 10 ** 18;

    function mul(uint256 target, uint256 d) internal pure returns (uint256) {
        unchecked {
            return target * d / ONE;
        }
    }

    function mulCeil(uint256 target, uint256 d) internal pure returns (uint256) {
        unchecked {
            return (target * d).unsafeDivUp(ONE);
        }
    }

    function divFloor(uint256 target, uint256 d) internal pure returns (uint256) {
        unchecked {
            return (target * ONE).unsafeDiv(d);
        }
    }

    function divCeil(uint256 target, uint256 d) internal pure returns (uint256) {
        unchecked {
            return (target * ONE).unsafeDivUp(d);
        }
    }
}

library DodoMath {
    using UnsafeMath for uint256;
    using Math_1 for uint256;

    /*
        Integrate dodo curve fron V1 to V2
        require V0>=V1>=V2>0
        res = (1-k)i(V1-V2)+ikV0*V0(1/V2-1/V1)
        let V1-V2=delta
        res = i*delta*(1-k+k(V0^2/V1/V2))
    */
    function _GeneralIntegrate(uint256 V0, uint256 V1, uint256 V2, uint256 i, uint256 k)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            uint256 fairAmount = DecimalMath.mul(i, V1 - V2); // i*delta
            uint256 V0V0V1V2 = DecimalMath.divCeil((V0 * V0).unsafeDiv(V1), V2);
            uint256 penalty = DecimalMath.mul(k, V0V0V1V2); // k(V0^2/V1/V2)
            return DecimalMath.mul(fairAmount, DecimalMath.ONE - k + penalty);
        }
    }

    /*
        The same with integration expression above, we have:
        i*deltaB = (Q2-Q1)*(1-k+kQ0^2/Q1/Q2)
        Given Q1 and deltaB, solve Q2
        This is a quadratic function and the standard version is
        aQ2^2 + bQ2 + c = 0, where
        a=1-k
        -b=(1-k)Q1-kQ0^2/Q1+i*deltaB
        c=-kQ0^2
        and Q2=(-b+sqrt(b^2+4(1-k)kQ0^2))/2(1-k)
        note: another root is negative, abondan
        if deltaBSig=true, then Q2>Q1
        if deltaBSig=false, then Q2<Q1
    */
    function _SolveQuadraticFunctionForTrade(uint256 Q0, uint256 Q1, uint256 ideltaB, bool deltaBSig, uint256 k)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            // calculate -b value and sig
            // -b = (1-k)Q1-kQ0^2/Q1+i*deltaB
            uint256 kQ02Q1 = (DecimalMath.mul(k, Q0) * Q0).unsafeDiv(Q1); // kQ0^2/Q1
            uint256 b = DecimalMath.mul(DecimalMath.ONE - k, Q1); // (1-k)Q1
            bool minusbSig = true;
            if (deltaBSig) {
                b += ideltaB; // (1-k)Q1+i*deltaB
            } else {
                kQ02Q1 += ideltaB; // i*deltaB+kQ0^2/Q1
            }
            if (b >= kQ02Q1) {
                b -= kQ02Q1;
                minusbSig = true;
            } else {
                b = kQ02Q1 - b;
                minusbSig = false;
            }

            // calculate sqrt
            uint256 squareRoot = DecimalMath.mul((DecimalMath.ONE - k) * 4, DecimalMath.mul(k, Q0) * Q0); // 4(1-k)kQ0^2
            squareRoot = (b * b + squareRoot).sqrt(); // sqrt(b*b+4(1-k)kQ0*Q0)

            // final res
            uint256 denominator = (DecimalMath.ONE - k) * 2; // 2(1-k)
            uint256 numerator;
            if (minusbSig) {
                numerator = b + squareRoot;
            } else {
                numerator = squareRoot - b;
            }

            if (deltaBSig) {
                return DecimalMath.divFloor(numerator, denominator);
            } else {
                return DecimalMath.divCeil(numerator, denominator);
            }
        }
    }

    /*
        Start from the integration function
        i*deltaB = (Q2-Q1)*(1-k+kQ0^2/Q1/Q2)
        Assume Q2=Q0, Given Q1 and deltaB, solve Q0
        let fairAmount = i*deltaB
    */
    function _SolveQuadraticFunctionForTarget(uint256 V1, uint256 k, uint256 fairAmount)
        internal
        pure
        returns (uint256 V0)
    {
        unchecked {
            // V0 = V1+V1*(sqrt-1)/2k
            uint256 sqrt = DecimalMath.divCeil(DecimalMath.mul(k, fairAmount) * 4, V1);
            sqrt = ((sqrt + DecimalMath.ONE) * DecimalMath.ONE).sqrt();
            uint256 premium = DecimalMath.divCeil(sqrt - DecimalMath.ONE, k * 2);
            // V0 is greater than or equal to V1 according to the solution
            return DecimalMath.mul(V1, DecimalMath.ONE + premium);
        }
    }
}

abstract contract DodoSellHelper {
    using Math_1 for uint256;

    enum RStatus {
        ONE,
        ABOVE_ONE,
        BELOW_ONE
    }

    struct DodoState {
        uint256 oraclePrice;
        uint256 K;
        uint256 B;
        uint256 Q;
        uint256 baseTarget;
        uint256 quoteTarget;
        RStatus rStatus;
    }

    function dodoQuerySellQuoteToken(IDodoV1 dodo, uint256 amount) internal view returns (uint256) {
        DodoState memory state;
        (state.baseTarget, state.quoteTarget) = dodo.getExpectedTarget();
        state.rStatus = RStatus(dodo._R_STATUS_());
        state.oraclePrice = dodo.getOraclePrice();
        state.Q = dodo._QUOTE_BALANCE_();
        state.B = dodo._BASE_BALANCE_();
        state.K = dodo._K_();

        unchecked {
            uint256 boughtAmount;
            // Determine the status (RStatus) and calculate the amount based on the
            // state
            if (state.rStatus == RStatus.ONE) {
                boughtAmount = _ROneSellQuoteToken(amount, state);
            } else if (state.rStatus == RStatus.ABOVE_ONE) {
                boughtAmount = _RAboveSellQuoteToken(amount, state);
            } else {
                uint256 backOneBase = state.B - state.baseTarget;
                uint256 backOneQuote = state.quoteTarget - state.Q;
                if (amount <= backOneQuote) {
                    boughtAmount = _RBelowSellQuoteToken(amount, state);
                } else {
                    boughtAmount = backOneBase + _ROneSellQuoteToken(amount - backOneQuote, state);
                }
            }
            // Calculate fees
            return DecimalMath.divFloor(boughtAmount, DecimalMath.ONE + dodo._MT_FEE_RATE_() + dodo._LP_FEE_RATE_());
        }
    }

    function _ROneSellQuoteToken(uint256 amount, DodoState memory state)
        private
        pure
        returns (uint256 receiveBaseToken)
    {
        unchecked {
            uint256 i = DecimalMath.divFloor(DecimalMath.ONE, state.oraclePrice);
            uint256 B2 = DodoMath._SolveQuadraticFunctionForTrade(
                state.baseTarget, state.baseTarget, DecimalMath.mul(i, amount), false, state.K
            );
            return state.baseTarget - B2;
        }
    }

    function _RAboveSellQuoteToken(uint256 amount, DodoState memory state)
        private
        pure
        returns (uint256 receieBaseToken)
    {
        unchecked {
            uint256 i = DecimalMath.divFloor(DecimalMath.ONE, state.oraclePrice);
            uint256 B2 = DodoMath._SolveQuadraticFunctionForTrade(
                state.baseTarget, state.B, DecimalMath.mul(i, amount), false, state.K
            );
            return state.B - B2;
        }
    }

    function _RBelowSellQuoteToken(uint256 amount, DodoState memory state)
        private
        pure
        returns (uint256 receiveBaseToken)
    {
        unchecked {
            uint256 Q1 = state.Q + amount;
            uint256 i = DecimalMath.divFloor(DecimalMath.ONE, state.oraclePrice);
            return DodoMath._GeneralIntegrate(state.quoteTarget, Q1, state.Q, i, state.K);
        }
    }
}

abstract contract DodoV1 is SettlerAbstract, DodoSellHelper {
    using UnsafeMath for uint256;
    using SafeTransferLib for IERC20;

    function sellToDodoV1(IERC20 sellToken, uint256 bps, IDodoV1 dodo, bool quoteForBase, uint256 minBuyAmount)
        internal
    {
        uint256 sellAmount;
        unchecked {
            sellAmount = (sellToken.fastBalanceOf(address(this)) * bps).unsafeDiv(BASIS);
        }
        sellToken.safeApproveIfBelow(address(dodo), sellAmount);
        if (quoteForBase) {
            uint256 buyAmount = dodoQuerySellQuoteToken(dodo, sellAmount);
            if (buyAmount < minBuyAmount) {
                revert TooMuchSlippage(dodo._BASE_TOKEN_(), minBuyAmount, buyAmount);
            }
            dodo.buyBaseToken(buyAmount, sellAmount, new bytes(0));
        } else {
            dodo.sellBaseToken(sellAmount, minBuyAmount, new bytes(0));
        }
    }
}

// src/core/DodoV2.sol

interface IDodoV2 {
    function sellBase(address to) external returns (uint256 receiveQuoteAmount);
    function sellQuote(address to) external returns (uint256 receiveBaseAmount);

    function _BASE_TOKEN_() external view returns (IERC20);
    function _QUOTE_TOKEN_() external view returns (IERC20);
}

abstract contract DodoV2 is SettlerAbstract {
    using UnsafeMath for uint256;
    using SafeTransferLib for IERC20;

    function sellToDodoV2(
        address recipient,
        IERC20 sellToken,
        uint256 bps,
        IDodoV2 dodo,
        bool quoteForBase,
        uint256 minBuyAmount
    ) internal returns (uint256 buyAmount) {
        if (bps != 0) {
            uint256 sellAmount;
            unchecked {
                sellAmount = (sellToken.fastBalanceOf(address(this)) * bps).unsafeDiv(BASIS);
            }
            sellToken.safeTransfer(address(dodo), sellAmount);
        }
        if (quoteForBase) {
            buyAmount = dodo.sellQuote(recipient);
            if (buyAmount < minBuyAmount) {
                revert TooMuchSlippage(dodo._BASE_TOKEN_(), minBuyAmount, buyAmount);
            }
        } else {
            buyAmount = dodo.sellBase(recipient);
            if (buyAmount < minBuyAmount) {
                revert TooMuchSlippage(dodo._QUOTE_TOKEN_(), minBuyAmount, buyAmount);
            }
        }
    }
}

// src/core/MakerPSM.sol

interface IPSM {
    /// @dev Get the fee for selling DAI to USDC in PSM
    /// @return tout toll out [wad]
    function tout() external view returns (uint256);

    /// @dev Get the address of the underlying vault powering PSM
    /// @return address of gemJoin contract
    function gemJoin() external view returns (address);

    /// @dev Sell USDC for DAI
    /// @param usr The address of the account trading USDC for DAI.
    /// @param gemAmt The amount of USDC to sell in USDC base units
    /// @return daiOutWad The amount of Dai bought.
    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOutWad);

    /// @dev Buy USDC for DAI
    /// @param usr The address of the account trading DAI for USDC
    /// @param gemAmt The amount of USDC to buy in USDC base units
    /// @return daiInWad The amount of Dai required to sell.
    function buyGem(address usr, uint256 gemAmt) external returns (uint256 daiInWad);
}

// Maker units https://github.com/makerdao/dss/blob/master/DEVELOPING.md
// wad: fixed point decimal with 18 decimals (for basic quantities, e.g. balances)
uint256 constant WAD = 10 ** 18;

IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
IPSM constant LitePSM = IPSM(0xf6e72Db5454dd049d0788e411b06CfAF16853042);

abstract contract MakerPSM is SettlerAbstract {
    using UnsafeMath for uint256;
    using SafeTransferLib for IERC20;

    uint256 private immutable USDC_basis;

    constructor() {
        assert(block.chainid == 1 || block.chainid == 31337);
        DAI.safeApprove(address(LitePSM), type(uint256).max);
        // LitePSM is its own join
        USDC.safeApprove(address(LitePSM), type(uint256).max);
        USDC_basis = 10 ** USDC.decimals();
    }

    function sellToMakerPsm(address recipient, uint256 bps, bool buyGem, uint256 amountOutMin)
        internal
        returns (uint256 buyAmount)
    {
        if (buyGem) {
            unchecked {
                // phantom overflow can't happen here because DAI has decimals = 18
                uint256 sellAmount = (DAI.fastBalanceOf(address(this)) * bps).unsafeDiv(BASIS);

                uint256 feeDivisor = LitePSM.tout() + WAD; // eg. 1.001 * 10 ** 18 with 0.1% fee [tout is in wad];
                // overflow can't happen at all because DAI is reasonable and PSM prohibits gemToken with decimals > 18
                buyAmount = (sellAmount * USDC_basis).unsafeDiv(feeDivisor);
                if (buyAmount < amountOutMin) {
                    revert TooMuchSlippage(USDC, amountOutMin, buyAmount);
                }

                // DAI.safeApproveIfBelow(address(LitePSM), sellAmount);
                LitePSM.buyGem(recipient, buyAmount);
            }
        } else {
            // phantom overflow can't happen here because PSM prohibits gemToken with decimals > 18
            uint256 sellAmount;
            unchecked {
                sellAmount = (USDC.fastBalanceOf(address(this)) * bps).unsafeDiv(BASIS);
            }
            // USDC.safeApproveIfBelow(LitePSM.gemJoin(), sellAmount);
            buyAmount = LitePSM.sellGem(recipient, sellAmount);
            if (buyAmount < amountOutMin) {
                revert TooMuchSlippage(DAI, amountOutMin, buyAmount);
            }
        }
    }
}

// src/core/RfqOrderSettlement.sol

abstract contract RfqOrderSettlement is SettlerAbstract {
    using SafeTransferLib for IERC20;
    using FullMath for uint256;

    struct Consideration {
        IERC20 token;
        uint256 amount;
        address counterparty;
        bool partialFillAllowed;
    }

    string internal constant CONSIDERATION_TYPE =
        "Consideration(address token,uint256 amount,address counterparty,bool partialFillAllowed)";
    // `string.concat` isn't recognized by solc as compile-time constant, but `abi.encodePacked` is
    string internal constant CONSIDERATION_WITNESS =
        string(abi.encodePacked("Consideration consideration)", CONSIDERATION_TYPE, TOKEN_PERMISSIONS_TYPE));
    bytes32 internal constant CONSIDERATION_TYPEHASH =
        0x7d806873084f389a66fd0315dead7adaad8ae6e8b6cf9fb0d3db61e5a91c3ffa;

    string internal constant RFQ_ORDER_TYPE =
        "RfqOrder(Consideration makerConsideration,Consideration takerConsideration)";
    string internal constant RFQ_ORDER_TYPE_RECURSIVE = string(abi.encodePacked(RFQ_ORDER_TYPE, CONSIDERATION_TYPE));
    bytes32 internal constant RFQ_ORDER_TYPEHASH = 0x49fa719b76f0f6b7e76be94b56c26671a548e1c712d5b13dc2874f70a7598276;

    function _hashConsideration(Consideration memory consideration) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            let ptr := sub(consideration, 0x20)
            let oldValue := mload(ptr)
            mstore(ptr, CONSIDERATION_TYPEHASH)
            result := keccak256(ptr, 0xa0)
            mstore(ptr, oldValue)
        }
    }

    function _logRfqOrder(bytes32 makerConsiderationHash, bytes32 takerConsiderationHash, uint128 makerFilledAmount)
        private
    {
        assembly ("memory-safe") {
            mstore(0x00, RFQ_ORDER_TYPEHASH)
            mstore(0x20, makerConsiderationHash)
            let ptr := mload(0x40)
            mstore(0x40, takerConsiderationHash)
            let orderHash := keccak256(0x00, 0x60)
            mstore(0x40, ptr)
            mstore(0x10, makerFilledAmount)
            mstore(0x00, orderHash)
            log0(0x00, 0x30)
        }
    }

    constructor() {
        assert(CONSIDERATION_TYPEHASH == keccak256(bytes(CONSIDERATION_TYPE)));
        assert(RFQ_ORDER_TYPEHASH == keccak256(bytes(RFQ_ORDER_TYPE_RECURSIVE)));
    }

    /// @dev Settle an RfqOrder between maker and taker transfering funds directly between the counterparties. Either
    ///      two Permit2 signatures are consumed, with the maker Permit2 containing a witness of the RfqOrder, or
    ///      AllowanceHolder is supported for the taker payment. The Maker has signed the same order as the
    ///      Taker. Submission may be directly by the taker or via a third party with the Taker signing a witness.
    /// @dev if used, the taker's witness is not calculated nor verified here as calling function is trusted
    function fillRfqOrderVIP(
        address recipient,
        ISignatureTransfer.PermitTransferFrom memory makerPermit,
        address maker,
        bytes memory makerSig,
        ISignatureTransfer.PermitTransferFrom memory takerPermit,
        bytes memory takerSig
    ) internal {
        if (!_hasMetaTxn()) {
            assert(makerPermit.permitted.amount <= type(uint256).max - BASIS);
        }
        (ISignatureTransfer.SignatureTransferDetails memory makerTransferDetails, uint256 makerAmount) =
            _permitToTransferDetails(makerPermit, recipient);
        // In theory, the taker permit could invoke the balance-proportional sell amount logic. However,
        // because we hash the sell amount computed here into the maker's consideration (witness) only a
        // balance-proportional sell amount that corresponds exactly to the signed order would avoid a
        // revert. In other words, no unexpected behavior is possible. It's pointless to prohibit the
        // use of that logic.
        (ISignatureTransfer.SignatureTransferDetails memory takerTransferDetails, uint256 takerAmount) =
            _permitToTransferDetails(takerPermit, maker);

        bytes32 witness = _hashConsideration(
            Consideration({
                token: IERC20(takerPermit.permitted.token),
                amount: takerAmount,
                counterparty: _msgSender(),
                partialFillAllowed: false
            })
        );
        _transferFrom(takerPermit, takerTransferDetails, takerSig);
        _transferFromIKnowWhatImDoing(
            makerPermit, makerTransferDetails, maker, witness, CONSIDERATION_WITNESS, makerSig, false
        );

        _logRfqOrder(
            witness,
            _hashConsideration(
                Consideration({
                    token: IERC20(makerPermit.permitted.token),
                    amount: makerAmount,
                    counterparty: maker,
                    partialFillAllowed: false
                })
            ),
            uint128(makerAmount)
        );
    }

    /// @dev Settle an RfqOrder between maker and Settler retaining funds in this contract.
    /// @dev pre-condition: msgSender has been authenticated against the requestor
    /// One Permit2 signature is consumed, with the maker Permit2 containing a witness of the RfqOrder.
    // In this variant, Maker pays recipient and Settler pays Maker
    function fillRfqOrderSelfFunded(
        address recipient,
        ISignatureTransfer.PermitTransferFrom memory permit,
        address maker,
        bytes memory makerSig,
        IERC20 takerToken,
        uint256 maxTakerAmount
    ) internal {
        if (!_hasMetaTxn()) {
            assert(permit.permitted.amount <= type(uint256).max - BASIS);
        }
        // Compute witnesses. These are based on the quoted maximum amounts. We will modify them
        // later to adjust for the actual settled amount, which may be modified by encountered
        // slippage.
        (ISignatureTransfer.SignatureTransferDetails memory transferDetails, uint256 makerAmount) =
            _permitToTransferDetails(permit, recipient);

        bytes32 takerWitness = _hashConsideration(
            Consideration({
                token: IERC20(permit.permitted.token),
                amount: makerAmount,
                counterparty: maker,
                partialFillAllowed: true
            })
        );
        bytes32 makerWitness = _hashConsideration(
            Consideration({
                token: takerToken,
                amount: maxTakerAmount,
                counterparty: _msgSender(),
                partialFillAllowed: true
            })
        );

        // Now we adjust the transfer amounts to compensate for encountered slippage. Rounding is
        // performed in the maker's favor.
        uint256 takerAmount = takerToken.fastBalanceOf(address(this));
        if (takerAmount > maxTakerAmount) {
            takerAmount = maxTakerAmount;
        }
        transferDetails.requestedAmount = makerAmount = makerAmount.unsafeMulDiv(takerAmount, maxTakerAmount);

        // Now that we have all the relevant information, make the transfers and log the order.
        takerToken.safeTransfer(maker, takerAmount);
        _transferFromIKnowWhatImDoing(
            permit, transferDetails, maker, makerWitness, CONSIDERATION_WITNESS, makerSig, false
        );

        _logRfqOrder(makerWitness, takerWitness, uint128(makerAmount));
    }
}

// src/core/UniswapV2.sol

interface IUniV2Pair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112, uint112, uint32);

    function swap(uint256, uint256, address, bytes calldata) external;
}

abstract contract UniswapV2 is SettlerAbstract {
    using SafeTransferLib for IERC20;

    // bytes4(keccak256("getReserves()"))
    uint32 private constant UNI_PAIR_RESERVES_SELECTOR = 0x0902f1ac;
    // bytes4(keccak256("swap(uint256,uint256,address,bytes)"))
    uint32 private constant UNI_PAIR_SWAP_SELECTOR = 0x022c0d9f;
    // bytes4(keccak256("transfer(address,uint256)"))
    uint32 private constant ERC20_TRANSFER_SELECTOR = 0xa9059cbb;
    // bytes4(keccak256("balanceOf(address)"))
    uint32 private constant ERC20_BALANCEOF_SELECTOR = 0x70a08231;

    /// @dev Sell a token for another token using UniswapV2.
    function sellToUniswapV2(
        address recipient,
        address sellToken,
        uint256 bps,
        address pool,
        uint24 swapInfo,
        uint256 minBuyAmount
    ) internal {
        // Preventing calls to Permit2 or AH is not explicitly required as neither of these contracts implement the `swap` nor `transfer` selector

        // |7|6|5|4|3|2|1|0| - bit positions in swapInfo (uint8)
        // |0|0|0|0|0|0|F|Z| - Z: zeroForOne flag, F: sellTokenHasFee flag
        bool zeroForOne = (swapInfo & 1) == 1; // Extract the least significant bit (bit 0)
        bool sellTokenHasFee = (swapInfo & 2) >> 1 == 1; // Extract the second least significant bit (bit 1) and shift it right
        uint256 feeBps = swapInfo >> 8;

        uint256 sellAmount;
        uint256 buyAmount;
        // If bps is zero we assume there are no funds within this contract, skip the updating sellAmount.
        // This case occurs if the pool is being chained, in which the funds have been sent directly to the pool
        if (bps != 0) {
            // We don't care about phantom overflow here because reserves are
            // limited to 112 bits. Any token balance that would overflow here would
            // also break UniV2.
            // It is *possible* to set `bps` above the basis and therefore
            // cause an overflow on this multiplication. However, `bps` is
            // passed as authenticated calldata, so this is a GIGO error that we
            // do not attempt to fix.
            unchecked {
                sellAmount = IERC20(sellToken).fastBalanceOf(address(this)) * bps / BASIS;
            }
        }
        assembly ("memory-safe") {
            let ptr := mload(0x40)

            // transfer sellAmount (a non zero amount) of sellToken to the pool
            if sellAmount {
                mstore(ptr, ERC20_TRANSFER_SELECTOR)
                mstore(add(ptr, 0x20), pool)
                mstore(add(ptr, 0x40), sellAmount)
                // ...||ERC20_TRANSFER_SELECTOR|pool|sellAmount|
                if iszero(call(gas(), sellToken, 0, add(ptr, 0x1c), 0x44, 0x00, 0x20)) { bubbleRevert(ptr) }
                if iszero(or(iszero(returndatasize()), and(iszero(lt(returndatasize(), 0x20)), eq(mload(0x00), 1)))) {
                    revert(0, 0)
                }
            }

            // get pool reserves
            let sellReserve
            let buyReserve
            mstore(0x00, UNI_PAIR_RESERVES_SELECTOR)
            // ||UNI_PAIR_RESERVES_SELECTOR|
            if iszero(staticcall(gas(), pool, 0x1c, 0x04, 0x00, 0x40)) { bubbleRevert(ptr) }
            if lt(returndatasize(), 0x40) { revert(0, 0) }
            {
                let r := shl(5, zeroForOne)
                buyReserve := mload(r)
                sellReserve := mload(xor(0x20, r))
            }

            // Update the sell amount in the following cases:
            //   the funds are in the pool already (flagged by sellAmount being 0)
            //   the sell token has a fee (flagged by sellTokenHasFee)
            if or(iszero(sellAmount), sellTokenHasFee) {
                // retrieve the sellToken balance of the pool
                mstore(0x00, ERC20_BALANCEOF_SELECTOR)
                mstore(0x20, and(0xffffffffffffffffffffffffffffffffffffffff, pool))
                // ||ERC20_BALANCEOF_SELECTOR|pool|
                if iszero(staticcall(gas(), sellToken, 0x1c, 0x24, 0x00, 0x20)) { bubbleRevert(ptr) }
                if lt(returndatasize(), 0x20) { revert(0, 0) }
                let bal := mload(0x00)

                // determine real sellAmount by comparing pool's sellToken balance to reserve amount
                if lt(bal, sellReserve) {
                    mstore(0x00, 0x4e487b71) // selector for `Panic(uint256)`
                    mstore(0x20, 0x11) // panic code for arithmetic underflow
                    revert(0x1c, 0x24)
                }
                sellAmount := sub(bal, sellReserve)
            }

            // compute buyAmount based on sellAmount and reserves
            let sellAmountWithFee := mul(sellAmount, sub(10000, feeBps))
            buyAmount := div(mul(sellAmountWithFee, buyReserve), add(sellAmountWithFee, mul(sellReserve, 10000)))
            let swapCalldata := add(ptr, 0x1c)
            // set up swap call selector and empty callback data
            mstore(ptr, UNI_PAIR_SWAP_SELECTOR)
            mstore(add(ptr, 0x80), 0x80) // offset to length of data
            mstore(add(ptr, 0xa0), 0) // length of data

            // set amount0Out and amount1Out
            {
                // If `zeroForOne`, offset is 0x24, else 0x04
                let offset := add(0x04, shl(5, zeroForOne))
                mstore(add(swapCalldata, offset), buyAmount)
                mstore(add(swapCalldata, xor(0x20, offset)), 0)
            }

            mstore(add(swapCalldata, 0x44), and(0xffffffffffffffffffffffffffffffffffffffff, recipient))
            // ...||UNI_PAIR_SWAP_SELECTOR|amount0Out|amount1Out|recipient|data|

            // perform swap at the pool sending bought tokens to the recipient
            if iszero(call(gas(), pool, 0, swapCalldata, 0xa4, 0, 0)) { bubbleRevert(swapCalldata) }

            // revert with the return data from the most recent call
            function bubbleRevert(p) {
                returndatacopy(p, 0, returndatasize())
                revert(p, returndatasize())
            }
        }
        if (buyAmount < minBuyAmount) {
            revert TooMuchSlippage(
                IERC20(zeroForOne ? IUniV2Pair(pool).token1() : IUniV2Pair(pool).token0()), minBuyAmount, buyAmount
            );
        }
    }
}

// src/core/CurveTricrypto.sol

interface ICurveTricrypto {
    function exchange_extended(
        uint256 sellIndex,
        uint256 buyIndex,
        uint256 sellAmount,
        uint256 minBuyAmount,
        bool useEth,
        address payer,
        address receiver,
        bytes32 callbackSelector
    ) external returns (uint256 buyAmount);
}

interface ICurveTricryptoCallback {
    // The function name/selector is arbitrary, but the arguments are controlled by the pool
    function curveTricryptoSwapCallback(
        address payer,
        address receiver,
        IERC20 sellToken,
        uint256 sellAmount,
        uint256 buyAmount
    ) external;
}

abstract contract CurveTricrypto is SettlerAbstract {
    using UnsafeMath for uint256;
    using SafeTransferLib for IERC20;
    using AddressDerivation for address;

    function _curveFactory() internal virtual returns (address);
    // uint256 private constant codePrefixLen = 0x539d;
    // bytes32 private constant codePrefixHash = 0xec96085e693058e09a27755c07882ced27117a3161b1fdaf131a14c7db9978b7;

    function sellToCurveTricryptoVIP(
        address recipient,
        uint80 poolInfo,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 minBuyAmount
    ) internal {
        uint256 sellAmount = _permitToSellAmount(permit);
        uint64 factoryNonce = uint64(poolInfo >> 16);
        uint8 sellIndex = uint8(poolInfo >> 8);
        uint8 buyIndex = uint8(poolInfo);
        address pool = _curveFactory().deriveContract(factoryNonce);
        /*
        bytes32 codePrefixHashActual;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            extcodecopy(pool, ptr, 0x00, codePrefixLen)
            codePrefixHashActual := keccak256(ptr, codePrefixLen)
        }
        if (codePrefixHashActual != codePrefixHash) {
            revert ConfusedDeputy();
        }
        */
        bool isForwarded = _isForwarded();
        assembly ("memory-safe") {
            tstore(0x00, isForwarded)
            tstore(0x01, mload(add(0x20, mload(permit)))) // amount
            tstore(0x02, mload(add(0x20, permit))) // nonce
            tstore(0x03, mload(add(0x40, permit))) // deadline
            for {
                let src := add(0x20, sig)
                let end
                {
                    let len := mload(sig)
                    end := add(len, src)
                    tstore(0x04, len)
                }
                let dst := 0x05
            } lt(src, end) {
                src := add(0x20, src)
                dst := add(0x01, dst)
            } { tstore(dst, mload(src)) }
        }
        _setOperatorAndCall(
            pool,
            abi.encodeCall(
                ICurveTricrypto.exchange_extended,
                (
                    sellIndex,
                    buyIndex,
                    sellAmount,
                    minBuyAmount,
                    false,
                    address(0), // payer
                    recipient,
                    bytes32(ICurveTricryptoCallback.curveTricryptoSwapCallback.selector)
                )
            ),
            uint32(ICurveTricryptoCallback.curveTricryptoSwapCallback.selector),
            _curveTricryptoSwapCallback
        );
    }

    function _curveTricryptoSwapCallback(bytes calldata data) private returns (bytes memory) {
        require(data.length == 0xa0);
        address payer;
        IERC20 sellToken;
        uint256 sellAmount;
        assembly ("memory-safe") {
            payer := calldataload(data.offset)
            let err := shr(0xa0, payer)
            sellToken := calldataload(add(0x40, data.offset))
            err := or(shr(0xa0, sellToken), err)
            sellAmount := calldataload(add(0x60, data.offset))
            if err { revert(0x00, 0x00) }
        }
        curveTricryptoSwapCallback(payer, address(0), sellToken, sellAmount, 0);
        return new bytes(0);
    }

    function curveTricryptoSwapCallback(address payer, address, IERC20 sellToken, uint256 sellAmount, uint256)
        private
    {
        assert(payer == address(0));
        bool isForwarded;
        uint256 permittedAmount;
        uint256 nonce;
        uint256 deadline;
        bytes memory sig;
        assembly ("memory-safe") {
            isForwarded := tload(0x00)
            tstore(0x00, 0x00)
            permittedAmount := tload(0x01)
            tstore(0x01, 0x00)
            nonce := tload(0x02)
            tstore(0x02, 0x00)
            deadline := tload(0x03)
            tstore(0x03, 0x00)
            sig := mload(0x40)
            for {
                let dst := add(0x20, sig)
                let end
                {
                    let len := tload(0x04)
                    tstore(0x04, 0x00)
                    end := add(dst, len)
                    mstore(sig, len)
                    mstore(0x40, end)
                }
                let src := 0x05
            } lt(dst, end) {
                src := add(0x01, src)
                dst := add(0x20, dst)
            } {
                mstore(dst, tload(src))
                tstore(src, 0x00)
            }
        }
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(sellToken), amount: permittedAmount}),
            nonce: nonce,
            deadline: deadline
        });
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: msg.sender, requestedAmount: sellAmount});
        _transferFrom(permit, transferDetails, sig, isForwarded);
    }
}

// src/core/MaverickV2.sol

// Maverick AMM V2 is not open-source. The source code was disclosed to the
// developers of 0x Settler confidentially and recompiled privately. The
// deployed bytecode inithash matches the privately recompiled inithash.
bytes32 constant maverickV2InitHash = 0xbb7b783eb4b8ca46925c5384a6b9919df57cb83da8f76e37291f58d0dd5c439a;

// https://docs.mav.xyz/technical-reference/contract-addresses/v2-contract-addresses
// For chains: mainnet, base, bnb, arbitrum, scroll, sepolia
address constant maverickV2Factory = 0x0A7e848Aca42d879EF06507Fca0E7b33A0a63c1e;

interface IMaverickV2Pool {
    /**
     * @notice Parameters for swap.
     * @param amount Amount of the token that is either the input if exactOutput is false
     * or the output if exactOutput is true.
     * @param tokenAIn Boolean indicating whether tokenA is the input.
     * @param exactOutput Boolean indicating whether the amount specified is
     * the exact output amount (true).
     * @param tickLimit The furthest tick a swap will execute in. If no limit
     * is desired, value should be set to type(int32).max for a tokenAIn swap
     * and type(int32).min for a swap where tokenB is the input.
     */
    struct SwapParams {
        uint256 amount;
        bool tokenAIn;
        bool exactOutput;
        int32 tickLimit;
    }

    /**
     * @notice Swap tokenA/tokenB assets in the pool.  The swap user has two
     * options for funding their swap.
     * - The user can push the input token amount to the pool before calling
     * the swap function. In order to avoid having the pool call the callback,
     * the user should pass a zero-length `data` bytes object with the swap
     * call.
     * - The user can send the input token amount to the pool when the pool
     * calls the `maverickV2SwapCallback` function on the calling contract.
     * That callback has input parameters that specify the token address of the
     * input token, the input and output amounts, and the bytes data sent to
     * the swap function.
     * @dev  If the users elects to do a callback-based swap, the output
     * assets will be sent before the callback is called, allowing the user to
     * execute flash swaps.  However, the pool does have reentrancy protection,
     * so a swapper will not be able to interact with the same pool again
     * while they are in the callback function.
     * @param recipient The address to receive the output tokens.
     * @param params Parameters containing the details of the swap
     * @param data Bytes information that gets passed to the callback.
     */
    function swap(address recipient, SwapParams calldata params, bytes calldata data)
        external
        returns (uint256 amountIn, uint256 amountOut);

    /**
     * @notice Pool tokenA.  Address of tokenA is such that tokenA < tokenB.
     */
    function tokenA() external view returns (IERC20);

    /**
     * @notice Pool tokenB.
     */
    function tokenB() external view returns (IERC20);

    /**
     * @notice State of the pool.
     * @param reserveA Pool tokenA balanceOf at end of last operation
     * @param reserveB Pool tokenB balanceOf at end of last operation
     * @param lastTwaD8 Value of log time weighted average price at last block.
     * Value is 8-decimal scale and is in the fractional tick domain.  E.g. a
     * value of 12.3e8 indicates the TWAP was 3/10ths of the way into the 12th
     * tick.
     * @param lastLogPriceD8 Value of log price at last block. Value is
     * 8-decimal scale and is in the fractional tick domain.  E.g. a value of
     * 12.3e8 indicates the price was 3/10ths of the way into the 12th tick.
     * @param lastTimestamp Last block.timestamp value in seconds for latest
     * swap transaction.
     * @param activeTick Current tick position that contains the active bins.
     * @param isLocked Pool isLocked, E.g., locked or unlocked; isLocked values
     * defined in Pool.sol.
     * @param binCounter Index of the last bin created.
     * @param protocolFeeRatioD3 Ratio of the swap fee that is kept for the
     * protocol.
     */
    struct State {
        uint128 reserveA;
        uint128 reserveB;
        int64 lastTwaD8;
        int64 lastLogPriceD8;
        uint40 lastTimestamp;
        int32 activeTick;
        bool isLocked;
        uint32 binCounter;
        uint8 protocolFeeRatioD3;
    }

    /**
     * @notice External function to get the state of the pool.
     */
    function getState() external view returns (State memory);
}

interface IMaverickV2SwapCallback {
    function maverickV2SwapCallback(IERC20 tokenIn, uint256 amountIn, uint256 amountOut, bytes calldata data)
        external;
}

abstract contract MaverickV2 is SettlerAbstract {
    using UnsafeMath for uint256;
    using SafeTransferLib for IERC20;

    function _encodeSwapCallback(ISignatureTransfer.PermitTransferFrom memory permit, bytes memory sig)
        internal
        view
        returns (bytes memory result)
    {
        bool isForwarded = _isForwarded();
        assembly ("memory-safe") {
            result := mload(0x40)
            mcopy(add(0x20, result), mload(permit), 0x40)
            mcopy(add(0x60, result), add(0x20, permit), 0x40)
            mstore8(add(0xa0, result), isForwarded)
            let sigLength := mload(sig)
            mcopy(add(0xa1, result), add(0x20, sig), sigLength)
            mstore(result, add(0x81, sigLength))
            mstore(0x40, add(sigLength, add(0xa1, result)))
        }
    }

    function sellToMaverickV2VIP(
        address recipient,
        bytes32 salt,
        bool tokenAIn,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 minBuyAmount
    ) internal returns (uint256 buyAmount) {
        bytes memory swapCallbackData = _encodeSwapCallback(permit, sig);
        address pool = AddressDerivation.deriveDeterministicContract(maverickV2Factory, salt, maverickV2InitHash);
        (, buyAmount) = abi.decode(
            _setOperatorAndCall(
                pool,
                abi.encodeCall(
                    IMaverickV2Pool.swap,
                    (
                        recipient,
                        IMaverickV2Pool.SwapParams({
                            amount: _permitToSellAmount(permit),
                            tokenAIn: tokenAIn,
                            exactOutput: false,
                            // TODO: actually set a tick limit so that we can partial fill
                            tickLimit: tokenAIn ? type(int32).max : type(int32).min
                        }),
                        swapCallbackData
                    )
                ),
                uint32(IMaverickV2SwapCallback.maverickV2SwapCallback.selector),
                _maverickV2Callback
            ),
            (uint256, uint256)
        );
        if (buyAmount < minBuyAmount) {
            IERC20 buyToken = tokenAIn ? IMaverickV2Pool(pool).tokenB() : IMaverickV2Pool(pool).tokenA();
            revert TooMuchSlippage(buyToken, minBuyAmount, buyAmount);
        }
    }

    function sellToMaverickV2(
        address recipient,
        IERC20 sellToken,
        uint256 bps,
        IMaverickV2Pool pool,
        bool tokenAIn,
        uint256 minBuyAmount
    ) internal returns (uint256 buyAmount) {
        uint256 sellAmount;
        if (bps != 0) {
            unchecked {
                // We don't care about phantom overflow here because reserves
                // are limited to 128 bits. Any token balance that would
                // overflow here would also break MaverickV2.
                sellAmount = (sellToken.fastBalanceOf(address(this)) * bps).unsafeDiv(BASIS);
            }
        }
        if (sellAmount == 0) {
            sellAmount = sellToken.fastBalanceOf(address(pool));
            IMaverickV2Pool.State memory poolState = pool.getState();
            unchecked {
                sellAmount -= tokenAIn ? poolState.reserveA : poolState.reserveB;
            }
        } else {
            sellToken.safeTransfer(address(pool), sellAmount);
        }
        (, buyAmount) = pool.swap(
            recipient,
            IMaverickV2Pool.SwapParams({
                amount: sellAmount,
                tokenAIn: tokenAIn,
                exactOutput: false,
                // TODO: actually set a tick limit so that we can partial fill
                tickLimit: tokenAIn ? type(int32).max : type(int32).min
            }),
            new bytes(0)
        );
        if (buyAmount < minBuyAmount) {
            revert TooMuchSlippage(tokenAIn ? pool.tokenB() : pool.tokenA(), minBuyAmount, buyAmount);
        }
    }

    function _maverickV2Callback(bytes calldata data) private returns (bytes memory) {
        require(data.length >= 0xa0);
        IERC20 tokenIn;
        uint256 amountIn;
        assembly ("memory-safe") {
            // we don't bother checking for dirty bits because we trust the
            // initcode (by its hash) to produce well-behaved bytecode that
            // produces strict ABI-encoded calldata
            tokenIn := calldataload(data.offset)
            amountIn := calldataload(add(0x20, data.offset))
            // likewise, we don't bother to perform the indirection to find the
            // nested data. we just index directly to it because we know that
            // the pool follows strict ABI encoding
            data.length := calldataload(add(0x80, data.offset))
            data.offset := add(0xa0, data.offset)
        }
        maverickV2SwapCallback(
            tokenIn,
            amountIn,
            // forgefmt: disable-next-line
            0 /* we didn't bother loading `amountOut` because we don't use it */,
            data
        );
        return new bytes(0);
    }

    // forgefmt: disable-next-line
    function maverickV2SwapCallback(IERC20 tokenIn, uint256 amountIn, uint256 /* amountOut */, bytes calldata data)
        private
    {
        ISignatureTransfer.PermitTransferFrom calldata permit;
        bool isForwarded;
        assembly ("memory-safe") {
            permit := data.offset
            isForwarded := and(0x01, calldataload(add(0x61, data.offset)))
            data.offset := add(0x81, data.offset)
            data.length := sub(data.length, 0x81)
        }
        assert(tokenIn == IERC20(permit.permitted.token));
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: msg.sender, requestedAmount: amountIn});
        _transferFrom(permit, transferDetails, data, isForwarded);
    }
}

// src/core/UniswapV3Fork.sol

interface IUniswapV3Pool {
    /// @notice Swap token0 for token1, or token1 for token0
    /// @dev The caller of this method receives a callback in the form of IUniswapV3SwapCallback#uniswapV3SwapCallback
    /// @param recipient The address to receive the output of the swap
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param amountSpecified The amount of the swap, which implicitly configures the swap as exact input (positive),
    /// or exact output (negative)
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @param data Any data to be passed through to the callback
    /// @return amount0 The delta of the balance of token0 of the pool, exact when negative, minimum when positive
    /// @return amount1 The delta of the balance of token1 of the pool, exact when negative, minimum when positive
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

abstract contract UniswapV3Fork is SettlerAbstract {
    using UnsafeMath for uint256;
    using UnsafeMath for int256;
    using SafeTransferLib for IERC20;

    /// @dev Minimum size of an encoded swap path:
    ///      sizeof(address(inputToken) | uint8(forkId) | uint24(poolId) | address(outputToken))
    uint256 private constant SINGLE_HOP_PATH_SIZE = 0x2c;
    /// @dev How many bytes to skip ahead in an encoded path to start at the next hop:
    ///      sizeof(address(inputToken) | uint8(forkId) | uint24(poolId))
    uint256 private constant PATH_SKIP_HOP_SIZE = 0x18;
    /// @dev The size of the swap callback prefix data before the Permit2 data.
    uint256 private constant SWAP_CALLBACK_PREFIX_DATA_SIZE = 0x28;
    /// @dev The offset from the pointer to the length of the swap callback prefix data to the start of the Permit2 data.
    uint256 private constant SWAP_CALLBACK_PERMIT2DATA_OFFSET = 0x48;
    uint256 private constant PERMIT_DATA_SIZE = 0x60;
    uint256 private constant ISFORWARDED_DATA_SIZE = 0x01;
    /// @dev Minimum tick price sqrt ratio.
    uint160 private constant MIN_PRICE_SQRT_RATIO = 4295128739;
    /// @dev Minimum tick price sqrt ratio.
    uint160 private constant MAX_PRICE_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    /// @dev Mask of lower 20 bytes.
    uint256 private constant ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;
    /// @dev Mask of lower 3 bytes.
    uint256 private constant UINT24_MASK = 0xffffff;

    /// @dev Sell a token for another token directly against uniswap v3.
    /// @param encodedPath Uniswap-encoded path.
    /// @param bps proportion of current balance of the first token in the path to sell.
    /// @param minBuyAmount Minimum amount of the last token in the path to buy.
    /// @param recipient The recipient of the bought tokens.
    /// @return buyAmount Amount of the last token in the path bought.
    function sellToUniswapV3(address recipient, uint256 bps, bytes memory encodedPath, uint256 minBuyAmount)
        internal
        returns (uint256 buyAmount)
    {
        buyAmount = _uniV3ForkSwap(
            recipient,
            encodedPath,
            // We don't care about phantom overflow here because reserves are
            // limited to 128 bits. Any token balance that would overflow here
            // would also break UniV3.
            (IERC20(address(bytes20(encodedPath))).fastBalanceOf(address(this)) * bps).unsafeDiv(BASIS),
            minBuyAmount,
            address(this), // payer
            new bytes(SWAP_CALLBACK_PREFIX_DATA_SIZE)
        );
    }

    /// @dev Sell a token for another token directly against uniswap v3. Payment is using a Permit2 signature (or AllowanceHolder).
    /// @param encodedPath Uniswap-encoded path.
    /// @param minBuyAmount Minimum amount of the last token in the path to buy.
    /// @param recipient The recipient of the bought tokens.
    /// @param permit The PermitTransferFrom allowing this contract to spend the taker's tokens
    /// @param sig The taker's signature for Permit2
    /// @return buyAmount Amount of the last token in the path bought.
    function sellToUniswapV3VIP(
        address recipient,
        bytes memory encodedPath,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 minBuyAmount
    ) internal returns (uint256 buyAmount) {
        bytes memory swapCallbackData =
            new bytes(SWAP_CALLBACK_PREFIX_DATA_SIZE + PERMIT_DATA_SIZE + ISFORWARDED_DATA_SIZE + sig.length);
        _encodePermit2Data(swapCallbackData, permit, sig, _isForwarded());

        buyAmount = _uniV3ForkSwap(
            recipient,
            encodedPath,
            _permitToSellAmount(permit),
            minBuyAmount,
            address(0), // payer
            swapCallbackData
        );
    }

    // Executes successive swaps along an encoded uniswap path.
    function _uniV3ForkSwap(
        address recipient,
        bytes memory encodedPath,
        uint256 sellAmount,
        uint256 minBuyAmount,
        address payer,
        bytes memory swapCallbackData
    ) internal returns (uint256 buyAmount) {
        if (sellAmount > uint256(type(int256).max)) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }

        IERC20 outputToken;
        while (true) {
            bool isPathMultiHop = _isPathMultiHop(encodedPath);
            bool zeroForOne;
            IUniswapV3Pool pool;
            uint32 callbackSelector;
            {
                (IERC20 token0, uint8 forkId, uint24 poolId, IERC20 token1) = _decodeFirstPoolInfoFromPath(encodedPath);
                IERC20 sellToken = token0;
                outputToken = token1;
                if (!(zeroForOne = token0 < token1)) {
                    (token0, token1) = (token1, token0);
                }
                address factory;
                bytes32 initHash;
                (factory, initHash, callbackSelector) = _uniV3ForkInfo(forkId);
                pool = _toPool(factory, initHash, token0, token1, poolId);
                _updateSwapCallbackData(swapCallbackData, sellToken, payer);
            }

            int256 amount0;
            int256 amount1;
            if (isPathMultiHop) {
                uint256 freeMemPtr;
                assembly ("memory-safe") {
                    freeMemPtr := mload(0x40)
                }
                (amount0, amount1) = abi.decode(
                    _setOperatorAndCall(
                        address(pool),
                        abi.encodeCall(
                            pool.swap,
                            (
                                // Intermediate tokens go to this contract.
                                address(this),
                                zeroForOne,
                                int256(sellAmount),
                                zeroForOne ? MIN_PRICE_SQRT_RATIO + 1 : MAX_PRICE_SQRT_RATIO - 1,
                                swapCallbackData
                            )
                        ),
                        callbackSelector,
                        _uniV3ForkCallback
                    ),
                    (int256, int256)
                );
                assembly ("memory-safe") {
                    mstore(0x40, freeMemPtr)
                }
            } else {
                (amount0, amount1) = abi.decode(
                    _setOperatorAndCall(
                        address(pool),
                        abi.encodeCall(
                            pool.swap,
                            (
                                recipient,
                                zeroForOne,
                                int256(sellAmount),
                                zeroForOne ? MIN_PRICE_SQRT_RATIO + 1 : MAX_PRICE_SQRT_RATIO - 1,
                                swapCallbackData
                            )
                        ),
                        callbackSelector,
                        _uniV3ForkCallback
                    ),
                    (int256, int256)
                );
            }

            {
                int256 _buyAmount = (zeroForOne ? amount1 : amount0).unsafeNeg();
                if (_buyAmount < 0) {
                    Panic.panic(Panic.ARITHMETIC_OVERFLOW);
                }
                buyAmount = uint256(_buyAmount);
            }
            if (!isPathMultiHop) {
                // Done.
                break;
            }
            // Continue with next hop.
            payer = address(this); // Subsequent hops are paid for by us.
            sellAmount = buyAmount;
            // Skip to next hop along path.
            encodedPath = _shiftHopFromPathInPlace(encodedPath);
            assembly ("memory-safe") {
                mstore(swapCallbackData, SWAP_CALLBACK_PREFIX_DATA_SIZE)
            }
        }
        if (buyAmount < minBuyAmount) {
            revert TooMuchSlippage(outputToken, minBuyAmount, buyAmount);
        }
    }

    // Return whether or not an encoded uniswap path contains more than one hop.
    function _isPathMultiHop(bytes memory encodedPath) private pure returns (bool) {
        return encodedPath.length > SINGLE_HOP_PATH_SIZE;
    }

    function _decodeFirstPoolInfoFromPath(bytes memory encodedPath)
        private
        pure
        returns (IERC20 inputToken, uint8 forkId, uint24 poolId, IERC20 outputToken)
    {
        if (encodedPath.length < SINGLE_HOP_PATH_SIZE) {
            Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
        }
        assembly ("memory-safe") {
            // Solidity cleans dirty bits automatically
            inputToken := mload(add(encodedPath, 0x14))
            forkId := mload(add(encodedPath, 0x15))
            poolId := mload(add(encodedPath, 0x18))
            outputToken := mload(add(encodedPath, SINGLE_HOP_PATH_SIZE))
        }
    }

    // Skip past the first hop of an encoded uniswap path in-place.
    function _shiftHopFromPathInPlace(bytes memory encodedPath) private pure returns (bytes memory) {
        if (encodedPath.length < PATH_SKIP_HOP_SIZE) {
            Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
        }
        assembly ("memory-safe") {
            let length := sub(mload(encodedPath), PATH_SKIP_HOP_SIZE)
            encodedPath := add(encodedPath, PATH_SKIP_HOP_SIZE)
            mstore(encodedPath, length)
        }
        return encodedPath;
    }

    function _encodePermit2Data(
        bytes memory swapCallbackData,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        bool isForwarded
    ) private pure {
        assembly ("memory-safe") {
            mstore(add(SWAP_CALLBACK_PERMIT2DATA_OFFSET, swapCallbackData), mload(add(0x20, mload(permit))))
            mcopy(add(add(SWAP_CALLBACK_PERMIT2DATA_OFFSET, 0x20), swapCallbackData), add(0x20, permit), 0x40)
            mstore8(add(add(SWAP_CALLBACK_PERMIT2DATA_OFFSET, PERMIT_DATA_SIZE), swapCallbackData), isForwarded)
            mcopy(
                add(
                    add(add(SWAP_CALLBACK_PERMIT2DATA_OFFSET, PERMIT_DATA_SIZE), ISFORWARDED_DATA_SIZE),
                    swapCallbackData
                ),
                add(0x20, sig),
                mload(sig)
            )
        }
    }

    // Update `swapCallbackData` in place with new values.
    function _updateSwapCallbackData(bytes memory swapCallbackData, IERC20 sellToken, address payer) private pure {
        assembly ("memory-safe") {
            let length := mload(swapCallbackData)
            mstore(add(0x28, swapCallbackData), sellToken)
            mstore(add(0x14, swapCallbackData), payer)
            mstore(swapCallbackData, length)
        }
    }

    // Compute the pool address given two tokens and a poolId.
    function _toPool(address factory, bytes32 initHash, IERC20 token0, IERC20 token1, uint24 poolId)
        private
        pure
        returns (IUniswapV3Pool)
    {
        // address(keccak256(abi.encodePacked(
        //     hex"ff",
        //     factory,
        //     keccak256(abi.encode(token0, token1, poolId)),
        //     initHash
        // )))
        bytes32 salt;
        assembly ("memory-safe") {
            token0 := and(ADDRESS_MASK, token0)
            token1 := and(ADDRESS_MASK, token1)
            poolId := and(UINT24_MASK, poolId)
            let ptr := mload(0x40)
            mstore(0x00, token0)
            mstore(0x20, token1)
            mstore(0x40, poolId)
            salt := keccak256(0x00, sub(0x60, shl(0x05, iszero(poolId))))
            mstore(0x40, ptr)
        }
        return IUniswapV3Pool(AddressDerivation.deriveDeterministicContract(factory, salt, initHash));
    }

    function _uniV3ForkInfo(uint8 forkId) internal view virtual returns (address, bytes32, uint32);

    function _uniV3ForkCallback(bytes calldata data) private returns (bytes memory) {
        require(data.length >= 0x80);
        int256 amount0Delta;
        int256 amount1Delta;
        assembly ("memory-safe") {
            amount0Delta := calldataload(data.offset)
            amount1Delta := calldataload(add(0x20, data.offset))
            data.offset := add(data.offset, calldataload(add(0x40, data.offset)))
            data.length := calldataload(data.offset)
            data.offset := add(0x20, data.offset)
        }
        uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
        return new bytes(0);
    }

    /// @dev The UniswapV3 pool swap callback which pays the funds requested
    ///      by the caller/pool to the pool. Can only be called by a valid
    ///      UniswapV3 pool.
    /// @param amount0Delta Token0 amount owed.
    /// @param amount1Delta Token1 amount owed.
    /// @param data Arbitrary data forwarded from swap() caller. A packed encoding of: payer, sellToken, (optionally: permit[0x20:], isForwarded, sig)
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) private {
        address payer;
        assembly ("memory-safe") {
            payer := shr(0x60, calldataload(data.offset))
            data.length := sub(data.length, 0x14)
            data.offset := add(0x14, data.offset)
            // We don't check for underflow/array-out-of-bounds here because the trusted inithash
            // ensures that `data` was passed unmodified from `_updateSwapCallbackData`. Therefore,
            // it is at least 40 bytes long.
        }
        uint256 sellAmount = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        _pay(payer, sellAmount, data);
    }

    function _pay(address payer, uint256 amount, bytes calldata permit2Data) private {
        if (payer == address(this)) {
            IERC20 token;
            assembly ("memory-safe") {
                token := shr(0x60, calldataload(permit2Data.offset))
            }
            token.safeTransfer(msg.sender, amount);
        } else {
            assert(payer == address(0));
            ISignatureTransfer.PermitTransferFrom calldata permit;
            bool isForwarded;
            bytes calldata sig;
            assembly ("memory-safe") {
                // this is super dirty, but it works because although `permit` is aliasing in the
                // middle of `payer`, because `payer` is all zeroes, it's treated as padding for the
                // first word of `permit`, which is the sell token
                permit := sub(permit2Data.offset, 0x0c)
                isForwarded := and(0x01, calldataload(add(0x55, permit2Data.offset)))
                sig.offset := add(0x75, permit2Data.offset)
                sig.length := sub(permit2Data.length, 0x75)
            }
            ISignatureTransfer.SignatureTransferDetails memory transferDetails =
                ISignatureTransfer.SignatureTransferDetails({to: msg.sender, requestedAmount: amount});
            _transferFrom(permit, transferDetails, sig, isForwarded);
        }
    }
}

// src/core/Velodrome.sol

//import {Panic} from "../utils/Panic.sol";

interface IVelodromePair {
    function metadata()
        external
        view
        returns (
            uint256 basis0,
            uint256 basis1,
            uint256 reserve0,
            uint256 reserve1,
            bool stable,
            IERC20 token0,
            IERC20 token1
        );
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

abstract contract Velodrome is SettlerAbstract {
    using Math_0 for uint256;
    using Math_0 for bool;
    using UnsafeMath for uint256;
    using FullMath for uint256;
    using SafeTransferLib for IERC20;

    // This is the basis used for token balances. The original token may have fewer decimals, in
    // which case we scale up by the appropriate factor to give this basis.
    uint256 internal constant _VELODROME_TOKEN_BASIS = 1 ether;

    // When computing `k`, to minimize rounding error, we use a significantly larger basis. This
    // also allows us to save work in the Newton-Raphson step because dividing a quantity with this
    // basis by a quantity with `_VELODROME_TOKEN_BASIS` basis gives that same
    // `_VELODROME_TOKEN_BASIS` basis. Convenient *and* accurate.
    uint256 private constant _VELODROME_INTERNAL_BASIS = _VELODROME_TOKEN_BASIS * _VELODROME_TOKEN_BASIS;

    uint256 private constant _VELODROME_INTERNAL_TO_TOKEN_RATIO = _VELODROME_INTERNAL_BASIS / _VELODROME_TOKEN_BASIS;

    // When computing `d` we need to compute the cube of a token quantity and format the result with
    // `_VELODROME_TOKEN_BASIS`. In order to avoid overflow, we must divide the squared token
    // quantity by this before multiplying again by the token quantity. Setting this value as small
    // as possible preserves precision. This gives a result in an awkward basis, but we'll correct
    // that with `_VELODROME_CUBE_STEP_BASIS` after the cubing
    uint256 private constant _VELODROME_SQUARE_STEP_BASIS = 216840435;

    // After squaring a token quantity (in `_VELODROME_TOKEN_BASIS`), we need to multiply again by a
    // token quantity and then divide out the awkward basis to get back to
    // `_VELODROME_TOKEN_BASIS`. This constant is what gets us back to the original token quantity
    // basis. `_VELODROME_TOKEN_BASIS * _VELODROME_TOKEN_BASIS / _VELODROME_SQUARE_STEP_BASIS *
    // _VELODROME_TOKEN_BASIS / _VELODROME_CUBE_STEP_BASIS == _VELODROME_TOKEN_BASIS`
    uint256 private constant _VELODROME_CUBE_STEP_BASIS = 4611686007731906643703237360;

    // The maximum balance in the AMM's reference implementation of `k` is `b` such that `(b * b) /
    // 1 ether * ((b * b) / 1 ether + (b * b) / 1 ether)` does not overflow. This that quantity,
    // `b`. This is roughly 15.5 billion ether.
    uint256 internal constant _VELODROME_MAX_BALANCE = 15511800964685064948225197537;

    // This is the `k = x^3 * y + y^3 * x` constant function. Unlike the original formulation, the
    // result has a basis of `_VELODROME_INTERNAL_BASIS` instead of `_VELODROME_TOKEN_BASIS`
    function _k(uint256 x, uint256 y) private pure returns (uint256) {
        unchecked {
            return _k(x, y, x * x);
        }
    }

    function _k(uint256 x, uint256 y, uint256 x_squared) private pure returns (uint256) {
        unchecked {
            return _k(x, y, x_squared, y * y);
        }
    }

    function _k(uint256 x, uint256 y, uint256 x_squared, uint256 y_squared) private pure returns (uint256) {
        unchecked {
            return (x * y).unsafeMulDivAlt(x_squared + y_squared, _VELODROME_INTERNAL_BASIS);
        }
    }

    function _k_compat(uint256 x, uint256 y) internal pure returns (uint256) {
        unchecked {
            return (x * y).unsafeMulDivAlt(x * x + y * y, _VELODROME_INTERNAL_BASIS * _VELODROME_TOKEN_BASIS);
        }
    }

    function _k_compat(uint256 x, uint256 y, uint256 x_squared) private pure returns (uint256) {
        unchecked {
            return (x * y).unsafeMulDivAlt(x_squared + y * y, _VELODROME_INTERNAL_BASIS * _VELODROME_TOKEN_BASIS);
        }
    }

    // For numerically approximating a solution to the `k = x^3 * y + y^3 * x` constant function
    // using Newton-Raphson, this is `∂k/∂y = 3 * x * y^2 + x^3`. The result has a basis of
    // `_VELODROME_TOKEN_BASIS`.
    function _d(uint256 y, uint256 x) private pure returns (uint256) {
        unchecked {
            return _d(y, 3 * x, x * x / _VELODROME_SQUARE_STEP_BASIS * x);
        }
    }

    function _d(uint256 y, uint256 three_x, uint256 x_cubed) private pure returns (uint256) {
        unchecked {
            return _d(y, three_x, x_cubed, y * y / _VELODROME_SQUARE_STEP_BASIS);
        }
    }

    function _d(uint256, uint256 three_x, uint256 x_cubed, uint256 y_squared) private pure returns (uint256) {
        unchecked {
            return (y_squared * three_x + x_cubed) / _VELODROME_CUBE_STEP_BASIS;
        }
    }

    // Using Newton-Raphson iterations, compute the smallest `new_y` such that `_k(x + dx, new_y) >=
    // _k(x, y)`. As a function of `new_y`, we find the root of `_k(x + dx, new_y) - _k(x, y)`.
    function _get_y(uint256 x, uint256 dx, uint256 y) internal pure returns (uint256) {
        unchecked {
            uint256 k_orig = _k(x, y);
            // `k_orig` has a basis much greater than is actually required for correctness. To
            // achieve wei-level accuracy, we perform our final comparisons agains `k_target`
            // instead, which has the same precision as the AMM itself.
            uint256 k_target = _k_compat(x, y);

            // Now that we have `k` computed, we offset `x` to account for the sell amount and use
            // the constant-product formula to compute an initial estimate for `y`.
            x += dx;
            y -= (dx * y).unsafeDiv(x);

            // These intermediate values do not change throughout the Newton-Raphson iterations, so
            // precomputing and caching them saves us gas.
            uint256 three_x = 3 * x;
            uint256 x_squared_raw = x * x;
            uint256 x_cubed_raw = x_squared_raw / _VELODROME_SQUARE_STEP_BASIS * x;

            for (uint256 i; i < 255; i++) {
                uint256 y_squared_raw = y * y;
                uint256 k = _k(x, y, x_squared_raw, y_squared_raw);
                uint256 d = _d(y, three_x, x_cubed_raw, y_squared_raw / _VELODROME_SQUARE_STEP_BASIS);

                // This would exactly solve *OUR* formulation of the `k=x^3*y+y^3*x` constant
                // function. However, not only is it computationally and contract-size expensive, it
                // also does not necessarily exactly satisfy the *REFERENCE* implementations of the
                // same constant function (SolidlyV1, VelodromeV2). Therefore, it is commented out
                // and the relevant condition is handled by the "ordinary" parts of the
                // Newton-Raphson loop.
                /* if (k / _VELODROME_INTERNAL_TO_TOKEN_RATIO == k_target) {
                    uint256 hi = y;
                    uint256 lo = y - 1;
                    uint256 k_next = _k_compat(x, lo, x_squared_raw);
                    while (k_next == k_target) {
                        (hi, lo) = (lo, lo - (hi - lo) * 2);
                        k_next = _k_compat(x, lo, x_squared_raw);
                    }
                    while (hi != lo) {
                        uint256 mid = (hi - lo) / 2 + lo;
                        k_next = _k_compat(x, mid, x_squared_raw);
                        if (k_next == k_target) {
                            hi = mid;
                        } else {
                            lo = mid + 1;
                        }
                    }
                    return lo;
                } else */ if (k < k_orig) {
                    uint256 dy = (k_orig - k).unsafeDiv(d);
                    // There are two cases where `dy == 0`
                    // Case 1: The `y` is converged and we find the correct answer
                    // Case 2: `_d(y, x)` is too large compare to `(k_orig - k)` and the rounding
                    //         error screwed us.
                    //         In this case, we need to increase `y` by 1
                    if (dy == 0) {
                        if (_k_compat(x, y + 1, x_squared_raw) >= k_target) {
                            // If `_k(x, y + 1) >= k_orig`, then we are close to the correct answer.
                            // There's no closer answer than `y + 1`
                            return y + 1;
                        }
                        // `y + 1` does not give us the condition `k >= k_orig`, so we have to do at
                        // least 1 more iteration to find a satisfactory `y` value. Setting `dy = y
                        // / 2` also solves the problem where the constant-product estimate of `y`
                        // is very bad and convergence is only linear.
                        dy = y / 2;
                    }
                    y += dy;
                    if (y > _VELODROME_MAX_BALANCE) {
                        y = _VELODROME_MAX_BALANCE;
                    }
                } else {
                    uint256 dy = (k - k_orig).unsafeDiv(d);
                    if (dy == 0) {
                        if (_k_compat(x, y - 1, x_squared_raw) < k_target) {
                            // If `_k(x, y - 1) < k_orig`, then we are close to the correct answer.
                            // There's no closer answer than `y`. We need to find `y` where `_k(x,
                            // y) >= k_orig`. As a result, we can't return `y - 1` even it's closer
                            // to the correct answer
                            return y;
                        }
                        if (_k(x, y - 2, x_squared_raw) < k_orig) {
                            // It may be the case that all 3 of `y`, `y - 1`, and `y - 2` give the
                            // same value for `_k_compat`, but that `y - 2` gives a value for `_k`
                            // that brackets `k_orig`. In this case, we would loop forever. This
                            // branch causes us to bail out with the approximately correct value.
                            return y - 1;
                        }
                        // It's possible that `y - 1` is the correct answer. To know that, we must
                        // check that `y - 2` gives `k < k_orig`. We must do at least 1 more
                        // iteration to determine this.
                        dy = 2;
                    }
                    if (dy > y / 2) {
                        dy = y / 2;
                    }
                    y -= dy;
                }
            }
            revert NotConverged();
        }
    }

    function sellToVelodrome(address recipient, uint256 bps, IVelodromePair pair, uint24 swapInfo, uint256 minAmountOut)
        internal
    {
        // Preventing calls to Permit2 or AH is not explicitly required as neither of these contracts implement the `swap` nor `transfer` selector

        // |7|6|5|4|3|2|1|0| - bit positions in swapInfo (uint8)
        // |0|0|0|0|0|0|F|Z| - Z: zeroForOne flag, F: sellTokenHasFee flag
        bool zeroForOne = (swapInfo & 1) == 1; // Extract the least significant bit (bit 0)
        bool sellTokenHasFee = (swapInfo & 2) >> 1 == 1; // Extract the second least significant bit (bit 1) and shift it right
        uint256 feeBps = swapInfo >> 8;

        (
            uint256 sellBasis,
            uint256 buyBasis,
            uint256 sellReserve,
            uint256 buyReserve,
            bool stable,
            IERC20 sellToken,
            IERC20 buyToken
        ) = pair.metadata();
        assert(stable);
        if (!zeroForOne) {
            (sellBasis, buyBasis, sellReserve, buyReserve, sellToken, buyToken) =
                (buyBasis, sellBasis, buyReserve, sellReserve, buyToken, sellToken);
        }

        uint256 buyAmount;
        unchecked {
            // Compute sell amount in native units
            uint256 sellAmount;
            if (bps != 0) {
                // It must be possible to square the sell token balance of the pool, otherwise it
                // will revert with an overflow. Therefore, it can't be so large that multiplying by
                // a "reasonable" `bps` value could overflow. We don't care to protect against
                // unreasonable `bps` values because that just means the taker is griefing themself.
                sellAmount = (sellToken.fastBalanceOf(address(this)) * bps).unsafeDiv(BASIS);
            }
            if (sellAmount != 0) {
                sellToken.safeTransfer(address(pair), sellAmount);
            }
            if (sellAmount == 0 || sellTokenHasFee) {
                sellAmount = sellToken.fastBalanceOf(address(pair)) - sellReserve;
            }

            // Convert reserves from native units to `_VELODROME_TOKEN_BASIS`
            sellReserve = (sellReserve * _VELODROME_TOKEN_BASIS).unsafeDiv(sellBasis);
            buyReserve = (buyReserve * _VELODROME_TOKEN_BASIS).unsafeDiv(buyBasis);

            // This check is commented because values that are too large will
            // result in reverts inside the pool anyways. We don't need to
            // bother.
            /*
            // Check for overflow
            if (buyReserve > _VELODROME_MAX_BALANCE) {
                Panic.panic(Panic.ARITHMETIC_OVERFLOW);
            }
            if (sellReserve + (sellAmount * _VELODROME_TOKEN_BASIS).unsafeDiv(sellBasis) > _VELODROME_MAX_BALANCE) {
                Panic.panic(Panic.ARITHMETIC_OVERFLOW);
            }
            */

            // Apply the fee in native units
            sellAmount -= sellAmount * feeBps / 10_000; // can't overflow
            // Convert sell amount from native units to `_VELODROME_TOKEN_BASIS`
            sellAmount = (sellAmount * _VELODROME_TOKEN_BASIS).unsafeDiv(sellBasis);

            // Solve the constant function numerically to get `buyAmount` from `sellAmount`
            buyAmount = buyReserve - _get_y(sellReserve, sellAmount, buyReserve);

            // Convert `buyAmount` from `_VELODROME_TOKEN_BASIS` to native units
            buyAmount = buyAmount * buyBasis / _VELODROME_TOKEN_BASIS;
        }

        // Compensate for rounding error in the reference implementation of the constant-function
        buyAmount--;
        buyAmount.dec((sellReserve < sellBasis).or(buyReserve < buyBasis));

        // Check slippage
        if (buyAmount < minAmountOut) {
            revert TooMuchSlippage(sellToken, minAmountOut, buyAmount);
        }

        // Perform the swap
        {
            (uint256 buyAmount0, uint256 buyAmount1) = zeroForOne ? (uint256(0), buyAmount) : (buyAmount, uint256(0));
            pair.swap(buyAmount0, buyAmount1, recipient, new bytes(0));
        }
    }
}

// src/core/Basic.sol

abstract contract Basic is SettlerAbstract {
    using UnsafeMath for uint256;
    using SafeTransferLib for IERC20;
    using FullMath for uint256;
    using Revert for bool;

    /// @dev Sell to a pool with a generic approval, transferFrom interaction.
    /// offset in the calldata is used to update the sellAmount given a proportion of the sellToken balance
    function basicSellToPool(IERC20 sellToken, uint256 bps, address pool, uint256 offset, bytes memory data) internal {
        if (_isRestrictedTarget(pool)) {
            revert ConfusedDeputy();
        }

        bool success;
        bytes memory returnData;
        uint256 value;
        if (sellToken == ETH_ADDRESS) {
            value = (address(this).balance * bps).unsafeDiv(BASIS);
            if (data.length == 0) {
                if (offset != 0) revert InvalidOffset();
                (success, returnData) = payable(pool).call{value: value}("");
                success.maybeRevert(returnData);
                return;
            } else {
                if ((offset += 32) > data.length) {
                    Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
                }
                assembly ("memory-safe") {
                    mstore(add(data, offset), value)
                }
            }
        } else if (address(sellToken) == address(0)) {
            // TODO: check for zero `bps`
            if (offset != 0) revert InvalidOffset();
        } else {
            uint256 amount = sellToken.fastBalanceOf(address(this)).mulDiv(bps, BASIS);
            if ((offset += 32) > data.length) {
                Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
            }
            assembly ("memory-safe") {
                mstore(add(data, offset), amount)
            }
            if (address(sellToken) != pool) {
                sellToken.safeApproveIfBelow(pool, amount);
            }
        }
        (success, returnData) = payable(pool).call{value: value}(data);
        success.maybeRevert(returnData);
        // forbid sending data to EOAs
        if (returnData.length == 0 && pool.code.length == 0) revert InvalidTarget();
    }
}

// src/core/UniswapV4.sol

library CreditDebt {
    using UnsafeMath for int256;

    function asCredit(int256 delta, IERC20 token) internal pure returns (uint256) {
        if (delta < 0) {
            revert DeltaNotPositive(token);
        }
        return uint256(delta);
    }

    function asDebt(int256 delta, IERC20 token) internal pure returns (uint256) {
        if (delta > 0) {
            revert DeltaNotNegative(token);
        }
        return uint256(delta.unsafeNeg());
    }
}

abstract contract UniswapV4 is SettlerAbstract {
    using SafeTransferLib for IERC20;
    using UnsafeMath for uint256;
    using UnsafeMath for int256;
    using CreditDebt for int256;
    using UnsafePoolManager for IPoolManager;
    using NotesLib for NotesLib.Note;
    using NotesLib for NotesLib.Note[];
    using StateLib for StateLib.State;

    constructor() {
        assert(BASIS == Encoder.BASIS);
        assert(BASIS == Decoder.BASIS);
        assert(ETH_ADDRESS == Decoder.ETH_ADDRESS);
    }

    function _POOL_MANAGER() internal view virtual returns (IPoolManager);

    //// These two functions are the entrypoints to this set of actions. Because UniV4 has a
    //// mandatory callback, and the vast majority of the business logic has to be executed inside
    //// the callback, they're pretty minimal. Both end up inside the last function in this file
    //// `unlockCallback`, which is where most of the business logic lives. Primarily, these
    //// functions are concerned with correctly encoding the argument to
    //// `POOL_MANAGER.unlock(...)`. Pay special attention to the `payer` field, which is what
    //// signals to the callback whether we should be spending a coupon.

    //// How to generate `fills` for UniV4:
    ////
    //// Linearize your DAG of fills by doing a topological sort on the tokens involved. In the
    //// topological sort of tokens, when there is a choice of the next token, break ties by
    //// preferring a token if it is the lexicographically largest token that is bought among fills
    //// with sell token equal to the previous token in the topological sort. Then sort the fills
    //// belonging to each sell token by their buy token. This technique isn't *quite* optimal, but
    //// it's pretty close. The buy token of the final fill is special-cased. It is the token that
    //// will be transferred to `recipient` and have its slippage checked against `amountOutMin`. In
    //// the event that you are encoding a series of fills with more than one output token, ensure
    //// that at least one of the global buy token's fills is positioned appropriately.
    ////
    //// Now that you have a list of fills, encode each fill as follows.
    //// First encode the `bps` for the fill as 2 bytes. Remember that this `bps` is relative to the
    //// running balance at the moment that the fill is settled.
    //// Second, encode the packing key for that fill as 1 byte. The packing key byte depends on the
    //// tokens involved in the previous fill. The packing key for the first fill must be 1;
    //// i.e. encode only the buy token for the first fill.
    ////   0 -> sell and buy tokens remain unchanged from the previous fill (pure multiplex)
    ////   1 -> sell token remains unchanged from the previous fill, buy token is encoded (diamond multiplex)
    ////   2 -> sell token becomes the buy token from the previous fill, new buy token is encoded (multihop)
    ////   3 -> both sell and buy token are encoded
    //// Obviously, after encoding the packing key, you encode 0, 1, or 2 tokens (each as 20 bytes),
    //// as appropriate.
    //// The remaining fields of the fill are mandatory.
    //// Third, encode the pool fee as 3 bytes, and the pool tick spacing as 3 bytes.
    //// Fourth, encode the hook address as 20 bytes.
    //// Fifth, encode the hook data for the fill. Encode the length of the hook data as 3 bytes,
    //// then append the hook data itself.
    ////
    //// Repeat the process for each fill and concatenate the results without padding.

    function sellToUniswapV4(
        address recipient,
        IERC20 sellToken,
        uint256 bps,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        uint256 amountOutMin
    ) internal returns (uint256 buyAmount) {
        bytes memory data = Encoder.encode(
            uint32(IPoolManager.unlock.selector),
            recipient,
            sellToken,
            bps,
            feeOnTransfer,
            hashMul,
            hashMod,
            fills,
            amountOutMin
        );
        bytes memory encodedBuyAmount = _setOperatorAndCall(
            address(_POOL_MANAGER()), data, uint32(IUnlockCallback.unlockCallback.selector), _uniV4Callback
        );
        // buyAmount = abi.decode(abi.decode(encodedBuyAmount, (bytes)), (uint256));
        assembly ("memory-safe") {
            // We can skip all the checks performed by `abi.decode` because we know that this is the
            // verbatim result from `unlockCallback` and that `unlockCallback` encoded the buy
            // amount correctly.
            buyAmount := mload(add(0x60, encodedBuyAmount))
        }
    }

    function sellToUniswapV4VIP(
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 amountOutMin
    ) internal returns (uint256 buyAmount) {
        bytes memory data = Encoder.encodeVIP(
            uint32(IPoolManager.unlock.selector),
            recipient,
            feeOnTransfer,
            hashMul,
            hashMod,
            fills,
            permit,
            sig,
            _isForwarded(),
            amountOutMin
        );
        bytes memory encodedBuyAmount = _setOperatorAndCall(
            address(_POOL_MANAGER()), data, uint32(IUnlockCallback.unlockCallback.selector), _uniV4Callback
        );
        // buyAmount = abi.decode(abi.decode(encodedBuyAmount, (bytes)), (uint256));
        assembly ("memory-safe") {
            // We can skip all the checks performed by `abi.decode` because we know that this is the
            // verbatim result from `unlockCallback` and that `unlockCallback` encoded the buy
            // amount correctly.
            buyAmount := mload(add(0x60, encodedBuyAmount))
        }
    }

    function _uniV4Callback(bytes calldata data) private returns (bytes memory) {
        // We know that our calldata is well-formed. Therefore, the first slot is 0x20 and the
        // second slot is the length of the strict ABIEncoded payload
        assembly ("memory-safe") {
            data.length := calldataload(add(0x20, data.offset))
            data.offset := add(0x40, data.offset)
        }
        return unlockCallback(data);
    }

    //// The following functions are the helper functions for `unlockCallback`. They abstract much
    //// of the complexity of tracking which tokens need to be zeroed out at the end of the
    //// callback.
    ////
    //// The two major pieces of state that are maintained through the callback are `Note[] memory
    //// notes` and `State memory state`
    ////
    //// `notes` keeps track of the list of the tokens that have been touched throughout the
    //// callback that have nonzero credit. At the end of the fills, all tokens with credit will be
    //// swept back to Settler. These are the global buy token (against which slippage is checked)
    //// and any other multiplex-out tokens. Only the global sell token is allowed to have debt, but
    //// it is accounted slightly differently from the other tokens. The function `_take` is
    //// responsible for iterating over the list of tokens and withdrawing any credit to the
    //// appropriate recipient.
    ////
    //// `state` exists to reduce stack pressure and to simplify/gas-optimize the process of
    //// swapping. By keeping track of the sell and buy token on each hop, we're able to compress
    //// the representation of the fills required to satisfy the swap. Most often in a swap, the
    //// tokens in adjacent fills are somewhat in common. By caching, we avoid having them appear
    //// multiple times in the calldata.

    // the mandatory fields are
    // 2 - sell bps
    // 1 - pool key tokens case
    // 3 - pool fee
    // 3 - pool tick spacing
    // 20 - pool hooks
    // 3 - hook data length
    uint256 private constant _HOP_DATA_LENGTH = 32;

    uint256 private constant _ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

    /// Decode a `PoolKey` from its packed representation in `bytes` and the token information in
    /// `state`. Returns the `zeroForOne` flag and the suffix of the bytes that are not consumed in
    /// the decoding process.
    function _setPoolKey(IPoolManager.PoolKey memory key, StateLib.State memory state, bytes calldata data)
        private
        pure
        returns (bool, bytes calldata)
    {
        (IERC20 sellToken, IERC20 buyToken) = (state.sell.token, state.buy.token);
        bool zeroForOne;
        assembly ("memory-safe") {
            sellToken := and(_ADDRESS_MASK, sellToken)
            buyToken := and(_ADDRESS_MASK, buyToken)
            zeroForOne :=
                or(
                    eq(sellToken, 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee),
                    and(iszero(eq(buyToken, 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee)), lt(sellToken, buyToken))
                )
        }
        (key.token0, key.token1) = zeroForOne ? (sellToken, buyToken) : (buyToken, sellToken);

        uint256 packed;
        assembly ("memory-safe") {
            packed := shr(0x30, calldataload(data.offset))

            data.offset := add(0x1a, data.offset)
            data.length := sub(data.length, 0x1a)
            // we don't check for array out-of-bounds here; we will check it later in `Decoder.overflowCheck`
        }

        key.fee = uint24(packed >> 184);
        key.tickSpacing = int24(uint24(packed >> 160));
        key.hooks = IHooks.wrap(address(uint160(packed)));

        return (zeroForOne, data);
    }

    function _pay(
        IERC20 sellToken,
        address payer,
        uint256 sellAmount,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bool isForwarded,
        bytes calldata sig
    ) private returns (uint256) {
        IPoolManager(msg.sender).unsafeSync(sellToken);
        if (payer == address(this)) {
            sellToken.safeTransfer(msg.sender, sellAmount);
        } else {
            // assert(payer == address(0));
            ISignatureTransfer.SignatureTransferDetails memory transferDetails =
                ISignatureTransfer.SignatureTransferDetails({to: msg.sender, requestedAmount: sellAmount});
            _transferFrom(permit, transferDetails, sig, isForwarded);
        }
        return IPoolManager(msg.sender).unsafeSettle();
    }

    function unlockCallback(bytes calldata data) private returns (bytes memory) {
        address recipient;
        uint256 minBuyAmount;
        uint256 hashMul;
        uint256 hashMod;
        bool feeOnTransfer;
        address payer;
        (data, recipient, minBuyAmount, hashMul, hashMod, feeOnTransfer, payer) = Decoder.decodeHeader(data);

        // Set up `state` and `notes`. The other values are ancillary and might be used when we need
        // to settle global sell token debt at the end of swapping.
        (
            bytes calldata newData,
            StateLib.State memory state,
            NotesLib.Note[] memory notes,
            ISignatureTransfer.PermitTransferFrom calldata permit,
            bool isForwarded,
            bytes calldata sig
        ) = Decoder.initialize(data, hashMul, hashMod, payer);
        if (payer != address(this)) {
            state.globalSell.amount = _permitToSellAmountCalldata(permit);
        }
        if (feeOnTransfer) {
            state.globalSell.amount =
                _pay(state.globalSell.token, payer, state.globalSell.amount, permit, isForwarded, sig);
        }
        if (state.globalSell.amount == 0) {
            revert ZeroSellAmount(state.globalSell.token);
        }
        state.globalSellAmount = state.globalSell.amount;
        data = newData;

        // Now that we've unpacked and decoded the header, we can begin decoding the array of swaps
        // and executing them.
        IPoolManager.PoolKey memory key;
        IPoolManager.SwapParams memory params;
        while (data.length >= _HOP_DATA_LENGTH) {
            uint16 bps;
            assembly ("memory-safe") {
                bps := shr(0xf0, calldataload(data.offset))

                data.offset := add(0x02, data.offset)
                data.length := sub(data.length, 0x02)
                // we don't check for array out-of-bounds here; we will check it later in `Decoder.overflowCheck`
            }

            data = Decoder.updateState(state, notes, data);
            bool zeroForOne;
            (zeroForOne, data) = _setPoolKey(key, state, data);
            bytes calldata hookData;
            (data, hookData) = Decoder.decodeBytes(data);
            Decoder.overflowCheck(data);

            params.zeroForOne = zeroForOne;
            unchecked {
                params.amountSpecified = int256((state.sell.amount * bps).unsafeDiv(BASIS)).unsafeNeg();
            }
            // TODO: price limits
            params.sqrtPriceLimitX96 = zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341;

            BalanceDelta delta = IPoolManager(msg.sender).unsafeSwap(key, params, hookData);
            {
                (int256 settledSellAmount, int256 settledBuyAmount) =
                    zeroForOne ? (delta.amount0(), delta.amount1()) : (delta.amount1(), delta.amount0());
                // Some insane hooks may increase the sell amount; obviously this may result in
                // unavoidable reverts in some cases. But we still need to make sure that we don't
                // underflow to avoid wildly unexpected behavior. The pool manager enforces that the
                // settled sell amount cannot be positive
                state.sell.amount -= uint256(settledSellAmount.unsafeNeg());
                // If `state.buy.amount()` overflows an `int128`, we'll get a revert inside the pool
                // manager later. We cannot overflow a `uint256`.
                unchecked {
                    state.buy.amount += settledBuyAmount.asCredit(state.buy.token);
                }
            }
        }

        // `data` has been consumed. All that remains is to settle out the net result of all the
        // swaps. Any credit in any token other than `state.buy.token` will be swept to
        // Settler. `state.buy.token` will be sent to `recipient`.
        {
            (IERC20 globalSellToken, uint256 globalSellAmount) = (state.globalSell.token, state.globalSell.amount);
            uint256 globalBuyAmount =
                Take.take(state, notes, uint32(IPoolManager.take.selector), recipient, minBuyAmount);
            if (feeOnTransfer) {
                // We've already transferred the sell token to the pool manager and
                // `settle`'d. `globalSellAmount` is the verbatim credit in that token stored by the
                // pool manager. We only need to handle the case of incomplete filling.
                if (globalSellAmount != 0) {
                    Take._callSelector(
                        uint32(IPoolManager.take.selector),
                        globalSellToken,
                        payer == address(this) ? address(this) : _msgSender(),
                        globalSellAmount
                    );
                }
            } else {
                // While `notes` records a credit value, the pool manager actually records a debt
                // for the global sell token. We recover the exact amount of that debt and then pay
                // it.
                // `globalSellAmount` is _usually_ zero, but if it isn't it represents a partial
                // fill. This subtraction recovers the actual debt recorded in the pool manager.
                uint256 debt;
                unchecked {
                    debt = state.globalSellAmount - globalSellAmount;
                }
                if (debt == 0) {
                    revert ZeroSellAmount(globalSellToken);
                }
                if (globalSellToken == ETH_ADDRESS) {
                    IPoolManager(msg.sender).unsafeSync(IERC20(address(0)));
                    IPoolManager(msg.sender).unsafeSettle(debt);
                } else {
                    _pay(globalSellToken, payer, debt, permit, isForwarded, sig);
                }
            }

            bytes memory returndata;
            assembly ("memory-safe") {
                returndata := mload(0x40)
                mstore(returndata, 0x60)
                mstore(add(0x20, returndata), 0x20)
                mstore(add(0x40, returndata), 0x20)
                mstore(add(0x60, returndata), globalBuyAmount)
                mstore(0x40, add(0x80, returndata))
            }
            return returndata;
        }
    }
}

// src/core/BalancerV3.sol

interface IBalancerV3Vault {
    /**
     * @notice Creates a context for a sequence of operations (i.e., "unlocks" the Vault).
     * @dev Performs a callback on msg.sender with arguments provided in `data`. The Callback is `transient`,
     * meaning all balances for the caller have to be settled at the end.
     *
     * @param data Contains function signature and args to be passed to the msg.sender
     * @return result Resulting data from the call
     */
    function unlock(bytes calldata data) external returns (bytes memory);

    /**
     * @notice Settles deltas for a token; must be successful for the current lock to be released.
     * @dev Protects the caller against leftover dust in the Vault for the token being settled. The caller
     * should know in advance how many tokens were paid to the Vault, so it can provide it as a hint to discard any
     * excess in the Vault balance.
     *
     * If the given hint is equal to or higher than the difference in reserves, the difference in reserves is given as
     * credit to the caller. If it's higher, the caller sent fewer tokens than expected, so settlement would fail.
     *
     * If the given hint is lower than the difference in reserves, the hint is given as credit to the caller.
     * In this case, the excess would be absorbed by the Vault (and reflected correctly in the reserves), but would
     * not affect settlement.
     *
     * The credit supplied by the Vault can be calculated as `min(reserveDifference, amountHint)`, where the reserve
     * difference equals current balance of the token minus existing reserves of the token when the function is called.
     *
     * @param token Address of the token
     * @param amountHint Amount paid as reported by the caller
     * @return credit Credit received in return of the payment
     */
    function settle(IERC20 token, uint256 amountHint) external returns (uint256 credit);

    /**
     * @notice Sends tokens to a recipient.
     * @dev There is no inverse operation for this function. Transfer funds to the Vault and call `settle` to cancel
     * debts.
     *
     * @param token Address of the token
     * @param to Recipient address
     * @param amount Amount of tokens to send
     */
    function sendTo(IERC20 token, address to, uint256 amount) external;

    enum SwapKind {
        EXACT_IN,
        EXACT_OUT
    }

    /**
     * @notice Data passed into primary Vault `swap` operations.
     * @param kind Type of swap (Exact In or Exact Out)
     * @param pool The pool with the tokens being swapped
     * @param tokenIn The token entering the Vault (balance increases)
     * @param tokenOut The token leaving the Vault (balance decreases)
     * @param amountGiven Amount specified for tokenIn or tokenOut (depending on the type of swap)
     * @param limit Minimum or maximum value of the calculated amount (depending on the type of swap)
     * @param userData Additional (optional) user data
     */
    struct VaultSwapParams {
        SwapKind kind;
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        uint256 limit;
        bytes userData;
    }

    /**
     * @notice Swaps tokens based on provided parameters.
     * @dev All parameters are given in raw token decimal encoding.
     * @param vaultSwapParams Parameters for the swap (see above for struct definition)
     * @return amountCalculated Calculated swap amount
     * @return amountIn Amount of input tokens for the swap
     * @return amountOut Amount of output tokens from the swap
     */
    function swap(VaultSwapParams memory vaultSwapParams)
        external
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);

    enum WrappingDirection {
        WRAP,
        UNWRAP
    }

    /**
     * @notice Data for a wrap/unwrap operation.
     * @param kind Type of swap (Exact In or Exact Out)
     * @param direction Direction of the wrapping operation (Wrap or Unwrap)
     * @param wrappedToken Wrapped token, compatible with interface ERC4626
     * @param amountGiven Amount specified for tokenIn or tokenOut (depends on the type of swap and wrapping direction)
     * @param limit Minimum or maximum amount specified for the other token (depends on the type of swap and wrapping
     * direction)
     */
    struct BufferWrapOrUnwrapParams {
        SwapKind kind;
        WrappingDirection direction;
        IERC4626 wrappedToken;
        uint256 amountGiven;
        uint256 limit;
    }

    /**
     * @notice Wraps/unwraps tokens based on the parameters provided.
     * @dev All parameters are given in raw token decimal encoding. It requires the buffer to be initialized,
     * and uses the internal wrapped token buffer when it has enough liquidity to avoid external calls.
     *
     * @param params Parameters for the wrap/unwrap operation (see struct definition)
     * @return amountCalculated Calculated swap amount
     * @return amountIn Amount of input tokens for the swap
     * @return amountOut Amount of output tokens from the swap
     */
    function erc4626BufferWrapOrUnwrap(BufferWrapOrUnwrapParams memory params)
        external
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);
}

library UnsafeVault {
    function unsafeSettle(IBalancerV3Vault vault, IERC20 token, uint256 amount) internal returns (uint256 credit) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)

            mstore(0x00, 0x15afd409) // selector for `settle(address,uint256)`
            mstore(0x20, and(0xffffffffffffffffffffffffffffffffffffffff, token))
            mstore(0x40, amount)

            if iszero(call(gas(), vault, 0x00, 0x1c, 0x44, 0x00, 0x20)) {
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            credit := mload(0x00)

            mstore(0x40, ptr)
        }
    }

    function unsafeSwap(IBalancerV3Vault vault, IBalancerV3Vault.VaultSwapParams memory params)
        internal
        returns (uint256 amountIn, uint256 amountOut)
    {
        assembly ("memory-safe") {
            // `VaultSwapParams` is a dynamic type with exactly 1 sub-object, and that sub-object is
            // dynamic (all the other members are value types). Therefore, the layout in calldata is
            // nearly identical to the layout in memory, but there's an extra indirection offset
            // that needs to be prepended. Also the pointer to `params.userData` needs to be
            // transformed into an offset relative to the start of `params`.
            // We know that it's safe to (temporarily) clobber the two words in memory immediately
            // before `params` because they are user-allocated (they're part of `wrapParams`). If
            // they were not user-allocated, this would be illegal as it could clobber a word that
            // `solc` spilled from the stack into memory.

            let ptr := mload(0x40)
            let clobberedPtr0 := sub(params, 0x40)
            let clobberedVal0 := mload(clobberedPtr0)
            let clobberedPtr1 := sub(params, 0x20)
            let clobberedVal1 := mload(clobberedPtr1)

            mstore(clobberedPtr0, 0x2bfb780c) // selector for `swap((uint8,address,address,address,uint256,uint256,bytes))`
            mstore(clobberedPtr1, 0x20) // indirection offset to the dynamic type `VaultSwapParams`

            // Because we laid out `swapParams` as the last object in memory before
            // `swapParam.userData`, the two objects are contiguous. Their encoding in calldata is
            // exactly the same as their encoding in memory, but with pointers changed to offsets.
            let userDataPtr := add(0xc0, params)
            let userData := mload(userDataPtr)
            let userDataLen := mload(userData)
            // Convert the pointer `userData` into an offset relative to the start of its parent
            // object (`params`), and replace it in memory to transform it to the calldata encoding
            let len := sub(userData, params)
            mstore(userDataPtr, len)
            // Compute the length of the entire encoded object
            len := add(0x20, add(userDataLen, len))
            // The padding is a little wonky (we're not creating the Solidity-strict ABI encoding),
            // but the Solidity ABIDecoder is relaxed enough that this doesn't matter.

            // The length of the whole call's calldata is 36 bytes longer than the encoding of
            // `params` in memory to account for the prepending of the selector (4 bytes) and the
            // indirection offset (32 bytes)
            if iszero(call(gas(), vault, 0x00, add(0x1c, clobberedPtr0), add(0x24, len), 0x00, 0x60)) {
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            amountIn := mload(0x20)
            amountOut := mload(0x40)

            // mstore(userDataPtr, userData) // we don't need this because we're immediately going to deallocate
            mstore(clobberedPtr0, clobberedVal0)
            mstore(clobberedPtr1, clobberedVal1)
            mstore(0x40, ptr)
        }
    }

    function unsafeErc4626BufferWrapOrUnwrap(
        IBalancerV3Vault vault,
        IBalancerV3Vault.BufferWrapOrUnwrapParams memory params
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        assembly ("memory-safe") {
            // `BufferWrapOrUnwrapParams` is a static type and contains no sub-objects (all its
            // members are value types), so the layout in calldata is just the layout in memory,
            // without any indirection.
            // We know that it's safe to (temporarily) clobber the word in memory immediately before
            // `params` because it is user-allocated (it's part of the `Notes` heap). If it were not
            // user-allocated, this would be illegal as it could clobber a word that `solc` spilled
            // from the stack into memory.

            let ptr := mload(0x40)
            let clobberedPtr := sub(params, 0x20)
            let clobberedVal := mload(clobberedPtr)
            mstore(clobberedPtr, 0x43583be5) // selector for `erc4626BufferWrapOrUnwrap((uint8,uint8,address,uint256,uint256))`

            if iszero(call(gas(), vault, 0x00, add(0x1c, clobberedPtr), 0xa4, 0x00, 0x60)) {
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            amountIn := mload(0x20)
            amountOut := mload(0x40)

            mstore(clobberedPtr, clobberedVal)
            mstore(0x40, ptr)
        }
    }
}

IBalancerV3Vault constant VAULT = IBalancerV3Vault(0xbA1333333333a1BA1108E8412f11850A5C319bA9);

abstract contract BalancerV3 is SettlerAbstract, FreeMemory {
    using SafeTransferLib for IERC20;
    using UnsafeMath for uint256;
    using NotesLib for NotesLib.Note;
    using NotesLib for NotesLib.Note[];
    using StateLib for StateLib.State;

    using UnsafeVault for IBalancerV3Vault;

    constructor() {
        assert(BASIS == Encoder.BASIS);
        assert(BASIS == Decoder.BASIS);
        assert(ETH_ADDRESS == Decoder.ETH_ADDRESS);
    }

    //// How to generate `fills` for BalancerV3:
    ////
    //// Linearize your DAG of fills by doing a topological sort on the tokens involved. Swapping
    //// against a boosted pool (usually) creates 3 fills: wrap, swap, unwrap. The tokens involved
    //// includes each ERC4626 tokenized vault token for any boosted pools. In the topological sort
    //// of tokens, when there is a choice of the next token, break ties by preferring a token if it
    //// is the lexicographically largest token that is bought among fills with sell token equal to
    //// the previous token in the topological sort. Then sort the fills belonging to each sell
    //// token by their buy token. This technique isn't *quite* optimal, but it's pretty close. The
    //// buy token of the final fill is special-cased. It is the token that will be transferred to
    //// `recipient` and have its slippage checked against `amountOutMin`. In the event that you are
    //// encoding a series of fills with more than one output token, ensure that at least one of the
    //// global buy token's fills is positioned appropriately.
    ////
    //// Now that you have a list of fills, encode each fill as follows.
    //// First, decide if the fill is a swap or an ERC4626 wrap/unwrap.
    //// Second, encode the `bps` for the fill as 2 bytes. Remember that this `bps` is relative to
    //// the running balance at the moment that the fill is settled. If the fill is a wrap, set the
    //// most significant bit of `bps`. If the fill is an unwrap, set the second most significant
    //// bit of `bps`
    //// Third, encode the packing key for that fill as 1 byte. The packing key byte depends on the
    //// tokens involved in the previous fill. If the fill is a wrap, the buy token must be the
    //// ERC4626 vault. If the fill is an unwrap, the sell token must be the ERC4626 vault. If the
    //// fill is a swap against a boosted pool, both sell and buy tokens must be ERC4626 vaults. God
    //// help you if you're dealing with a boosted pool where only some of the tokens involved are
    //// ERC4626. The packing key for the first fill must be 1; i.e. encode only the buy token for
    //// the first fill.
    ////   0 -> sell and buy tokens remain unchanged from the previous fill (pure multiplex)
    ////   1 -> sell token remains unchanged from the previous fill, buy token is encoded (diamond multiplex)
    ////   2 -> sell token becomes the buy token from the previous fill, new buy token is encoded (multihop)
    ////   3 -> both sell and buy token are encoded
    //// Obviously, after encoding the packing key, you encode 0, 1, or 2 tokens (each as 20 bytes),
    //// as appropriate.
    //// If the fill is a wrap/unwrap, you're done. Move on to the next fill. If the fill is a swap,
    //// the following fields are mandatory:
    //// Fourth, encode the pool address as 20 bytes.
    //// Fifth, encode the hook data for the fill. Encode the length of the hook data as 3 bytes,
    //// then append the hook data itself.
    ////
    //// Repeat the process for each fill and concatenate the results without padding.

    function sellToBalancerV3(
        address recipient,
        IERC20 sellToken,
        uint256 bps,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        uint256 amountOutMin
    ) internal returns (uint256 buyAmount) {
        if (bps > BASIS) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        bytes memory data = Encoder.encode(
            uint32(IBalancerV3Vault.unlock.selector),
            recipient,
            sellToken,
            bps,
            feeOnTransfer,
            hashMul,
            hashMod,
            fills,
            amountOutMin
        );
        // If, for some insane reason, the first 4 bytes of `recipient` alias the selector for the
        // only mutative function of Settler (`execute` or `executeMetaTxn`, as appropriate), then
        // this call will revert. We will encounter a revert in the nested call to
        // `execute`/`executeMetaTxn` because Settler is reentrancy-locked (this revert is
        // bubbled). If, instead, it aliases a non-mutative function of Settler, we would encounter
        // a revert inside `TransientStorage.checkSpentOperatorAndCallback` because the transient
        // storage slot was not zeroed. This would happen by accident with negligible probability,
        // and is merely annoying if it does happen.
        bytes memory encodedBuyAmount =
            _setOperatorAndCall(address(VAULT), data, uint32(uint256(uint160(recipient)) >> 128), _balV3Callback);
        // buyAmount = abi.decode(abi.decode(encodedBuyAmount, (bytes)), (uint256));
        assembly ("memory-safe") {
            // We can skip all the checks performed by `abi.decode` because we know that this is the
            // verbatim result from `balV3UnlockCallback` and that `balV3UnlockCallback` encoded the
            // buy amount correctly.
            buyAmount := mload(add(0x60, encodedBuyAmount))
        }
    }

    function sellToBalancerV3VIP(
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 amountOutMin
    ) internal returns (uint256 buyAmount) {
        bytes memory data = Encoder.encodeVIP(
            uint32(IBalancerV3Vault.unlock.selector),
            recipient,
            feeOnTransfer,
            hashMul,
            hashMod,
            fills,
            permit,
            sig,
            _isForwarded(),
            amountOutMin
        );
        // See comment in `sellToBalancerV3` about why `recipient` aliasing a valid selector is
        // ultimately harmless.
        bytes memory encodedBuyAmount =
            _setOperatorAndCall(address(VAULT), data, uint32(uint256(uint160(recipient)) >> 128), _balV3Callback);
        // buyAmount = abi.decode(abi.decode(encodedBuyAmount, (bytes)), (uint256));
        assembly ("memory-safe") {
            // We can skip all the checks performed by `abi.decode` because we know that this is the
            // verbatim result from `balV3UnlockCallback` and that `balV3UnlockCallback` encoded the
            // buy amount correctly.
            buyAmount := mload(add(0x60, encodedBuyAmount))
        }
    }

    function _balV3Callback(bytes calldata) private returns (bytes memory) {
        // `VAULT` doesn't prepend a selector and ABIEncode the payload. It just echoes the decoded
        // payload verbatim back to us. Therefore, we use `_msgData()` instead of the argument to
        // this function because `_msgData()` still has the first 4 bytes of the payload attached.
        return balV3UnlockCallback(_msgData());
    }

    function _setSwapParams(
        IBalancerV3Vault.VaultSwapParams memory swapParams,
        StateLib.State memory state,
        bytes calldata data
    ) private pure returns (bytes calldata) {
        assembly ("memory-safe") {
            mstore(add(0x20, swapParams), shr(0x60, calldataload(data.offset)))
            data.offset := add(0x14, data.offset)
            data.length := sub(data.length, 0x14)
            // we don't check for array out-of-bounds here; we will check it later in `Decoder.overflowCheck`
        }
        swapParams.tokenIn = state.sell.token;
        swapParams.tokenOut = state.buy.token;
        return data;
    }

    function _decodeUserdataAndSwap(
        IBalancerV3Vault.VaultSwapParams memory swapParams,
        StateLib.State memory state,
        bytes calldata data
    ) private DANGEROUS_freeMemory returns (bytes calldata) {
        (data, swapParams.userData) = Decoder.decodeBytes(data);
        Decoder.overflowCheck(data);

        (uint256 amountIn, uint256 amountOut) = IBalancerV3Vault(msg.sender).unsafeSwap(swapParams);
        unchecked {
            // `amountIn` is always exactly `swapParams.amountGiven`
            state.sell.amount -= amountIn;
        }
        // `amountOut` can never get super close to `type(uint256).max` because `VAULT` does its
        // internal calculations in fixnum with a basis of `1 ether`, giving us a headroom of ~60
        // bits. However, `state.buy.amount` may be an agglomeration of values returned by ERC4626
        // vaults, and there is no implicit restriction on those values.
        state.buy.amount += amountOut;
        assembly ("memory-safe") {
            mstore(add(0xc0, swapParams), 0x60)
        }

        return data;
    }

    function _erc4626WrapUnwrap(
        IBalancerV3Vault.BufferWrapOrUnwrapParams memory wrapParams,
        StateLib.State memory state
    ) private {
        (uint256 amountIn, uint256 amountOut) = IBalancerV3Vault(msg.sender).unsafeErc4626BufferWrapOrUnwrap(wrapParams);
        unchecked {
            // `amountIn` is always exactly `wrapParams.amountGiven`
            state.sell.amount -= amountIn;
        }
        // `amountOut` may depend on the behavior of the ERC4626 vault. We can make no assumptions
        // about the reasonableness of the range of values that may be returned.
        state.buy.amount += amountOut;
    }

    function _balV3Pay(
        IERC20 sellToken,
        address payer,
        uint256 sellAmount,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bool isForwarded,
        bytes calldata sig
    ) private returns (uint256) {
        if (payer == address(this)) {
            sellToken.safeTransfer(msg.sender, sellAmount);
        } else {
            // assert(payer == address(0));
            ISignatureTransfer.SignatureTransferDetails memory transferDetails =
                ISignatureTransfer.SignatureTransferDetails({to: msg.sender, requestedAmount: sellAmount});
            _transferFrom(permit, transferDetails, sig, isForwarded);
        }
        return IBalancerV3Vault(msg.sender).unsafeSettle(sellToken, sellAmount);
    }

    // the mandatory fields are
    // 2 - sell bps
    // 1 - pool key tokens case
    uint256 private constant _HOP_DATA_LENGTH = 3;

    function balV3UnlockCallback(bytes calldata data) private returns (bytes memory) {
        address recipient;
        uint256 minBuyAmount;
        uint256 hashMul;
        uint256 hashMod;
        bool feeOnTransfer;
        address payer;
        (data, recipient, minBuyAmount, hashMul, hashMod, feeOnTransfer, payer) = Decoder.decodeHeader(data);

        // Set up `state` and `notes`. The other values are ancillary and might be used when we need
        // to settle global sell token debt at the end of swapping.
        (
            bytes calldata newData,
            StateLib.State memory state,
            NotesLib.Note[] memory notes,
            ISignatureTransfer.PermitTransferFrom calldata permit,
            bool isForwarded,
            bytes calldata sig
        ) = Decoder.initialize(data, hashMul, hashMod, payer);
        if (payer != address(this)) {
            state.globalSell.amount = _permitToSellAmountCalldata(permit);
        }
        if (feeOnTransfer) {
            state.globalSell.amount =
                _balV3Pay(state.globalSell.token, payer, state.globalSell.amount, permit, isForwarded, sig);
        }
        if (state.globalSell.amount == 0) {
            revert ZeroSellAmount(state.globalSell.token);
        }
        state.globalSellAmount = state.globalSell.amount;
        data = newData;

        IBalancerV3Vault.BufferWrapOrUnwrapParams memory wrapParams;
        /*
        wrapParams.kind = IBalancerV3Vault.SwapKind.EXACT_IN;
        wrapParams.limit = 0; // TODO: price limits for partial filling
        */

        // We position `swapParams` at the end of allocated memory so that when we `calldatacopy`
        // the `userData`, it ends up contiguous
        IBalancerV3Vault.VaultSwapParams memory swapParams;
        /*
        swapParams.kind = IBalancerV3Vault.SwapKind.EXACT_IN;
        swapParams.limit = 0; // TODO: price limits for partial filling
        */

        while (data.length >= _HOP_DATA_LENGTH) {
            uint16 bps;
            assembly ("memory-safe") {
                bps := shr(0xf0, calldataload(data.offset))

                data.offset := add(0x02, data.offset)
                data.length := sub(data.length, 0x02)
                // we don't check for array out-of-bounds here; we will check it later in `Decoder.overflowCheck`
            }

            data = Decoder.updateState(state, notes, data);

            if (bps & 0xc000 == 0) {
                data = _setSwapParams(swapParams, state, data);
                unchecked {
                    swapParams.amountGiven = (state.sell.amount * bps).unsafeDiv(BASIS);
                }
                data = _decodeUserdataAndSwap(swapParams, state, data);
            } else {
                Decoder.overflowCheck(data);

                if (bps & 0x4000 == 0) {
                    wrapParams.direction = IBalancerV3Vault.WrappingDirection.WRAP;
                    wrapParams.wrappedToken = IERC4626(address(state.buy.token));
                } else {
                    wrapParams.direction = IBalancerV3Vault.WrappingDirection.UNWRAP;
                    wrapParams.wrappedToken = IERC4626(address(state.sell.token));
                }
                bps &= 0x3fff;
                unchecked {
                    wrapParams.amountGiven = (state.sell.amount * bps).unsafeDiv(BASIS);
                }

                _erc4626WrapUnwrap(wrapParams, state);
            }
        }

        // `data` has been consumed. All that remains is to settle out the net result of all the
        // swaps. Any credit in any token other than `state.buy.token` will be swept to
        // Settler. `state.buy.token` will be sent to `recipient`.
        {
            (IERC20 globalSellToken, uint256 globalSellAmount) = (state.globalSell.token, state.globalSell.amount);
            uint256 globalBuyAmount =
                Take.take(state, notes, uint32(IBalancerV3Vault.sendTo.selector), recipient, minBuyAmount);
            if (feeOnTransfer) {
                // We've already transferred the sell token to the vault and
                // `settle`'d. `globalSellAmount` is the verbatim credit in that token stored by the
                // vault. We only need to handle the case of incomplete filling.
                if (globalSellAmount != 0) {
                    Take._callSelector(
                        uint32(IBalancerV3Vault.sendTo.selector),
                        globalSellToken,
                        payer == address(this) ? address(this) : _msgSender(),
                        globalSellAmount
                    );
                }
            } else {
                // While `notes` records a credit value, the vault actually records a debt for the
                // global sell token. We recover the exact amount of that debt and then pay it.
                // `globalSellAmount` is _usually_ zero, but if it isn't it represents a partial
                // fill. This subtraction recovers the actual debt recorded in the vault.
                uint256 debt;
                unchecked {
                    debt = state.globalSellAmount - globalSellAmount;
                }
                if (debt == 0) {
                    revert ZeroSellAmount(globalSellToken);
                }
                _balV3Pay(globalSellToken, payer, debt, permit, isForwarded, sig);
            }

            bytes memory returndata;
            assembly ("memory-safe") {
                returndata := mload(0x40)
                mstore(returndata, 0x60)
                mstore(add(0x20, returndata), 0x20)
                mstore(add(0x40, returndata), 0x20)
                mstore(add(0x60, returndata), globalBuyAmount)
                mstore(0x40, add(0x80, returndata))
            }
            return returndata;
        }
    }
}

// src/core/Permit2Payment.sol

library TransientStorage {
    // bytes32((uint256(keccak256("operator slot")) - 1) & type(uint128).max)
    bytes32 private constant _OPERATOR_SLOT = 0x0000000000000000000000000000000007f49fa1cdccd5c65a7d4860ce3abbe9;
    // bytes32((uint256(keccak256("witness slot")) - 1) & type(uint128).max)
    bytes32 private constant _WITNESS_SLOT = 0x00000000000000000000000000000000e44a235ac7aebfbc05485e093720deaa;
    // bytes32((uint256(keccak256("payer slot")) - 1) & type(uint128).max)
    bytes32 private constant _PAYER_SLOT = 0x00000000000000000000000000000000c824a45acd1e9517bb0cb8d0d5cde893;

    // We assume (and our CI enforces) that internal function pointers cannot be
    // greater than 2 bytes. On chains not supporting the ViaIR pipeline, not
    // supporting EOF, and where the Spurious Dragon size limit is not enforced,
    // it might be possible to violate this assumption. However, our
    // `foundry.toml` enforces the use of the IR pipeline, so the point is moot.
    //
    // `operator` must not be `address(0)`. This is not checked.
    // `callback` must not be zero. This is checked in `_invokeCallback`.
    function setOperatorAndCallback(
        address operator,
        uint32 selector,
        function (bytes calldata) internal returns (bytes memory) callback
    ) internal {
        address currentSigner;
        assembly ("memory-safe") {
            currentSigner := tload(_PAYER_SLOT)
        }
        if (operator == currentSigner) {
            revert ConfusedDeputy();
        }
        uint256 callbackInt;
        assembly ("memory-safe") {
            callbackInt := tload(_OPERATOR_SLOT)
        }
        if (callbackInt != 0) {
            // It should be impossible to reach this error because the first thing the fallback does
            // is clear the operator. It's also not possible to reenter the entrypoint function
            // because `_PAYER_SLOT` is an implicit reentrancy guard.
            revert ReentrantCallback(callbackInt);
        }
        assembly ("memory-safe") {
            tstore(
                _OPERATOR_SLOT,
                or(
                    shl(0xe0, selector),
                    or(shl(0xa0, and(0xffff, callback)), and(0xffffffffffffffffffffffffffffffffffffffff, operator))
                )
            )
        }
    }

    function checkSpentOperatorAndCallback() internal view {
        uint256 callbackInt;
        assembly ("memory-safe") {
            callbackInt := tload(_OPERATOR_SLOT)
        }
        if (callbackInt != 0) {
            revert CallbackNotSpent(callbackInt);
        }
    }

    function getAndClearOperatorAndCallback()
        internal
        returns (bytes4 selector, function (bytes calldata) internal returns (bytes memory) callback, address operator)
    {
        assembly ("memory-safe") {
            selector := tload(_OPERATOR_SLOT)
            callback := and(0xffff, shr(0xa0, selector))
            operator := selector
            tstore(_OPERATOR_SLOT, 0x00)
        }
    }

    // `newWitness` must not be `bytes32(0)`. This is not checked.
    function setWitness(bytes32 newWitness) internal {
        bytes32 currentWitness;
        assembly ("memory-safe") {
            currentWitness := tload(_WITNESS_SLOT)
        }
        if (currentWitness != bytes32(0)) {
            // It should be impossible to reach this error because the first thing a metatransaction
            // does on entry is to spend the `witness` (either directly or via a callback)
            revert ReentrantMetatransaction(currentWitness);
        }
        assembly ("memory-safe") {
            tstore(_WITNESS_SLOT, newWitness)
        }
    }

    function checkSpentWitness() internal view {
        bytes32 currentWitness;
        assembly ("memory-safe") {
            currentWitness := tload(_WITNESS_SLOT)
        }
        if (currentWitness != bytes32(0)) {
            revert WitnessNotSpent(currentWitness);
        }
    }

    function getAndClearWitness() internal returns (bytes32 witness) {
        assembly ("memory-safe") {
            witness := tload(_WITNESS_SLOT)
            tstore(_WITNESS_SLOT, 0x00)
        }
    }

    function setPayer(address payer) internal {
        if (payer == address(0)) {
            revert ConfusedDeputy();
        }
        address oldPayer;
        assembly ("memory-safe") {
            oldPayer := tload(_PAYER_SLOT)
        }
        if (oldPayer != address(0)) {
            revert ReentrantPayer(oldPayer);
        }
        assembly ("memory-safe") {
            tstore(_PAYER_SLOT, and(0xffffffffffffffffffffffffffffffffffffffff, payer))
        }
    }

    function getPayer() internal view returns (address payer) {
        assembly ("memory-safe") {
            payer := tload(_PAYER_SLOT)
        }
    }

    function clearPayer(address expectedOldPayer) internal {
        address oldPayer;
        assembly ("memory-safe") {
            oldPayer := tload(_PAYER_SLOT)
        }
        if (oldPayer != expectedOldPayer) {
            revert PayerSpent();
        }
        assembly ("memory-safe") {
            tstore(_PAYER_SLOT, 0x00)
        }
    }
}

abstract contract Permit2PaymentBase is SettlerAbstract {
    using Revert for bool;

    /// @dev Permit2 address
    ISignatureTransfer internal constant _PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    function _isRestrictedTarget(address target) internal pure virtual override returns (bool) {
        return target == address(_PERMIT2);
    }

    function _msgSender() internal view virtual override returns (address) {
        return TransientStorage.getPayer();
    }

    /// @dev You must ensure that `target` is derived by hashing trusted initcode or another
    ///      equivalent mechanism that guarantees "reasonable"ness. `target` must not be
    ///      user-supplied or attacker-controlled. This is required for security and is not checked
    ///      here. For example, it must not do something weird like modifying the spender (possibly
    ///      setting it to itself). If the callback is expected to relay a
    ///      `ISignatureTransfer.PermitTransferFrom` struct, then the computation of `target` using
    ///      the trusted initcode (or equivalent) must ensure that that calldata is relayed
    ///      unmodified. The library function `AddressDerivation.deriveDeterministicContract` is
    ///      recommended.
    function _setOperatorAndCall(
        address payable target,
        uint256 value,
        bytes memory data,
        uint32 selector,
        function (bytes calldata) internal returns (bytes memory) callback
    ) internal returns (bytes memory) {
        TransientStorage.setOperatorAndCallback(target, selector, callback);
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        success.maybeRevert(returndata);
        TransientStorage.checkSpentOperatorAndCallback();
        return returndata;
    }

    function _setOperatorAndCall(
        address target,
        bytes memory data,
        uint32 selector,
        function (bytes calldata) internal returns (bytes memory) callback
    ) internal override returns (bytes memory) {
        return _setOperatorAndCall(payable(target), 0, data, selector, callback);
    }

    function _invokeCallback(bytes calldata data) internal returns (bytes memory) {
        // Retrieve callback and perform call with untrusted calldata
        (bytes4 selector, function (bytes calldata) internal returns (bytes memory) callback, address operator) =
            TransientStorage.getAndClearOperatorAndCallback();
        require(bytes4(data) == selector);
        require(msg.sender == operator);
        return callback(data[4:]);
    }
}

abstract contract Permit2Payment is Permit2PaymentBase {
    fallback(bytes calldata) external virtual returns (bytes memory) {
        return _invokeCallback(_msgData());
    }

    function _permitToTransferDetails(ISignatureTransfer.PermitTransferFrom memory permit, address recipient)
        internal
        view
        override
        returns (ISignatureTransfer.SignatureTransferDetails memory transferDetails, uint256 sellAmount)
    {
        transferDetails.to = recipient;
        transferDetails.requestedAmount = sellAmount = _permitToSellAmount(permit);
    }

    // This function is provided *EXCLUSIVELY* for use here and in RfqOrderSettlement. Any other use
    // of this function is forbidden. You must use the version that does *NOT* take a `from` or
    // `witness` argument.
    function _transferFromIKnowWhatImDoing(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        address from,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory sig,
        bool isForwarded
    ) internal override {
        if (isForwarded) revert ForwarderNotAllowed();
        _PERMIT2.permitWitnessTransferFrom(permit, transferDetails, from, witness, witnessTypeString, sig);
    }

    // See comment in above overload; don't use this function
    function _transferFromIKnowWhatImDoing(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        address from,
        bytes32 witness,
        string memory witnessTypeString,
        bytes memory sig
    ) internal override {
        _transferFromIKnowWhatImDoing(permit, transferDetails, from, witness, witnessTypeString, sig, _isForwarded());
    }

    function _transferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        bytes memory sig
    ) internal override {
        _transferFrom(permit, transferDetails, sig, _isForwarded());
    }
}

abstract contract Permit2PaymentTakerSubmitted is AllowanceHolderContext, Permit2Payment {
    using FullMath for uint256;
    using SafeTransferLib for IERC20;

    constructor() {
        assert(!_hasMetaTxn());
    }

    function _permitToSellAmountCalldata(ISignatureTransfer.PermitTransferFrom calldata permit)
        internal
        view
        override
        returns (uint256 sellAmount)
    {
        sellAmount = permit.permitted.amount;
        if (sellAmount > type(uint256).max - BASIS) {
            unchecked {
                sellAmount -= type(uint256).max - BASIS;
            }
            sellAmount = IERC20(permit.permitted.token).fastBalanceOf(_msgSender()).mulDiv(sellAmount, BASIS);
        }
    }

    function _permitToSellAmount(ISignatureTransfer.PermitTransferFrom memory permit)
        internal
        view
        override
        returns (uint256 sellAmount)
    {
        sellAmount = permit.permitted.amount;
        if (sellAmount > type(uint256).max - BASIS) {
            unchecked {
                sellAmount -= type(uint256).max - BASIS;
            }
            sellAmount = IERC20(permit.permitted.token).fastBalanceOf(_msgSender()).mulDiv(sellAmount, BASIS);
        }
    }

    function _isRestrictedTarget(address target) internal pure virtual override returns (bool) {
        return target == address(_ALLOWANCE_HOLDER) || super._isRestrictedTarget(target);
    }

    function _operator() internal view override returns (address) {
        return AllowanceHolderContext._msgSender();
    }

    function _msgSender()
        internal
        view
        virtual
        override(Permit2PaymentBase, AllowanceHolderContext)
        returns (address)
    {
        return Permit2PaymentBase._msgSender();
    }

    function _transferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        bytes memory sig,
        bool isForwarded
    ) internal override {
        if (isForwarded) {
            if (sig.length != 0) revert InvalidSignatureLen();
            if (permit.nonce != 0) Panic.panic(Panic.ARITHMETIC_OVERFLOW);
            if (block.timestamp > permit.deadline) revert SignatureExpired(permit.deadline);
            // we don't check `requestedAmount` because it's checked by AllowanceHolder itself
            _allowanceHolderTransferFrom(
                permit.permitted.token, _msgSender(), transferDetails.to, transferDetails.requestedAmount
            );
        } else {
            _PERMIT2.permitTransferFrom(permit, transferDetails, _msgSender(), sig);
        }
    }

    function _allowanceHolderTransferFrom(address token, address owner, address recipient, uint256 amount)
        internal
        override
    {
        // `owner` is always `_msgSender()`
        _ALLOWANCE_HOLDER.transferFrom(token, owner, recipient, amount);
    }

    modifier takerSubmitted() override {
        address msgSender = _operator();
        TransientStorage.setPayer(msgSender);
        _;
        TransientStorage.clearPayer(msgSender);
    }

    modifier metaTx(address, bytes32) override {
        revert();
        _;
    }
}

abstract contract Permit2PaymentMetaTxn is Context, Permit2Payment {
    constructor() {
        assert(_hasMetaTxn());
    }

    function _permitToSellAmountCalldata(ISignatureTransfer.PermitTransferFrom calldata permit)
        internal
        pure
        override
        returns (uint256)
    {
        return permit.permitted.amount;
    }

    function _permitToSellAmount(ISignatureTransfer.PermitTransferFrom memory permit)
        internal
        pure
        override
        returns (uint256)
    {
        return permit.permitted.amount;
    }

    function _operator() internal view override returns (address) {
        return Context._msgSender();
    }

    function _msgSender() internal view virtual override(Permit2PaymentBase, Context) returns (address) {
        return Permit2PaymentBase._msgSender();
    }

    // `string.concat` isn't recognized by solc as compile-time constant, but `abi.encodePacked` is
    // This is defined here as `private` and not in `SettlerAbstract` as `internal` because no other
    // contract/file should reference it. The *ONLY* approved way to make a transfer using this
    // witness string is by setting the witness with modifier `metaTx`
    string private constant _SLIPPAGE_AND_ACTIONS_WITNESS = string(
        abi.encodePacked("SlippageAndActions slippageAndActions)", SLIPPAGE_AND_ACTIONS_TYPE, TOKEN_PERMISSIONS_TYPE)
    );

    function _transferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails memory transferDetails,
        bytes memory sig,
        bool isForwarded // must be false
    ) internal override {
        bytes32 witness = TransientStorage.getAndClearWitness();
        if (witness == bytes32(0)) {
            revert ConfusedDeputy();
        }
        _transferFromIKnowWhatImDoing(
            permit, transferDetails, _msgSender(), witness, _SLIPPAGE_AND_ACTIONS_WITNESS, sig, isForwarded
        );
    }

    function _allowanceHolderTransferFrom(address, address, address, uint256) internal pure override {
        revert ConfusedDeputy();
    }

    modifier takerSubmitted() override {
        revert();
        _;
    }

    modifier metaTx(address msgSender, bytes32 witness) override {
        if (_isForwarded()) {
            revert ForwarderNotAllowed();
        }
        TransientStorage.setWitness(witness);
        TransientStorage.setPayer(msgSender);
        _;
        TransientStorage.clearPayer(msgSender);
        // It should not be possible for this check to revert because the very first thing that a
        // metatransaction does is spend the witness.
        TransientStorage.checkSpentWitness();
    }
}

// src/SettlerBase.sol

/// @dev This library's ABIDeocding is more lax than the Solidity ABIDecoder. This library omits index bounds/overflow
/// checking when accessing calldata arrays for gas efficiency. It also omits checks against `calldatasize()`. This
/// means that it is possible that `args` will run off the end of calldata and be implicitly padded with zeroes. That we
/// don't check for overflow means that offsets can be negative. This can also result in `args` that alias other parts
/// of calldata, or even the `actions` array itself.
library CalldataDecoder {
    function decodeCall(bytes[] calldata data, uint256 i)
        internal
        pure
        returns (uint256 selector, bytes calldata args)
    {
        assembly ("memory-safe") {
            // initially, we set `args.offset` to the pointer to the length. this is 32 bytes before the actual start of data
            args.offset :=
                add(
                    data.offset,
                    // We allow the indirection/offset to `calls[i]` to be negative
                    calldataload(
                        add(shl(5, i), data.offset) // can't overflow; we assume `i` is in-bounds
                    )
                )
            // now we load `args.length` and set `args.offset` to the start of data
            args.length := calldataload(args.offset)
            args.offset := add(args.offset, 0x20)

            // slice off the first 4 bytes of `args` as the selector
            selector := shr(0xe0, calldataload(args.offset))
            args.length := sub(args.length, 0x04)
            args.offset := add(args.offset, 0x04)
        }
    }
}

abstract contract SettlerBase is Basic, RfqOrderSettlement, UniswapV3Fork, UniswapV2, Velodrome {
    using SafeTransferLib for IERC20;
    using SafeTransferLib for address payable;

    receive() external payable {}

    event GitCommit(bytes20 indexed);

    constructor(bytes20 gitCommit, uint256 tokenId) {
        if (block.chainid != 31337) {
            emit GitCommit(gitCommit);
            assert(IERC721Owner(DEPLOYER).ownerOf(tokenId) == address(this));
        } else {
            assert(gitCommit == bytes20(0));
        }
    }

    function _div512to256(uint512 n, uint512 d) internal view virtual override returns (uint256) {
        return n.div(d);
    }

    struct AllowedSlippage {
        address recipient;
        IERC20 buyToken;
        uint256 minAmountOut;
    }

    function _checkSlippageAndTransfer(AllowedSlippage calldata slippage) internal {
        // This final slippage check effectively prohibits custody optimization on the
        // final hop of every swap. This is gas-inefficient. This is on purpose. Because
        // ISettlerActions.BASIC could interact with an intents-based settlement
        // mechanism, we must ensure that the user's want token increase is coming
        // directly from us instead of from some other form of exchange of value.
        (address recipient, IERC20 buyToken, uint256 minAmountOut) =
            (slippage.recipient, slippage.buyToken, slippage.minAmountOut);
        if (minAmountOut != 0 || address(buyToken) != address(0)) {
            if (buyToken == ETH_ADDRESS) {
                uint256 amountOut = address(this).balance;
                if (amountOut < minAmountOut) {
                    revert TooMuchSlippage(buyToken, minAmountOut, amountOut);
                }
                payable(recipient).safeTransferETH(amountOut);
            } else {
                uint256 amountOut = buyToken.fastBalanceOf(address(this));
                if (amountOut < minAmountOut) {
                    revert TooMuchSlippage(buyToken, minAmountOut, amountOut);
                }
                buyToken.safeTransfer(recipient, amountOut);
            }
        }
    }

    function _dispatch(uint256, uint256 action, bytes calldata data) internal virtual override returns (bool) {
        if (action == uint32(ISettlerActions.RFQ.selector)) {
            (
                address recipient,
                ISignatureTransfer.PermitTransferFrom memory permit,
                address maker,
                bytes memory makerSig,
                IERC20 takerToken,
                uint256 maxTakerAmount
            ) = abi.decode(data, (address, ISignatureTransfer.PermitTransferFrom, address, bytes, IERC20, uint256));

            fillRfqOrderSelfFunded(recipient, permit, maker, makerSig, takerToken, maxTakerAmount);
        } else if (action == uint32(ISettlerActions.UNISWAPV3.selector)) {
            (address recipient, uint256 bps, bytes memory path, uint256 amountOutMin) =
                abi.decode(data, (address, uint256, bytes, uint256));

            sellToUniswapV3(recipient, bps, path, amountOutMin);
        } else if (action == uint32(ISettlerActions.UNISWAPV2.selector)) {
            (address recipient, address sellToken, uint256 bps, address pool, uint24 swapInfo, uint256 amountOutMin) =
                abi.decode(data, (address, address, uint256, address, uint24, uint256));

            sellToUniswapV2(recipient, sellToken, bps, pool, swapInfo, amountOutMin);
        } else if (action == uint32(ISettlerActions.BASIC.selector)) {
            (IERC20 sellToken, uint256 bps, address pool, uint256 offset, bytes memory _data) =
                abi.decode(data, (IERC20, uint256, address, uint256, bytes));

            basicSellToPool(sellToken, bps, pool, offset, _data);
        } else if (action == uint32(ISettlerActions.VELODROME.selector)) {
            (address recipient, uint256 bps, IVelodromePair pool, uint24 swapInfo, uint256 minAmountOut) =
                abi.decode(data, (address, uint256, IVelodromePair, uint24, uint256));

            sellToVelodrome(recipient, bps, pool, swapInfo, minAmountOut);
        } else if (action == uint32(ISettlerActions.POSITIVE_SLIPPAGE.selector)) {
            (address recipient, IERC20 token, uint256 expectedAmount) = abi.decode(data, (address, IERC20, uint256));
            if (token == ETH_ADDRESS) {
                uint256 balance = address(this).balance;
                if (balance > expectedAmount) {
                    unchecked {
                        payable(recipient).safeTransferETH(balance - expectedAmount);
                    }
                }
            } else {
                uint256 balance = token.fastBalanceOf(address(this));
                if (balance > expectedAmount) {
                    unchecked {
                        token.safeTransfer(recipient, balance - expectedAmount);
                    }
                }
            }
        } else {
            return false;
        }
        return true;
    }
}

// src/Settler.sol

abstract contract Settler is Permit2PaymentTakerSubmitted, SettlerBase {
    using UnsafeMath for uint256;
    using CalldataDecoder for bytes[];

    // When/if you change this, you must make corresponding changes to
    // `sh/deploy_new_chain.sh` and 'sh/common_deploy_settler.sh' to set
    // `constructor_args`.
    constructor(bytes20 gitCommit) SettlerBase(gitCommit, 2) {}

    function _hasMetaTxn() internal pure override returns (bool) {
        return false;
    }

    function _msgSender()
        internal
        view
        virtual
        // Solidity inheritance is so stupid
        override(Permit2PaymentTakerSubmitted, AbstractContext)
        returns (address)
    {
        return super._msgSender();
    }

    function _isRestrictedTarget(address target)
        internal
        pure
        virtual
        // Solidity inheritance is so stupid
        override(Permit2PaymentTakerSubmitted, Permit2PaymentAbstract)
        returns (bool)
    {
        return super._isRestrictedTarget(target);
    }

    function _dispatchVIP(uint256 action, bytes calldata data) internal virtual returns (bool) {
        if (action == uint32(ISettlerActions.TRANSFER_FROM.selector)) {
            (address recipient, ISignatureTransfer.PermitTransferFrom memory permit, bytes memory sig) =
                abi.decode(data, (address, ISignatureTransfer.PermitTransferFrom, bytes));
            (ISignatureTransfer.SignatureTransferDetails memory transferDetails,) =
                _permitToTransferDetails(permit, recipient);
            _transferFrom(permit, transferDetails, sig);
        } else if (action == uint32(ISettlerActions.RFQ_VIP.selector)) {
            (
                address recipient,
                ISignatureTransfer.PermitTransferFrom memory makerPermit,
                address maker,
                bytes memory makerSig,
                ISignatureTransfer.PermitTransferFrom memory takerPermit,
                bytes memory takerSig
            ) = abi.decode(
                data,
                (
                    address,
                    ISignatureTransfer.PermitTransferFrom,
                    address,
                    bytes,
                    ISignatureTransfer.PermitTransferFrom,
                    bytes
                )
            );

            fillRfqOrderVIP(recipient, makerPermit, maker, makerSig, takerPermit, takerSig);
        } else if (action == uint32(ISettlerActions.UNISWAPV3_VIP.selector)) {
            (
                address recipient,
                bytes memory path,
                ISignatureTransfer.PermitTransferFrom memory permit,
                bytes memory sig,
                uint256 amountOutMin
            ) = abi.decode(data, (address, bytes, ISignatureTransfer.PermitTransferFrom, bytes, uint256));

            sellToUniswapV3VIP(recipient, path, permit, sig, amountOutMin);
        } else {
            return false;
        }
        return true;
    }

    function execute(AllowedSlippage calldata slippage, bytes[] calldata actions, bytes32 /* zid & affiliate */ )
        public
        payable
        takerSubmitted
        returns (bool)
    {
        if (actions.length != 0) {
            (uint256 action, bytes calldata data) = actions.decodeCall(0);
            if (!_dispatchVIP(action, data)) {
                if (!_dispatch(0, action, data)) {
                    revert ActionInvalid(0, bytes4(uint32(action)), data);
                }
            }
        }

        for (uint256 i = 1; i < actions.length; i = i.unsafeInc()) {
            (uint256 action, bytes calldata data) = actions.decodeCall(i);
            if (!_dispatch(i, action, data)) {
                revert ActionInvalid(i, bytes4(uint32(action)), data);
            }
        }

        _checkSlippageAndTransfer(slippage);
        return true;
    }
}

// src/chains/Mainnet/Common.sol

// Solidity inheritance is stupid

abstract contract MainnetMixin is
    FreeMemory,
    SettlerBase,
    MakerPSM,
    MaverickV2,
    CurveTricrypto,
    DodoV1,
    DodoV2,
    UniswapV4,
    BalancerV3
{
    constructor() {
        assert(block.chainid == 1 || block.chainid == 31337);
    }

    function _dispatch(uint256 i, uint256 action, bytes calldata data)
        internal
        virtual
        override(SettlerAbstract, SettlerBase)
        DANGEROUS_freeMemory
        returns (bool)
    {
        if (super._dispatch(i, action, data)) {
            return true;
        } else if (action == uint32(ISettlerActions.UNISWAPV4.selector)) {
            (
                address recipient,
                IERC20 sellToken,
                uint256 bps,
                bool feeOnTransfer,
                uint256 hashMul,
                uint256 hashMod,
                bytes memory fills,
                uint256 amountOutMin
            ) = abi.decode(data, (address, IERC20, uint256, bool, uint256, uint256, bytes, uint256));

            sellToUniswapV4(recipient, sellToken, bps, feeOnTransfer, hashMul, hashMod, fills, amountOutMin);
        } else if (action == uint32(ISettlerActions.MAKERPSM.selector)) {
            (address recipient, uint256 bps, bool buyGem, uint256 amountOutMin) =
                abi.decode(data, (address, uint256, bool, uint256));

            sellToMakerPsm(recipient, bps, buyGem, amountOutMin);
        } else if (action == uint32(ISettlerActions.BALANCERV3.selector)) {
            (
                address recipient,
                IERC20 sellToken,
                uint256 bps,
                bool feeOnTransfer,
                uint256 hashMul,
                uint256 hashMod,
                bytes memory fills,
                uint256 amountOutMin
            ) = abi.decode(data, (address, IERC20, uint256, bool, uint256, uint256, bytes, uint256));

            sellToBalancerV3(recipient, sellToken, bps, feeOnTransfer, hashMul, hashMod, fills, amountOutMin);
        } else if (action == uint32(ISettlerActions.MAVERICKV2.selector)) {
            (
                address recipient,
                IERC20 sellToken,
                uint256 bps,
                IMaverickV2Pool pool,
                bool tokenAIn,
                uint256 minBuyAmount
            ) = abi.decode(data, (address, IERC20, uint256, IMaverickV2Pool, bool, uint256));

            sellToMaverickV2(recipient, sellToken, bps, pool, tokenAIn, minBuyAmount);
        } else if (action == uint32(ISettlerActions.DODOV2.selector)) {
            (address recipient, IERC20 sellToken, uint256 bps, IDodoV2 dodo, bool quoteForBase, uint256 minBuyAmount) =
                abi.decode(data, (address, IERC20, uint256, IDodoV2, bool, uint256));

            sellToDodoV2(recipient, sellToken, bps, dodo, quoteForBase, minBuyAmount);
        } else if (action == uint32(ISettlerActions.DODOV1.selector)) {
            (IERC20 sellToken, uint256 bps, IDodoV1 dodo, bool quoteForBase, uint256 minBuyAmount) =
                abi.decode(data, (IERC20, uint256, IDodoV1, bool, uint256));

            sellToDodoV1(sellToken, bps, dodo, quoteForBase, minBuyAmount);
        } else {
            return false;
        }
        return true;
    }

    function _uniV3ForkInfo(uint8 forkId)
        internal
        pure
        override
        returns (address factory, bytes32 initHash, uint32 callbackSelector)
    {
        if (forkId == uniswapV3ForkId) {
            factory = uniswapV3MainnetFactory;
            initHash = uniswapV3InitHash;
            callbackSelector = uint32(IUniswapV3Callback.uniswapV3SwapCallback.selector);
        } else if (forkId == pancakeSwapV3ForkId) {
            factory = pancakeSwapV3Factory;
            initHash = pancakeSwapV3InitHash;
            callbackSelector = uint32(IPancakeSwapV3Callback.pancakeV3SwapCallback.selector);
        } else if (forkId == sushiswapV3ForkId) {
            factory = sushiswapV3MainnetFactory;
            initHash = uniswapV3InitHash;
            callbackSelector = uint32(IUniswapV3Callback.uniswapV3SwapCallback.selector);
        } else if (forkId == solidlyV3ForkId) {
            factory = solidlyV3Factory;
            initHash = solidlyV3InitHash;
            callbackSelector = uint32(ISolidlyV3Callback.solidlyV3SwapCallback.selector);
        } else {
            revert UnknownForkId(forkId);
        }
    }

    function _curveFactory() internal pure override returns (address) {
        return 0x0c0e5f2fF0ff18a3be9b835635039256dC4B4963;
    }

    function _POOL_MANAGER() internal pure override returns (IPoolManager) {
        return MAINNET_POOL_MANAGER;
    }

    function rebateClaimer() external view returns (address) {
        return IOwnable(DEPLOYER).owner();
    }
}

// src/chains/Mainnet/TakerSubmitted.sol

// Solidity inheritance is stupid

/// @custom:security-contact security@0x.org
contract MainnetSettler is Settler, MainnetMixin {
    constructor(bytes20 gitCommit) Settler(gitCommit) {}

    function _dispatchVIP(uint256 action, bytes calldata data) internal override DANGEROUS_freeMemory returns (bool) {
        if (super._dispatchVIP(action, data)) {
            return true;
        } else if (action == uint32(ISettlerActions.UNISWAPV4_VIP.selector)) {
            (
                address recipient,
                bool feeOnTransfer,
                uint256 hashMul,
                uint256 hashMod,
                bytes memory fills,
                ISignatureTransfer.PermitTransferFrom memory permit,
                bytes memory sig,
                uint256 amountOutMin
            ) = abi.decode(
                data, (address, bool, uint256, uint256, bytes, ISignatureTransfer.PermitTransferFrom, bytes, uint256)
            );

            sellToUniswapV4VIP(recipient, feeOnTransfer, hashMul, hashMod, fills, permit, sig, amountOutMin);
        } else if (action == uint32(ISettlerActions.BALANCERV3_VIP.selector)) {
            (
                address recipient,
                bool feeOnTransfer,
                uint256 hashMul,
                uint256 hashMod,
                bytes memory fills,
                ISignatureTransfer.PermitTransferFrom memory permit,
                bytes memory sig,
                uint256 amountOutMin
            ) = abi.decode(
                data, (address, bool, uint256, uint256, bytes, ISignatureTransfer.PermitTransferFrom, bytes, uint256)
            );

            sellToBalancerV3VIP(recipient, feeOnTransfer, hashMul, hashMod, fills, permit, sig, amountOutMin);
        } else if (action == uint32(ISettlerActions.MAVERICKV2_VIP.selector)) {
            (
                address recipient,
                bytes32 salt,
                bool tokenAIn,
                ISignatureTransfer.PermitTransferFrom memory permit,
                bytes memory sig,
                uint256 minBuyAmount
            ) = abi.decode(data, (address, bytes32, bool, ISignatureTransfer.PermitTransferFrom, bytes, uint256));

            sellToMaverickV2VIP(recipient, salt, tokenAIn, permit, sig, minBuyAmount);
        } else if (action == uint32(ISettlerActions.CURVE_TRICRYPTO_VIP.selector)) {
            (
                address recipient,
                uint80 poolInfo,
                ISignatureTransfer.PermitTransferFrom memory permit,
                bytes memory sig,
                uint256 minBuyAmount
            ) = abi.decode(data, (address, uint80, ISignatureTransfer.PermitTransferFrom, bytes, uint256));

            sellToCurveTricryptoVIP(recipient, poolInfo, permit, sig, minBuyAmount);
        } else {
            return false;
        }
        return true;
    }

    // Solidity inheritance is stupid
    function _isRestrictedTarget(address target)
        internal
        pure
        override(Settler, Permit2PaymentAbstract)
        returns (bool)
    {
        return super._isRestrictedTarget(target);
    }

    function _dispatch(uint256 i, uint256 action, bytes calldata data)
        internal
        override(SettlerAbstract, SettlerBase, MainnetMixin)
        returns (bool)
    {
        return super._dispatch(i, action, data);
    }

    function _msgSender() internal view override(Settler, AbstractContext) returns (address) {
        return super._msgSender();
    }
}
