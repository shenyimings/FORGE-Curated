// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMorpho } from "@morpho-blue/interfaces/IMorpho.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import { Admin } from "contracts/base/Admin.sol";
import { ILendingPoolV2 } from
    "contracts/interfaces/external/flashloans/ILendingPoolV2.sol";
import { IPoolV3 } from "contracts/interfaces/external/flashloans/IPoolV3.sol";
import {
    IBalancerVault,
    IFlashLoanRecipient
} from "contracts/interfaces/external/flashloans/IBalancerVault.sol";
import { IUniswapV3Pool } from
    "contracts/interfaces/external/uniswap/IUniswapV3Pool.sol";
import { IUniswapV2Factory } from
    "contracts/interfaces/external/uniswap/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from
    "contracts/interfaces/external/uniswap/IUniswapV2Pair.sol";
import { IUniswapV3Factory } from
    "contracts/interfaces/external/uniswap/IUniswapV3Factory.sol";
import { SickleRegistry } from "contracts/SickleRegistry.sol";
import { SickleFactory } from "contracts/SickleFactory.sol";
import { Multicall } from "contracts/base/Multicall.sol";

library FlashloanStrategyEvents {
    event SelectorLinked(bytes4 selector, address strategy);
}

/// @title FlashloanStrategy contract
/// @author vfat.tools
/// @notice Manages approved flashloan providers for the sickle and calls to and
/// from flashloan providers
contract FlashloanStrategy is Admin, IFlashLoanRecipient {
    /// ENUMS ///

    enum FlashloanStatus {
        FLASHLOAN_UNLOCKED,
        FLASHLOAN_INITIATED,
        CALLBACK_INITIATED
    }

    enum FlashloanProvider {
        AAVEV2,
        AAVEV3,
        BALANCER,
        UNIV2,
        UNIV3,
        MORPHO
    }

    /// ERRORS: Strategy ///

    error NotFlashloanStrategy(); // 0x9862416d
    error InvalidFlashloanData();
    error FlashloanNotInitiated();
    error FlashloanAlreadyInitiated();
    error FlashloanNotReset();
    error NotAnAssetPair();
    error UnauthorizedOperation();
    error SenderIsNotStrategy();
    error SenderIsNotAaveLendingPool();
    error SenderIsNotAaveV3LendingPool();
    error SenderIsNotBalancerVault();
    error SenderIsNotUniswapPool();
    error SenderIsNorMorpho();
    error NotSingleAsset();

    /// ERRORS: Registry ///

    /// @notice Thrown when array lengths don't match when registering flashloan
    /// operation types
    error ParamsMismatch();

    /// @notice Thrown when trying to override stub for an already registered
    /// flashloan operation
    error SelectorAlreadyLinked();

    /// STORAGE ///

    // Contract addresses
    SickleFactory public immutable sickleFactory;
    address public immutable aaveV2LendingPool;
    address public immutable aaveV3LendingPool;
    address public immutable balancerVault;
    address public immutable quickswapFactoryAddr;
    address public immutable uniswapV3FactoryAddr;
    address public immutable morpho;

    // Operational variables
    bytes32 flashloanDataHash;
    FlashloanStatus currentFlashloanStatus; // added reentrancy protection

    /// @notice Returns the stub contract address corresponding to the flashloan
    /// operation's function selector
    /// @dev if address(0) is returned, the flashloan operation does not exist
    /// or is not whitelisted
    /// param: flashloanOpSelector Function selector of the flashloan operation
    /// @return Address of the corresponding stub if it exists
    mapping(bytes4 => address) public whitelistedFlashloanOpsRegistry;

    /// WRITE FUNCTIONS ///

    /// @param admin_ Address of the admin
    /// @param whitelistedOpsSelectors_ Array of flashloan operation types to
    /// whitelist
    /// @param correspondingStrategies_ Array of strategy addresses where
    /// flashloan operations will be executed
    constructor(
        address admin_,
        SickleFactory sickleFactory_,
        address aaveV2LendingPool_,
        address aaveV3LendingPool_,
        address balancerVault_,
        address quickswapFactoryAddr_,
        address uniswapV3FactoryAddr_,
        address morpho_,
        bytes4[] memory whitelistedOpsSelectors_,
        address[] memory correspondingStrategies_
    ) Admin(admin_) {
        sickleFactory = sickleFactory_;
        aaveV2LendingPool = aaveV2LendingPool_;
        aaveV3LendingPool = aaveV3LendingPool_;
        balancerVault = balancerVault_;
        quickswapFactoryAddr = quickswapFactoryAddr_;
        uniswapV3FactoryAddr = uniswapV3FactoryAddr_;
        morpho = morpho_;

        currentFlashloanStatus = FlashloanStatus.FLASHLOAN_UNLOCKED;

        _setWhitelistedFlashloanOpsSelectors(
            whitelistedOpsSelectors_, correspondingStrategies_
        );
    }

    /// @notice Sets the approval status and corresponding stubs of several
    /// flashloan operation types
    /// @param whitelistedOpsSelectors Array of flashloan operation types to
    /// whitelist
    /// @param correspondingStrategies Array of strategy addresses where
    /// flashloan operations will be executed
    /// @custom:access Restricted to protocol admin.
    function setWhitelistedFlashloanOpsSelectors(
        bytes4[] memory whitelistedOpsSelectors,
        address[] memory correspondingStrategies
    ) external onlyAdmin {
        _setWhitelistedFlashloanOpsSelectors(
            whitelistedOpsSelectors, correspondingStrategies
        );
    }

    function _setWhitelistedFlashloanOpsSelectors(
        bytes4[] memory whitelistedOpsSelectors,
        address[] memory correspondingStrategies
    ) internal {
        if (whitelistedOpsSelectors.length != correspondingStrategies.length) {
            revert ParamsMismatch();
        }

        uint256 length = whitelistedOpsSelectors.length;
        for (uint256 i; i < length;) {
            if (
                whitelistedFlashloanOpsRegistry[whitelistedOpsSelectors[i]]
                    != address(0)
            ) {
                revert SelectorAlreadyLinked();
            }

            whitelistedFlashloanOpsRegistry[whitelistedOpsSelectors[i]] =
                correspondingStrategies[i];

            emit FlashloanStrategyEvents.SelectorLinked(
                whitelistedOpsSelectors[i], correspondingStrategies[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    modifier callbackSafetyCheck(bytes memory params) {
        bytes32 hashCheck = keccak256(params);
        if (hashCheck != flashloanDataHash) {
            revert InvalidFlashloanData();
        }
        if (currentFlashloanStatus != FlashloanStatus.FLASHLOAN_INITIATED) {
            revert FlashloanNotInitiated();
        }

        _;

        // resetting currentFlashloanStatus to FLASHLOAN_UNLOCKED after all
        // operations are finished
        currentFlashloanStatus = FlashloanStatus.FLASHLOAN_UNLOCKED;
    }

    /// @notice Routing function that initiates the flashloan at the indicated
    /// provider
    /// @param flashloanProvider Bytes blob containing the name of the flashloan
    /// provider and optionally the fee tier
    /// @param assets Array of contract addresses of the tokens being borrowed
    /// @param amounts Array of amounts of tokens being borrowed
    /// @param params Bytes blob contains all necessary parameters for the
    /// post-flashloan function
    /// @dev if using a uniswap call, the assets array must contain the token0
    /// and token1 of the called pool in the correct order
    function initiateFlashloan(
        address sickleAddress,
        bytes calldata flashloanProvider,
        address[] calldata assets,
        uint256[] calldata amounts,
        bytes calldata params
    ) external {
        if (assets.length != amounts.length) {
            revert SickleRegistry.ArrayLengthMismatch();
        }
        if (currentFlashloanStatus != FlashloanStatus.FLASHLOAN_UNLOCKED) {
            revert FlashloanAlreadyInitiated();
        }
        SickleRegistry registry = sickleFactory.registry();
        if (registry.isWhitelistedCaller(msg.sender) == false) {
            revert SenderIsNotStrategy();
        }

        // setting the currentFlashloanStatus to FLASHLOAN_INITIATED to avoid
        // reentrancy and allow callbacks only
        currentFlashloanStatus = FlashloanStatus.FLASHLOAN_INITIATED;

        (FlashloanProvider providerType, uint24 providerFee) =
            abi.decode(flashloanProvider, (FlashloanProvider, uint24));

        if (providerType == FlashloanProvider.AAVEV2) {
            uint256[] memory modes = new uint256[](assets.length);
            // mode 0 = no debt incurred, everything repaid at end of flashloan
            bytes memory aaveV2params = abi.encode(sickleAddress, params);
            // storing the hash of the callback data for safety checks
            flashloanDataHash = keccak256(aaveV2params);
            ILendingPoolV2(aaveV2LendingPool).flashLoan(
                address(this), // flashloan receiver
                assets,
                amounts,
                modes,
                address(0), // onBehalfOf variable
                aaveV2params,
                0 // referral code
            );
        } else if (providerType == FlashloanProvider.AAVEV3) {
            bytes memory aaveV3params = abi.encode(sickleAddress, params);
            // storing the hash of the callback data for safety checks
            flashloanDataHash = keccak256(aaveV3params);
            if (assets.length == 1) {
                IPoolV3(aaveV3LendingPool).flashLoanSimple(
                    address(this), // flashloan receiver
                    assets[0],
                    amounts[0],
                    aaveV3params,
                    0 // referral code
                );
            } else {
                uint256[] memory modes = new uint256[](assets.length);
                // mode 0 = no debt incurred, everything repaid at end of
                // flashloan
                IPoolV3(aaveV3LendingPool).flashLoan(
                    address(this), // flashloan receiver
                    assets,
                    amounts,
                    modes,
                    address(0),
                    aaveV3params,
                    0 // referral code
                );
            }
        } else if (providerType == FlashloanProvider.BALANCER) {
            bytes memory balancerParams = abi.encode(sickleAddress, params);
            // storing the hash of the callback data for safety checks
            flashloanDataHash = keccak256(balancerParams);
            IBalancerVault(balancerVault).flashLoan(
                this, assets, amounts, balancerParams
            );
        } else if (providerType == FlashloanProvider.UNIV2) {
            if (assets.length != 2) revert NotAnAssetPair();
            address poolAddress = IUniswapV2Factory(quickswapFactoryAddr)
                .getPair(assets[0], assets[1]);
            (,, uint256[] memory premiums,) =
                abi.decode(params[4:], (address[], uint256[], uint256[], bytes));
            bytes memory uniswapFlashParams = abi.encode(
                sickleAddress, poolAddress, assets, amounts, premiums, params
            );
            // storing the hash of the callback data for safety checks
            flashloanDataHash = keccak256(uniswapFlashParams);
            IUniswapV2Pair(poolAddress).swap(
                amounts[0], amounts[1], address(this), uniswapFlashParams
            );
        } else if (providerType == FlashloanProvider.UNIV3) {
            if (assets.length != 2) revert NotAnAssetPair();
            address poolAddress = IUniswapV3Factory(uniswapV3FactoryAddr)
                .getPool(assets[0], assets[1], providerFee);
            (,, uint256[] memory premiums,) =
                abi.decode(params[4:], (address[], uint256[], uint256[], bytes));
            bytes memory uniswapFlashParams = abi.encode(
                sickleAddress, poolAddress, assets, amounts, premiums, params
            );
            // storing the hash of the callback data for safety checks
            flashloanDataHash = keccak256(uniswapFlashParams);
            IUniswapV3Pool(poolAddress).flash(
                address(this), amounts[0], amounts[1], uniswapFlashParams
            );
        } else if (providerType == FlashloanProvider.MORPHO) {
            if (assets.length != 1) revert NotSingleAsset();
            bytes memory morphoParams =
                abi.encode(sickleAddress, assets[0], params);
            // storing the hash of the callback data for safety checks
            flashloanDataHash = keccak256(morphoParams);
            IMorpho(morpho).flashLoan(assets[0], amounts[0], morphoParams);
        } else {
            revert UnauthorizedOperation();
        }

        // resetting the flashloanDataHash variable to zero bytes at the end of
        // conversion operation
        flashloanDataHash = bytes32(0);

        if (currentFlashloanStatus != FlashloanStatus.FLASHLOAN_UNLOCKED) {
            revert FlashloanNotReset();
        }
    }

    /// @notice Callback function for flashloans coming from Aave's LendingPool
    /// contract (single-asset V3)
    /// @param asset Contract address of the token being borrowed
    /// @param amount Amount of tokens being borrowed
    /// @param premium Premium amount charged by the Aave protocol
    /// @param paramsInput Bytes blob contains all necessary parameters for the
    /// post-flashloan function
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address, // initiator
        bytes calldata paramsInput
    ) external callbackSafetyCheck(paramsInput) returns (bool) {
        if (msg.sender != aaveV3LendingPool) {
            revert SenderIsNotAaveV3LendingPool();
        }

        (address sickleAddress, bytes memory callback) =
            abi.decode(paramsInput, (address, bytes));

        address targetStrategy = _checkSelector(callback);

        // setting the currentFlashloanStatus to CALLBACK_INITIATED to avoid
        // reentrancy
        currentFlashloanStatus = FlashloanStatus.CALLBACK_INITIATED;

        // transfer borrowed assets to the sickle
        SafeTransferLib.safeTransfer(asset, sickleAddress, amount);

        // execute post-flashloan strategy function via a delegatecall from the
        // sickle
        {
            address[] memory targetStrategyArray = new address[](1);
            targetStrategyArray[0] = targetStrategy;
            bytes[] memory calldataArray = new bytes[](1);
            calldataArray[0] = callback;

            Multicall(sickleAddress).multicall(
                targetStrategyArray, calldataArray
            );
        }

        // approving borrowed funds + premiums to be repaid to the Lending Pool
        // contract
        SafeTransferLib.safeApprove(asset, aaveV3LendingPool, amount + premium);
        return true;

        // debt is automatically repaid
    }

    function executeOperation(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums,
        address, // initiator
        bytes memory paramsInput
    ) external callbackSafetyCheck(paramsInput) returns (bool) {
        if (assets.length != amounts.length || assets.length != premiums.length)
        {
            revert SickleRegistry.ArrayLengthMismatch();
        }

        if (msg.sender != aaveV2LendingPool && msg.sender != aaveV3LendingPool)
        {
            revert SenderIsNotAaveLendingPool();
        }

        (address sickleAddress, bytes memory callback) =
            abi.decode(paramsInput, (address, bytes));

        address targetStrategy = _checkSelector(callback);

        // setting the currentFlashloanStatus to CALLBACK_INITIATED to avoid
        // reentrancy
        currentFlashloanStatus = FlashloanStatus.CALLBACK_INITIATED;

        // transfer borrowed assets to the sickle
        _transferAssets(sickleAddress, assets, amounts);

        // execute post-flashloan strategy function via a delegatecall from the
        // sickle
        {
            address[] memory targetStrategyArray = new address[](1);
            targetStrategyArray[0] = targetStrategy;
            bytes[] memory calldataArray = new bytes[](1);
            calldataArray[0] = callback;

            Multicall(sickleAddress).multicall(
                targetStrategyArray, calldataArray
            );
        }

        // approving borrowed funds + premiums to be repaid to the Lending Pool
        // contract
        _approveAssets(msg.sender, assets, amounts, premiums);

        return true;

        // debt is automatically repaid
    }

    /// @notice Callback function for flashloans coming from Balancer's Vault
    /// contract
    /// @param tokens Array of contract addresses of the tokens being borrowed
    /// @param amounts Array of amounts of tokens being borrowed
    /// @param premiums Array of premium amounts charged by the Balancer
    /// protocol
    /// @param paramsInput Bytes blob contains all necessary parameters for the
    /// post-flashloan function
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        bytes memory paramsInput
    ) external callbackSafetyCheck(paramsInput) {
        if (tokens.length != amounts.length || tokens.length != premiums.length)
        {
            revert SickleRegistry.ArrayLengthMismatch();
        }

        if (msg.sender != balancerVault) {
            revert SenderIsNotBalancerVault();
        }

        (address sickleAddress, bytes memory params) =
            abi.decode(paramsInput, (address, bytes));

        address targetStrategy = _checkSelector(params);

        // setting the currentFlashloanStatus to CALLBACK_INITIATED to avoid
        // reentrancy
        currentFlashloanStatus = FlashloanStatus.CALLBACK_INITIATED;

        // convert data and transfer borrowed assets to the sickle
        _transferAssets(sickleAddress, tokens, amounts);

        // execute post-flashloan strategy function via a delegatecall from the
        // sickle
        {
            address[] memory targetStrategyArray = new address[](1);
            targetStrategyArray[0] = targetStrategy;
            bytes[] memory calldataArray = new bytes[](1);
            calldataArray[0] = params;

            Multicall(sickleAddress).multicall(
                targetStrategyArray, calldataArray
            );
        }

        // transferring borrowed funds + premiums to be repaid to the Balancer
        // Vault contract
        _transferAssets(balancerVault, tokens, amounts, premiums);
    }

    /// @notice Callback function for flashloans coming from UniswapV2 pairs
    /// @param params Bytes blob contains all necessary parameters for the
    /// post-flashloan function
    function uniswapV2Call(
        address, //sender
        uint256, // amount0
        uint256, // amount1
        bytes calldata params
    ) external callbackSafetyCheck(params) {
        (
            address sickleAddress,
            address poolAddress,
            address[] memory assets,
            uint256[] memory amounts,
            uint256[] memory premiums,
            bytes memory callback
        ) = abi.decode(
            params, (address, address, address[], uint256[], uint256[], bytes)
        );

        _uniswapCallback(
            sickleAddress, poolAddress, assets, amounts, premiums, callback
        );
    }

    /// @notice Callback function for flashloans coming from UniswapV3 pools
    /// @param params Bytes blob contains all necessary parameters for the
    /// post-flashloan function
    function uniswapV3FlashCallback(
        uint256, // fee0
        uint256, // fee1
        bytes calldata params
    ) external callbackSafetyCheck(params) {
        (
            address sickleAddress,
            address poolAddress,
            address[] memory assets,
            uint256[] memory amounts,
            uint256[] memory premiums,
            bytes memory callback
        ) = abi.decode(
            params, (address, address, address[], uint256[], uint256[], bytes)
        );

        _uniswapCallback(
            sickleAddress, poolAddress, assets, amounts, premiums, callback
        );
    }

    /// @notice Callback function for flashloans coming from PancakeV3 pools
    /// @param params Bytes blob contains all necessary parameters for the
    /// post-flashloan function
    function pancakeV3FlashCallback(
        uint256, // fee0
        uint256, // fee1
        bytes calldata params
    ) external callbackSafetyCheck(params) {
        (
            address sickleAddress,
            address poolAddress,
            address[] memory assets,
            uint256[] memory amounts,
            uint256[] memory premiums,
            bytes memory callback
        ) = abi.decode(
            params, (address, address, address[], uint256[], uint256[], bytes)
        );

        _uniswapCallback(
            sickleAddress, poolAddress, assets, amounts, premiums, callback
        );
    }

    function onMorphoFlashLoan(
        uint256 assets,
        bytes calldata data
    ) external callbackSafetyCheck(data) {
        (address sickleAddress, address token, bytes memory callback) =
            abi.decode(data, (address, address, bytes));

        // Check that we're being called from Morpho
        if (msg.sender != morpho) {
            revert SenderIsNorMorpho();
        }

        address targetStrategy = _checkSelector(callback);

        // Set the currentFlashloanStatus to CALLBACK_INITIATED to avoid
        // reentrancy
        currentFlashloanStatus = FlashloanStatus.CALLBACK_INITIATED;

        // Transfer borrowed assets to the sickle
        SafeTransferLib.safeTransfer(token, sickleAddress, assets);

        // Execute post-flashloan strategy function via a delegatecall from the
        // sickle
        {
            address[] memory targetStrategyArray = new address[](1);
            targetStrategyArray[0] = targetStrategy;
            bytes[] memory calldataArray = new bytes[](1);
            calldataArray[0] = callback;

            Multicall(sickleAddress).multicall(
                targetStrategyArray, calldataArray
            );
        }

        SafeTransferLib.safeApprove(token, morpho, assets);
    }

    /// VIEW FUNCTIONS ///

    /// @notice Returns the premium amounts on borrowed amounts based on the
    /// flashloan provider
    /// @param flashloanProvider Bytes blob indicating the selected flashloan
    /// provider and optionally the fee tier
    /// @param amounts Array of amounts of tokens being borrowed
    /// @return Array of premium amounts corresponding to each borrowed amount
    function calculatePremiums(
        bytes calldata flashloanProvider,
        uint256[] calldata amounts
    ) public view returns (uint256[] memory) {
        uint256[] memory premiums = new uint256[](amounts.length);

        (FlashloanProvider providerType, uint24 providerFee) =
            abi.decode(flashloanProvider, (FlashloanProvider, uint24));

        if (providerType == FlashloanProvider.AAVEV2) {
            uint256 aaveV2FlashloanPremiumInBasisPoints =
                ILendingPoolV2(aaveV2LendingPool).FLASHLOAN_PREMIUM_TOTAL();
            uint256 length = amounts.length;
            for (uint256 i; i < length;) {
                if (amounts[i] > 0 && aaveV2FlashloanPremiumInBasisPoints > 0) {
                    premiums[i] = (
                        (amounts[i] * aaveV2FlashloanPremiumInBasisPoints - 1)
                            / 10_000
                    ) + 1;
                } else {
                    premiums[i] = 0;
                }

                unchecked {
                    ++i;
                }
            }
        } else if (providerType == FlashloanProvider.AAVEV3) {
            uint256 aaveV3FlashloanPremiumInBasisPoints =
                IPoolV3(aaveV3LendingPool).FLASHLOAN_PREMIUM_TOTAL();
            uint256 length = amounts.length;
            for (uint256 i; i < length;) {
                if (amounts[i] > 0 && aaveV3FlashloanPremiumInBasisPoints > 0) {
                    premiums[i] = (
                        (amounts[i] * aaveV3FlashloanPremiumInBasisPoints - 1)
                            / 10_000
                    ) + 1;
                } else {
                    premiums[i] = 0;
                }

                unchecked {
                    ++i;
                }
            }
        } else if (providerType == FlashloanProvider.BALANCER) {
            uint256 balancerFlashLoanFeePercentage = IBalancerVault(
                balancerVault
            ).getProtocolFeesCollector().getFlashLoanFeePercentage();
            uint256 length = amounts.length;
            for (uint256 i; i < length;) {
                // reproducing the mulUp() function from Balancer's FixedPoint
                // helper library
                if (balancerFlashLoanFeePercentage == 0 || amounts[i] == 0) {
                    premiums[i] = 0;
                } else {
                    premiums[i] = (
                        (amounts[i] * balancerFlashLoanFeePercentage - 1) / 1e18
                    ) + 1;
                }

                unchecked {
                    ++i;
                }
            }
        } else if (providerType == FlashloanProvider.UNIV2) {
            uint256 length = amounts.length;
            for (uint256 i; i < length;) {
                if (amounts[i] > 0) {
                    premiums[i] = ((amounts[i] * 3) / 997) + 1;
                } else {
                    premiums[i] = 0;
                }

                unchecked {
                    ++i;
                }
            }
        } else if (providerType == FlashloanProvider.UNIV3) {
            uint256 length = amounts.length;
            for (uint256 i; i < length;) {
                if (amounts[i] > 0) {
                    premiums[i] =
                        ((amounts[i] * providerFee) / 10_000 / 100) + 1; // hundredths
                        // of basis points
                } else {
                    premiums[i] = 0;
                }

                unchecked {
                    ++i;
                }
            }
        }

        return premiums;
    }

    /// @notice Returns the first four bytes of a given bytes blob
    /// @param params Bytes blob from which we want to extract the first four
    /// bytes corresponding to the function selector
    /// @return selector Bytes4 containing the function selector
    /// @dev helper function for uniswapV2Call and uniswapV3Call functions where
    /// the function selector is not at the beginning of the bytes parameter in
    /// the callback
    function extractSelector(bytes memory params)
        public
        pure
        returns (bytes4 selector)
    {
        assembly {
            // 1. Load 4 bytes from `params`
            // 2. Shift the bytes left by 224 bits/28 bytes so that they're at
            //    the beginning of the 32-byte memory slot as required by
            //    Solidity ABI spec
            // 3. Store the result in `selector`
            selector := shl(224, mload(add(params, 4)))
        }
    }

    /// INTERNALS ///

    function _transferAssets(
        address to,
        address[] memory assets,
        uint256[] memory amounts
    ) internal {
        uint256[] memory premiums = new uint256[](assets.length);
        _transferAssets(to, assets, amounts, premiums);
    }

    function _transferAssets(
        address to,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) internal {
        uint256[] memory premiums = new uint256[](assets.length);
        _transferAssets(to, assets, amounts, premiums);
    }

    function _transferAssets(
        address to,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums
    ) internal {
        uint256 length = assets.length;
        for (uint256 i; i < length;) {
            uint256 total = amounts[i] + premiums[i];
            if (total > 0) {
                SafeTransferLib.safeTransfer(assets[i], to, total);
            }

            unchecked {
                ++i;
            }
        }
    }

    function _transferAssets(
        address to,
        IERC20[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums
    ) internal {
        uint256 length = assets.length;
        for (uint256 i; i < length;) {
            uint256 total = amounts[i] + premiums[i];
            if (total > 0) {
                SafeTransferLib.safeTransfer(address(assets[i]), to, total);
            }

            unchecked {
                ++i;
            }
        }
    }

    function _approveAssets(
        address to,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums
    ) internal {
        uint256 length = assets.length;
        for (uint256 i; i < length;) {
            uint256 total = amounts[i] + premiums[i];
            if (total > 0) {
                SafeTransferLib.safeApprove(assets[i], to, total);
            }

            unchecked {
                ++i;
            }
        }
    }

    function _checkSelector(bytes memory params)
        internal
        view
        returns (address)
    {
        // extracting function selector from the callback parameters
        bytes4 flashloanOpSelector = extractSelector(params);

        // fetching the corresponding strategy from the registry
        address targetStrategy =
            whitelistedFlashloanOpsRegistry[flashloanOpSelector];

        if (targetStrategy == address(0)) {
            revert UnauthorizedOperation();
        }

        return targetStrategy;
    }

    function _uniswapCallback(
        address sickleAddress,
        address poolAddress,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums,
        bytes memory callback
    ) internal {
        if (assets.length != amounts.length || assets.length != premiums.length)
        {
            revert SickleRegistry.ArrayLengthMismatch();
        }

        // Check that we're being called from a Uniswap pool
        if (msg.sender != poolAddress) {
            revert SenderIsNotUniswapPool();
        }

        address targetStrategy = _checkSelector(callback);

        // Set the currentFlashloanStatus to CALLBACK_INITIATED to avoid
        // reentrancy
        currentFlashloanStatus = FlashloanStatus.CALLBACK_INITIATED;

        // Transfer borrowed assets to the sickle
        _transferAssets(sickleAddress, assets, amounts);

        // Execute post-flashloan strategy function via a delegatecall from the
        // sickle
        {
            address[] memory targetStrategyArray = new address[](1);
            targetStrategyArray[0] = targetStrategy;
            bytes[] memory calldataArray = new bytes[](1);
            calldataArray[0] = callback;

            Multicall(sickleAddress).multicall(
                targetStrategyArray, calldataArray
            );
        }

        // Transfer borrowed funds + premiums to be repaid to the Uniswap pool
        // contract
        _transferAssets(poolAddress, assets, amounts, premiums);
    }
}
