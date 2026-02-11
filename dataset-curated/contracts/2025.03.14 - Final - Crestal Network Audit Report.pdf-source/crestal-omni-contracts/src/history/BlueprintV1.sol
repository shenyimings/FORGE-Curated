// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

contract Blueprint {
    enum Status {
        Init,
        Issued,
        Pickup,
        Deploying,
        Deployed,
        GeneratedProof
    }

    struct DeploymentStatus {
        Status status;
        address deployWorkerAddr;
    }

    string public VERSION;
    uint256 public factor;
    uint256 public totalProposalRequest;
    uint256 public totalDeploymentRequest;

    mapping(address => bytes32) public latestProposalRequestID;
    mapping(address => bytes32) public latestDeploymentRequestID;
    mapping(address => bytes32) public latestProjectID;

    mapping(address => uint256) public solverReputation;
    mapping(address => uint256) public workerReputation;
    mapping(bytes32 => DeploymentStatus) public requestDeploymentStatus;

    mapping(bytes32 => string) private deploymentProof;
    mapping(bytes32 => address) private requestSolver;
    mapping(bytes32 => address) private requestWorker;
    mapping(bytes32 => address) private projectIDs;

    event CreateProjectID(bytes32 indexed projectID, address walletAddress);
    event RequestProposal(
        bytes32 indexed projectID,
        address walletAddress,
        bytes32 indexed requestID,
        string base64RecParam,
        string serverURL
    );
    event RequestPrivateProposal(
        bytes32 indexed projectID,
        address walletAddress,
        address privateSolverAddress,
        bytes32 indexed requestID,
        string base64RecParam,
        string serverURL
    );
    event RequestDeployment(
        bytes32 indexed projectID,
        address walletAddress,
        address solverAddress,
        bytes32 indexed requestID,
        string base64Proposal,
        string serverURL
    );
    event RequestPrivateDeployment(
        bytes32 indexed projectID,
        address walletAddress,
        address privateWorkerAddress,
        address solverAddress,
        bytes32 indexed requestID,
        string base64Proposal,
        string serverURL
    );
    event AcceptDeployment(bytes32 indexed projectID, bytes32 indexed requestID, address indexed workerAddress);
    event GeneratedProofOfDeployment(
        bytes32 indexed projectID, bytes32 indexed requestID, string base64DeploymentProof
    );

    // get solver reputation
    function getReputation(address addr) public view returns (uint256) {
        return solverReputation[addr];
    }

    // set solver reputation
    function setReputation(address addr) private returns (uint256 reputation) {
        // get the solver reputation
        // uint256 reputation;
        reputation = solverReputation[addr];

        if (reputation < 6 * factor) {
            reputation += factor;
        } else {
            if (totalProposalRequest > 1000) {
                reputation += (reputation - 6 * factor) / totalProposalRequest;
            } else {
                reputation += (reputation - 6 * factor) / 1000;
            }
        }

        solverReputation[addr] = reputation;
    }

    function createProjectID() public returns (bytes32 projectId) {
        // generate unique project id
        projectId = keccak256(abi.encodePacked(block.timestamp, msg.sender, block.chainid));
        // set project id into mapping
        projectIDs[projectId] = msg.sender;
        // set latest project
        latestProjectID[msg.sender] = projectId;

        emit CreateProjectID(projectId, msg.sender);
    }

    // issue RequestProposal
    // `base64RecParam` should be an encoded base64 ChainRequestParam json string
    // https://github.com/crestalnetwork/crestal-dashboard-backend/blob/testnet-dev/listen/type.go#L9
    // example: {"type":"DA","latency":5,"max_throughput":20,"finality_time":10,"block_time":5,"created_at":"0001-01-01T00:00:00Z"}
    // associated base64 string: eyJ0eXBlIjoiREEiLCJsYXRlbmN5Ijo1LCJtYXhfdGhyb3VnaHB1dCI6MjAsImZpbmFsaXR5X3RpbWUiOjEwLCJibG9ja190aW1lIjo1LCJjcmVhdGVkX2F0IjoiMDAwMS0wMS0wMVQwMDowMDowMFoifQ
    function createProposalRequest(bytes32 projectId, string memory base64RecParam, string memory serverURL)
        public
        returns (bytes32 requestID)
    {
        require(projectIDs[projectId] != address(0), "projectId does not exist");

        require(bytes(serverURL).length > 0, "serverURL is empty");
        require(bytes(base64RecParam).length > 0, "base64RecParam is empty");

        // generate unique hash
        bytes32 messageHash = keccak256(abi.encodePacked(block.timestamp, msg.sender, base64RecParam, block.chainid));

        requestID = messageHash;

        // FIXME: This prevents a msg.sender to create multiple requests at the same time?
        // For different projects, a solver is allowed to create one (latest proposal) for each.
        latestProposalRequestID[msg.sender] = requestID;

        totalProposalRequest++;

        emit RequestProposal(projectId, msg.sender, messageHash, base64RecParam, serverURL);
    }

    // TODO: Merge Private and non-Private calls, as most logic is the same
    function createPrivateProposalRequest(
        bytes32 projectId,
        address privateSolverAddress,
        string memory base64RecParam,
        string memory serverURL
    ) public returns (bytes32 requestID) {
        require(projectIDs[projectId] != address(0), "projectId does not exist");

        require(bytes(serverURL).length > 0, "serverURL is empty");
        require(bytes(base64RecParam).length > 0, "base64RecParam is empty");

        // generate unique hash
        bytes32 messageHash = keccak256(abi.encodePacked(block.timestamp, msg.sender, base64RecParam, block.chainid));

        requestID = messageHash;

        // FIXME: This prevents a msg.sender to create multiple requests at the same time?
        // For different projects, a solver is allowed to create one (latest proposal) for each.
        latestProposalRequestID[msg.sender] = requestID;

        totalProposalRequest++;

        // set request id associated private solver
        requestSolver[requestID] = privateSolverAddress;

        emit RequestPrivateProposal(projectId, msg.sender, privateSolverAddress, messageHash, base64RecParam, serverURL);
    }

    // issue DeploymentRequest
    // `base64Proposal` should be encoded base64 ChainRequestParam json string
    // that was sent in `createProposalRequest` call
    // TODO: Why not just pass in requestID here?
    function createDeploymentRequest(
        bytes32 projectId,
        address solverAddress,
        string memory base64Proposal,
        string memory serverURL
    ) public returns (bytes32 requestID) {
        require(projectIDs[projectId] != address(0), "projectId does not exist");

        require(bytes(serverURL).length > 0, "serverURL is empty");
        require(bytes(base64Proposal).length > 0, "base64Proposal is empty");

        require(solverAddress != address(0), "solverAddress is not valid");

        // generate unique message hash
        bytes32 messageHash = keccak256(abi.encodePacked(block.timestamp, msg.sender, base64Proposal, block.chainid));

        requestID = messageHash;

        latestDeploymentRequestID[msg.sender] = requestID;

        totalDeploymentRequest++;

        // init deployment status, not picked by any worker
        DeploymentStatus memory deploymentStatus;
        deploymentStatus.status = Status.Issued;

        requestDeploymentStatus[requestID] = deploymentStatus;

        // set solver reputation
        setReputation(solverAddress);

        emit RequestDeployment(projectId, msg.sender, solverAddress, messageHash, base64Proposal, serverURL);
    }

    // TODO: Why not just pass in requestID here?
    // TODO: Merge Private and non-Private calls, as most logic is the same
    function createPrivateDeploymentRequest(
        bytes32 projectId,
        address solverAddress,
        address privateWorkerAddress,
        string memory base64Proposal,
        string memory serverURL
    ) public returns (bytes32 requestID) {
        require(projectIDs[projectId] != address(0), "projectId does not exist");

        require(bytes(serverURL).length > 0, "serverURL is empty");
        require(bytes(base64Proposal).length > 0, "base64Proposal is empty");

        require(solverAddress != address(0), "solverAddress is not valid");

        // generate unique message hash
        bytes32 messageHash = keccak256(abi.encodePacked(block.timestamp, msg.sender, base64Proposal, block.chainid));

        requestID = messageHash;

        latestDeploymentRequestID[msg.sender] = requestID;

        totalDeploymentRequest++;

        // set solver reputation
        setReputation(solverAddress);

        // pick up deployment status since this is private deployment request, which can be picked only by refered worker
        DeploymentStatus memory deploymentStatus;
        deploymentStatus.status = Status.Pickup;
        deploymentStatus.deployWorkerAddr = privateWorkerAddress;

        requestDeploymentStatus[requestID] = deploymentStatus;

        emit RequestPrivateDeployment(
            projectId, msg.sender, privateWorkerAddress, solverAddress, messageHash, base64Proposal, serverURL
        );

        // emit accept deployment event since this deployment request is accepted by blueprint
        emit AcceptDeployment(projectId, requestID, privateWorkerAddress);
    }

    function submitProofOfDeployment(bytes32 projectId, bytes32 requestID, string memory proofBase64) public {
        require(projectIDs[projectId] != address(0), "projectId does not exist");

        require(requestID.length > 0, "requestID is empty");
        require(requestDeploymentStatus[requestID].status != Status.Init, "request ID not exit");
        require(requestDeploymentStatus[requestID].deployWorkerAddr == msg.sender, "wrong worker address");

        require(requestDeploymentStatus[requestID].status != Status.GeneratedProof, "already submit proof");

        // set deployment status into generatedProof
        requestDeploymentStatus[requestID].status = Status.GeneratedProof;

        // save deployment proof to mapping
        deploymentProof[requestID] = proofBase64;

        emit GeneratedProofOfDeployment(projectId, requestID, proofBase64);
    }

    function submitDeploymentRequest(bytes32 projectId, bytes32 requestID) public returns (bool isAccepted) {
        require(projectIDs[projectId] != address(0), "projectId does not exist");

        require(requestID.length > 0, "requestID is empty");
        require(requestDeploymentStatus[requestID].status != Status.Init, "requestID does not exist");
        require(
            requestDeploymentStatus[requestID].status != Status.Pickup,
            "requestID already picked by another worker, try a different requestID"
        );

        // currently, do first come, first server, will do a better way in the future
        requestDeploymentStatus[requestID].status = Status.Pickup;
        requestDeploymentStatus[requestID].deployWorkerAddr = msg.sender;

        isAccepted = true;

        emit AcceptDeployment(projectId, requestID, requestDeploymentStatus[requestID].deployWorkerAddr);
    }

    // get latest deployment status
    function getDeploymentStatus(bytes32 requestID) public view returns (Status, address) {
        return (requestDeploymentStatus[requestID].status, requestDeploymentStatus[requestID].deployWorkerAddr);
    }

    // get latest proposal request id
    function getLatestProposalRequestID(address addr) public view returns (bytes32) {
        return latestProposalRequestID[addr];
    }

    // get latest deployment request id
    function getLatestDeploymentRequestID(address addr) public view returns (bytes32) {
        return latestDeploymentRequestID[addr];
    }

    // get latest project id of user
    function getLatestUserProjectID(address addr) public view returns (bytes32) {
        return latestProjectID[addr];
    }
}
