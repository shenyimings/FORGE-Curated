// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract EIP712 is EIP712Upgradeable {
    bytes32 public constant PROPOSAL_REQUEST_TYPEHASH =
        keccak256("ProposalRequest(bytes32 projectId,string base64RecParam,string serverURL)");
    bytes32 public constant DEPLOYMENT_REQUEST_TYPEHASH =
        keccak256("DeploymentRequest(bytes32 projectId,string base64RecParam,string serverURL)");

    function getAddress() public view returns (address) {
        (,,,, address verifyingContract,,) = eip712Domain();
        return verifyingContract;
    }

    function getRequestProposalDigest(bytes32 projectId, string memory base64RecParam, string memory serverURL)
        public
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                PROPOSAL_REQUEST_TYPEHASH, projectId, keccak256(bytes(base64RecParam)), keccak256(bytes(serverURL))
            )
        );

        return _hashTypedDataV4(structHash);
    }

    function getRequestDeploymentDigest(bytes32 projectId, string memory base64RecParam, string memory serverURL)
        public
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                DEPLOYMENT_REQUEST_TYPEHASH, projectId, keccak256(bytes(base64RecParam)), keccak256(bytes(serverURL))
            )
        );

        return _hashTypedDataV4(structHash);
    }

    function getSignerAddress(bytes32 hash, bytes memory signature) public pure returns (address) {
        address signerAddr = ECDSA.recover(hash, signature);
        require(signerAddr != address(0), "Invalid signature");
        return signerAddr;
    }
}
