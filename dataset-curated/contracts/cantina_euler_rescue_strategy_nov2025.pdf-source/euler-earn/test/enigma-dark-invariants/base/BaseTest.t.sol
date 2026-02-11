// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC4626, IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {
    FlowCaps,
    FlowCapsConfig,
    Withdrawal,
    MAX_SETTABLE_FLOW_CAP,
    IPublicAllocatorStaticTyping,
    IPublicAllocatorBase
} from "src/interfaces/IPublicAllocator.sol";
import {IEulerEarn} from "src/interfaces/IEulerEarn.sol";

// Libraries
import {Vm} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

// Utils
import {Actor} from "../utils/Actor.sol";
import {PropertiesConstants} from "../utils/PropertiesConstants.sol";
import {StdAsserts} from "../utils/StdAsserts.sol";

// Contracts

// Base
import {BaseStorage} from "./BaseStorage.t.sol";

import "forge-std/console.sol";

/// @notice Base contract for all test contracts extends BaseStorage
/// @dev Provides setup modifier and cheat code setup
/// @dev inherits Storage, Testing constants assertions and utils needed for testing
abstract contract BaseTest is BaseStorage, PropertiesConstants, StdAsserts, StdUtils {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   ACTOR PROXY MECHANISM                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Actor proxy mechanism
    modifier setup() virtual {
        actor = actors[msg.sender];
        targetActor = address(actor);
        _;
        delete actor;
        delete targetActor;
        delete target;
    }

    modifier directCallCleanup() virtual {
        _;
        delete target;
    }

    /// @dev Solves medusa backward time warp issue
    modifier monotonicTimestamp() virtual {
        // Implement monotonic timestamp if needed
        _;
    }

    receive() external payable {}

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          STRUCTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     CHEAT CODE SETUP                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    /// @dev Virtual machine instance
    Vm internal constant vm = Vm(VM_ADDRESS);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   HELPERS: RANDOM GETTERS                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // ACTORS

    /// @notice Get a random actor proxy address
    function _getRandomActor(uint256 _i) internal view returns (address) {
        uint256 _actorIndex = _i % NUMBER_OF_ACTORS;
        return actorAddresses[_actorIndex];
    }

    // ASSETS

    /// @notice Get a random asset
    function _getRandomBaseAsset(uint8 i) internal view returns (address) {
        uint256 _assetIndex = i % baseAssets.length;
        return baseAssets[_assetIndex];
    }

    /// @notice Get a random asset address
    function _getRandomAsset(uint8 i) internal view returns (address) {
        uint256 _assetIndex = i % allAssets.length;
        return allAssets[_assetIndex];
    }

    // VAULTS

    function _getRandomVault(uint8 i) internal view returns (address) {
        uint256 _vaultIndex = i % allVaults.length;
        return address(allVaults[_vaultIndex]);
    }

    /// @notice Get a random market from eulerEarn
    function _getRandomMarket(address eulerEarnAddress, uint8 i) internal view returns (IERC4626) {
        uint256 _marketIndex = i % allMarkets[eulerEarnAddress].length;
        return allMarkets[eulerEarnAddress][_marketIndex];
    }

    /// @notice Get a random eVault
    function _getRandomEVault(uint8 i) internal view returns (address) {
        uint256 _vaultIndex = i % eVaults.length;
        return address(eVaults[_vaultIndex]);
    }

    /// @notice Get a random loan vault
    function _getRandomLoanVault(uint8 i) internal view returns (address) {
        uint256 _vaultIndex = i % loanVaults.length;
        return address(loanVaults[_vaultIndex]);
    }

    /// @notice Get a random eulerEarn vault
    function _getRandomEulerEarnVault(uint8 i) internal view returns (address) {
        uint256 _vaultIndex = i % eulerEarnVaults.length;
        return eulerEarnVaults[_vaultIndex];
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _setTargetActor(address user) internal {
        targetActor = user;
    }

    /// @notice Get a random address
    function _makeAddr(string memory name) internal pure returns (address addr) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
    }

    /// @notice Helper function to deploy a contract from bytecode
    function deployFromBytecode(bytes memory bytecode) internal returns (address child) {
        assembly {
            child := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    /// @notice Helper function to approve an amount of tokens to a spender, a proxy Actor
    function _approve(address token, Actor actor_, address spender, uint256 amount) internal {
        bool success;
        bytes memory returnData;
        (success, returnData) = actor_.proxy(token, abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(success, string(returnData));
    }

    /// @notice Helper function to safely approve an amount of tokens to a spender
    function _approve(address token, address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        _safeApprove(token, spender, 0);
        vm.prank(owner);
        _safeApprove(token, spender, amount);
    }

    /// @notice Helper function to safely approve an amount of tokens to a spender
    /// @dev This function is used to revert on failed approvals
    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory returnData) = token.call(abi.encodeCall(IERC20.approve, (spender, amount)));
        assert(success);
        if (returnData.length > 0) assert(abi.decode(returnData, (bool)));
    }

    /// @notice Helper function to transfer an amount of tokens to an address
    function _transferByActor(address token, address to, uint256 amount) internal {
        bool success;
        bytes memory returnData;
        (success, returnData) = actor.proxy(token, abi.encodeCall(IERC20.transfer, (to, amount)));
        require(success, string(returnData));
    }

    /// @notice Helper function to setup actor approvals
    /// @dev This function is used to setup actor approvals for a given set of tokens and contracts
    function _setupActorApprovals(address[] memory tokens, address[] memory contracts_) internal {
        for (uint256 i; i < actorAddresses.length; i++) {
            for (uint256 j; j < tokens.length; j++) {
                for (uint256 k; k < contracts_.length; k++) {
                    _approve(tokens[j], actorAddresses[i], contracts_[k], type(uint256).max);
                }
            }
        }
    }

    function _isMarketEnabled(IERC4626 _market, address _eulerEarnVaultAddress) internal view returns (bool) {
        return IEulerEarn(_eulerEarnVaultAddress).config(_market).enabled;
    }

    function _expectedSupplyAssets(IERC4626 _market, address _eulerEarnVaultAddress)
        internal
        view
        virtual
        returns (uint256 assets)
    {
        assets = _market.convertToAssets(_market.balanceOf(_eulerEarnVaultAddress));
    }

    function _isEulerEarnVault(address _eulerEarnVaultAddress) internal view returns (bool) {
        return _eulerEarnVaultAddress == address(eulerEarn) || _eulerEarnVaultAddress == address(eulerEarn2);
    }

    function _isEulerEarnVaultAndTarget(address _eulerEarnVaultAddress) internal view returns (bool) {
        return _isEulerEarnVault(_eulerEarnVaultAddress) && _eulerEarnVaultAddress == target;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       PROTOCOL HELPERS                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        LOGS HELPERS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
