// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract EIP712 is EIP712Upgradeable {
    bytes32 public constant PROPOSAL_REQUEST_TYPEHASH =
        keccak256("ProposalRequest(bytes32 projectId,string base64RecParam,string serverURL)");
    bytes32 public constant DEPLOYMENT_REQUEST_TYPEHASH =
        keccak256("DeploymentRequest(bytes32 projectId,string base64RecParam,string serverURL)");
    bytes32 public constant CREATE_AGENT_WITH_TOKEN_TYPEHASH = keccak256(
        "CreateAgentWithToken(bytes32 projectId,string base64RecParam,string serverURL,address privateWorkerAddress,address tokenAddress)"
    );
    bytes32 public constant CREATE_AGENT_WITH_NFT_TYPEHASH = keccak256(
        "CreateAgentWithNFT(bytes32 projectId,string base64RecParam,string serverURL,address privateWorkerAddress,uint256 tokenId)"
    );
    bytes32 public constant UPDATE_WORKER_CONFIG_TYPEHASH = keccak256(
        "UpdateWorkerConfig(address tokenAddress,bytes32 projectId,bytes32 requestID,string updatedBase64Config,uint256 nonce)"
    );
    bytes32 public constant RESET_DEPLOYMENT_REQUEST_TYPEHASH = keccak256(
        "ResetDeploymentRequest(bytes32 projectId,bytes32 requestID,address workerAddress,string updatedBase64Config,uint256 nonce)"
    );

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

    function getCreateAgentWithTokenDigest(
        bytes32 projectId,
        string memory base64RecParam,
        string memory serverURL,
        address privateWorkerAddress,
        address tokenAddress
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                CREATE_AGENT_WITH_TOKEN_TYPEHASH,
                projectId,
                keccak256(bytes(base64RecParam)),
                keccak256(bytes(serverURL)),
                privateWorkerAddress,
                tokenAddress
            )
        );

        return _hashTypedDataV4(structHash);
    }

    function getCreateAgentWithNFTDigest(
        bytes32 projectId,
        string memory base64RecParam,
        string memory serverURL,
        address privateWorkerAddress,
        uint256 tokenId
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                CREATE_AGENT_WITH_NFT_TYPEHASH,
                projectId,
                keccak256(bytes(base64RecParam)),
                keccak256(bytes(serverURL)),
                privateWorkerAddress,
                tokenId
            )
        );

        return _hashTypedDataV4(structHash);
    }

    function getUpdateWorkerConfigDigest(
        address tokenAddress,
        bytes32 projectId,
        bytes32 requestID,
        string memory updatedBase64Config,
        uint256 nonce
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                UPDATE_WORKER_CONFIG_TYPEHASH,
                tokenAddress,
                projectId,
                requestID,
                keccak256(bytes(updatedBase64Config)),
                nonce
            )
        );

        return _hashTypedDataV4(structHash);
    }

    function getRequestResetDeploymentDigest(
        bytes32 projectId,
        bytes32 requestID,
        address workerAddress,
        string memory updatedBase64Config,
        uint256 nonce
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                RESET_DEPLOYMENT_REQUEST_TYPEHASH,
                projectId,
                requestID,
                workerAddress,
                keccak256(bytes(updatedBase64Config)),
                nonce
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
