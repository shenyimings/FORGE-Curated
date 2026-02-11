// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

import "./interfaces/IOperatorController.sol";

/**
 * @title Key Validation Oracle
 * @notice Handles validator key/signature pair validation
 */
contract KeyValidationOracle is Ownable, ChainlinkClient {
    using Chainlink for Chainlink.Request;

    IOperatorController public nwlOperatorController;
    IOperatorController public wlOperatorController;

    uint256 public fee;
    bytes32 public jobId;

    event SetOracleConfig(address oracleAddress, bytes32 jobId, uint256 fee);

    constructor(
        address _nwlOperatorController,
        address _wlOperatorController,
        address _chainlinkToken,
        address _chainlinkOracle,
        bytes32 _jobId,
        uint256 _fee
    ) {
        nwlOperatorController = IOperatorController(_nwlOperatorController);
        wlOperatorController = IOperatorController(_wlOperatorController);
        setChainlinkToken(_chainlinkToken);
        setChainlinkOracle(_chainlinkOracle);
        jobId = _jobId;
        fee = _fee;
    }

    /**
     * @notice ERC677 implementation that accepts a fee and initiates a key pair validation
     * @param _sender sender of the token transfer
     * @param _value value of the token transfer
     * @param _calldata (operatorId - id of operator to validate for,
     * isWhitelisted - whether or not operator is whitelisted) ABI encoded
     */
    function onTokenTransfer(address _sender, uint256 _value, bytes calldata _calldata) external {
        require(msg.sender == chainlinkTokenAddress(), "Sender is not chainlink token");
        require(_value == fee, "Value is not equal to fee");

        (uint256 operatorId, bool isWhitelisted) = abi.decode(_calldata, (uint256, bool));

        _initiateKeyPairValidation(_sender, operatorId, isWhitelisted);
    }

    /**
     * @notice Reports the results of a validation request
     * @param _requestId id of chainlink request
     * @param _operatorId id of operator receiving the validation report
     * @param _isWhitelisted whether or not operator is whitelisted
     * @param _success whether or not validation was successful
     */
    function reportKeyPairValidation(
        bytes32 _requestId,
        uint256 _operatorId,
        bool _isWhitelisted,
        bool _success
    ) external recordChainlinkFulfillment(_requestId) {
        if (_isWhitelisted) {
            wlOperatorController.reportKeyPairValidation(_operatorId, _success);
        } else {
            nwlOperatorController.reportKeyPairValidation(_operatorId, _success);
        }
    }

    /**
     * @notice Sets oracle config variables
     * @param _oracleAddress address of oracle
     * @param _jobId id of job
     * @param _fee fee that must be paid for each request
     */
    function setOracleConfig(
        address _oracleAddress,
        bytes32 _jobId,
        uint256 _fee
    ) external onlyOwner {
        setChainlinkOracle(_oracleAddress);
        jobId = _jobId;
        fee = _fee;
        emit SetOracleConfig(_oracleAddress, _jobId, _fee);
    }

    /**
     * @notice Returns the chainlink oracle address
     * @return oracleAddress oracle address
     */
    function oracleAddress() external view returns (address) {
        return chainlinkOracleAddress();
    }

    /**
     * @notice Constructs and sends a key pair validation request
     * @param _sender sender of request
     * @param _operatorId id of operator to validate for
     * @param _isWhitelisted whether or not operator is whitelisted
     */
    function _initiateKeyPairValidation(
        address _sender,
        uint256 _operatorId,
        bool _isWhitelisted
    ) private {
        if (_isWhitelisted) {
            wlOperatorController.initiateKeyPairValidation(_sender, _operatorId);
        } else {
            nwlOperatorController.initiateKeyPairValidation(_sender, _operatorId);
        }

        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.reportKeyPairValidation.selector
        );

        req.add("operatorId", Strings.toString(_operatorId));
        req.add("isWhitelisted", _isWhitelisted ? "true" : "false");

        sendChainlinkRequest(req, fee);
    }
}
