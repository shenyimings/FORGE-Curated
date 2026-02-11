interface IEIP712 {
    function eip712Domain() external view returns (
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract
    );
}
