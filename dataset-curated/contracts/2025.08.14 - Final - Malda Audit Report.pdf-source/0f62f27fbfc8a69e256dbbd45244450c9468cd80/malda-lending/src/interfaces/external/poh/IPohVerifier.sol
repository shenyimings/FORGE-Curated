

// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

interface IPohVerifier {
    /**
     * @notice Check if the provided signature has been signed by signer
     * @dev human is supposed to be a POH address, this is what is being signed by the POH API
     * @param signature The signature to check
     * @param human the address for which the signature has been crafted
     * @return True if the signature was made by signer, false otherwise
     */
    function verify(bytes memory signature, address human) external view returns (bool);

    /**
     * @notice Returns the signer's address
     */
    function getSigner() external view returns (address);
}
