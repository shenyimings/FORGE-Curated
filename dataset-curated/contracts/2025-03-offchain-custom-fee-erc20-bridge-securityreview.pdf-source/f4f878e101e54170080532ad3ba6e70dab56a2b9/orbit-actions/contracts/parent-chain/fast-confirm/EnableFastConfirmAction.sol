// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IRollupAdmin {
    function anyTrustFastConfirmer() external view returns (address);
    function isValidator(address) external view returns (bool);
    function setAnyTrustFastConfirmer(address _anyTrustFastConfirmer) external;
    function setMinimumAssertionPeriod(uint256 _minimumAssertionPeriod) external;
    function setValidator(address[] memory _validator, bool[] memory _val) external;
}

interface IGnosisSafeProxyFactory {
    function createProxyWithNonce(address _singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

contract EnableFastConfirmAction {
    address public immutable GNOSIS_SAFE_PROXY_FACTORY;
    address public immutable GNOSIS_SAFE_1_3_0;
    address public immutable GNOSIS_COMPATIBILITY_FALLBACK_HANDLER;

    constructor(address gnosisSafeProxyFactory, address gnosisSafe1_3_0, address gnosisCompatibilityFallbackHandler) {
        require(gnosisSafeProxyFactory.code.length > 0, "gnosisSafeProxyFactory doesn't exist on this chain");
        require(gnosisSafe1_3_0.code.length > 0, "gnosisSafe1_3_0 doesn't exist on this chain");
        require(
            gnosisCompatibilityFallbackHandler.code.length > 0,
            "gnosisCompatibilityFallbackHandler doesn't exist on this chain"
        );
        GNOSIS_SAFE_PROXY_FACTORY = gnosisSafeProxyFactory;
        GNOSIS_SAFE_1_3_0 = gnosisSafe1_3_0;
        GNOSIS_COMPATIBILITY_FALLBACK_HANDLER = gnosisCompatibilityFallbackHandler;
    }

    function perform(IRollupAdmin rollup, address[] calldata fastConfirmCommittee, uint256 threshold, uint256 salt)
        external
    {
        require(rollup.anyTrustFastConfirmer() == address(0), "Fast confirm already enabled");
        require(threshold > 0 && threshold <= fastConfirmCommittee.length, "Invalid threshold");
        for (uint256 i = 0; i < fastConfirmCommittee.length; i++) {
            require(fastConfirmCommittee[i] != address(0), "Invalid address");
            require(rollup.isValidator(fastConfirmCommittee[i]), "fastConfirmCommittee members must be validator");
        }
        address fastConfirmer = IGnosisSafeProxyFactory(GNOSIS_SAFE_PROXY_FACTORY).createProxyWithNonce(
            GNOSIS_SAFE_1_3_0,
            abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                fastConfirmCommittee,
                threshold,
                address(0),
                "",
                GNOSIS_COMPATIBILITY_FALLBACK_HANDLER,
                address(0),
                0,
                address(0)
            ),
            salt
        );
        rollup.setAnyTrustFastConfirmer(fastConfirmer);
        address[] memory validators = new address[](1);
        validators[0] = fastConfirmer;
        bool[] memory val = new bool[](1);
        val[0] = true;
        rollup.setValidator(validators, val);
        rollup.setMinimumAssertionPeriod(1);
    }
}
