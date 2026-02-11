pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";
import {console} from "forge-std/console.sol";
import {ITeeRollupVerifier} from "./interfaces/ITeeRollupVerifier.sol";
import {DcapAttestationRouter} from "./DcapAttestationRouter.sol";

/**
 * @notice proxy
 */
contract TEEVerifierProxy is ITeeRollupVerifier, Ownable {
    address public dcapAttestationRouter;
    mapping(address => bool) _authorized;
    bool _isCallerRestricted = true;

    error Forbidden();
    error InvalidAddress();

    modifier onlyAuthorized() {
        if (_isCallerRestricted && !_authorized[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    constructor(address _dcapAttestationRouter) {
        if (_dcapAttestationRouter == address(0)) revert InvalidAddress();
        _initializeOwner(msg.sender);
        _setConfig(_dcapAttestationRouter);
        _authorized[msg.sender] = true;
    }

    function setConfig(address _dcapAttestationRouter) external onlyOwner {
        if (_dcapAttestationRouter == address(0)) revert InvalidAddress();
        _setConfig(_dcapAttestationRouter);
    }

    function setAuthorized(address caller, bool authorized) external onlyOwner {
        if (caller == address(0)) revert InvalidAddress();
        _authorized[caller] = authorized;
    }

    function enableCallerRestriction() external onlyOwner {
        _isCallerRestricted = true;
    }

    function disableCallerRestriction() external onlyOwner {
        _isCallerRestricted = false;
    }

    function verifyProof(bytes calldata aggrProof)
        external
        onlyAuthorized
        returns (uint32 _error_code, bytes32 commitment)
    {
        DcapAttestationRouter router = DcapAttestationRouter(dcapAttestationRouter);
        (_error_code, commitment) = router.verifyProof(aggrProof);
    }

    function _setConfig(address _dcapAttestationRouter) private {
        dcapAttestationRouter = _dcapAttestationRouter;
    }
}
