pragma solidity ^0.8.0;

import {SignatureModule} from "./signatureModule/SignatureModule.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/// @dev Ripped from OZ 4.9.4 ERC20Permit.sol with namespaced storage and support of ERC1271 signatures
abstract contract PermitModule is SignatureModule {

    using Counters for Counters.Counter;

    //==============================================================================
    // Storage
    //==============================================================================

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    struct PermitModuleStorage {
        mapping(address => Counters.Counter) nonces;
    }

    // keccak256(abi.encode(uint256(keccak256("frax.storage.PermitModule")) - 1)) & ~bytes32(uint256(0xff))    
    bytes32 private constant PermitModuleStorageLocation = 0xb39b43abb0b115e0a59dece28477e279ee5f8e2fd55fbe200557c3ab864a0300;

    function _getPermitModuleStorage() private pure returns (PermitModuleStorage storage $) {
        assembly {
            $.slot := PermitModuleStorageLocation
        }
    }

    //==============================================================================
    // Functions
    //==============================================================================

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        permit({
            owner: owner,
            spender: spender,
            value: value,
            deadline: deadline,
            signature: abi.encodePacked(r, s, v)
        });
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) public virtual {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");

        _requireIsValidSignatureNow({
            signer: owner,
            structHash: keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline)),
            signature: signature
        });

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view virtual returns (uint256) {
        PermitModuleStorage storage $ = _getPermitModuleStorage();
        return $.nonces[owner].current();
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _useNonce(address owner) internal virtual returns (uint256 current) {
        PermitModuleStorage storage $ = _getPermitModuleStorage();
        current = $.nonces[owner].current();
        $.nonces[owner].increment();
    }

    //==============================================================================
    // Virtual overriden methods
    //==============================================================================

    function _approve(address owner, address spender, uint256 amount) internal virtual {}
}