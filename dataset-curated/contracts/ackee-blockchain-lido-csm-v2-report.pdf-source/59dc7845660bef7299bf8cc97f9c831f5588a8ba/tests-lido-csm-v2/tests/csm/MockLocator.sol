
contract MockLocator {
    address public immutable fallbackLocator;

    address public immutable triggerableWithdrawalsGateway;

    constructor(address _fallbackLocator, address _triggerableWithdrawalsGateway) {
        fallbackLocator = _fallbackLocator;
        triggerableWithdrawalsGateway = _triggerableWithdrawalsGateway;
    }

    fallback(bytes calldata b) external returns (bytes memory) {
        (bool success, bytes memory data) = fallbackLocator.staticcall(b);
        if (success) {
            return data;
        }

        assembly {
            revert(add(data, 32), mload(data))
        }
    }
}