import "csm/src/interfaces/ITriggerableWithdrawalsGateway.sol";
import "csm/src/interfaces/ICSModule.sol";

contract MockTriggerableWithdrawalsGateway is ITriggerableWithdrawalsGateway {
    address public constant WITHDRAWAL_REQUEST = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    ICSModule public module;

    function initialize(ICSModule _module) external {
        module = _module;
    }

    function triggerFullWithdrawals(ValidatorData[] calldata triggerableExitsData, address refundRecipient, uint256 exitType) external payable {
        (bool success, bytes memory feeData) = WITHDRAWAL_REQUEST.staticcall("");
        uint256 withdrawalRequestFee = abi.decode(feeData, (uint256));

        uint feeDiff = msg.value - withdrawalRequestFee * triggerableExitsData.length;

        for (uint256 i; i < triggerableExitsData.length; ++i) {
            (success,) = WITHDRAWAL_REQUEST.call{value: withdrawalRequestFee}(abi.encodePacked(triggerableExitsData[i].pubkey, uint64(0)));
            require(success, "Failed to trigger withdrawal");
        }

        for (uint256 i; i < triggerableExitsData.length; ++i) {
            module.onValidatorExitTriggered(
                triggerableExitsData[i].nodeOperatorId,
                triggerableExitsData[i].pubkey,
                withdrawalRequestFee,
                exitType
            );
        }

        if (feeDiff > 0) {
            if (refundRecipient == address(0)) {
                refundRecipient = msg.sender;
            }
            (success,) = refundRecipient.call{value: feeDiff}("");
            require(success, "Failed to send fee back to sender");
        }
    }
}