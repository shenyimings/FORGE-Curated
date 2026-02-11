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

    // keep old variable in order so that it can be compatible with old contract

    // new variable and struct
    struct Project {
        bytes32 id;
        bytes32 requestProposalID;
        bytes32 requestDeploymentID;
        address proposedSolverAddr;
    }

    address public constant dummyAddress = address(0);

    // project map
    mapping(bytes32 => Project) private projects;

    mapping(bytes32 => bytes32[]) public deploymentIdList;

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

    event UpdateDeploymentConfig(
        bytes32 indexed projectID, bytes32 indexed requestID, address workerAddress, string base64Config
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

    function setProjectId(bytes32 projectId) internal {
        // check project id
        require(projects[projectId].id == 0, "projectId already exists");

        Project memory project;
        project.id = projectId;
        // set project info into mapping
        projects[projectId] = project;

        // set latest project
        latestProjectID[msg.sender] = projectId;

        emit CreateProjectID(projectId, msg.sender);
    }

    function createProjectID() public returns (bytes32 projectId) {
        // generate unique project id
        projectId = keccak256(abi.encodePacked(block.timestamp, msg.sender, block.chainid));

        setProjectId(projectId);
    }

    function upgradeProject(bytes32 projectId) public {
        // check project id
        require(projects[projectId].id != 0 || projectIDs[projectId] != address(0), "projectId does not exist");
        // reset project info
        projects[projectId].requestProposalID = 0;

        projects[projectId].requestDeploymentID = 0;

        projects[projectId].proposedSolverAddr = dummyAddress;
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
        requestID = proposalRequest(projectId, dummyAddress, base64RecParam, serverURL);

        emit RequestProposal(projectId, msg.sender, requestID, base64RecParam, serverURL);
    }

    function createPrivateProposalRequest(
        bytes32 projectId,
        address privateSolverAddress,
        string memory base64RecParam,
        string memory serverURL
    ) public returns (bytes32 requestID) {
        requestID = proposalRequest(projectId, privateSolverAddress, base64RecParam, serverURL);

        emit RequestPrivateProposal(projectId, msg.sender, privateSolverAddress, requestID, base64RecParam, serverURL);
    }

    function createProjectIDAndProposalRequest(bytes32 projectId, string memory base64RecParam, string memory serverURL)
        public
        returns (bytes32 requestID)
    {
        // set project id
        setProjectId(projectId);
        // create proposal request
        requestID = createProposalRequest(projectId, base64RecParam, serverURL);
    }

    function proposalRequest(
        bytes32 projectId,
        address solverAddress,
        string memory base64RecParam,
        string memory serverURL
    ) internal returns (bytes32 requestID) {
        // check project id
        //    projects[projectId].id != 0 --> false --> new project id created by new blueprint not exit
        //    projectIDs[projectId] != address(0) -- > false -- >. old project id created by old blueprint not exit.
        //    both 1 and 2 are false, then project id does not exit in old and new blueprint
        require(projects[projectId].id != 0 || projectIDs[projectId] != address(0), "projectId does not exist");

        require(bytes(serverURL).length > 0, "serverURL is empty");
        require(bytes(base64RecParam).length > 0, "base64RecParam is empty");

        // generate unique hash
        requestID = keccak256(abi.encodePacked(block.timestamp, msg.sender, base64RecParam, block.chainid));

        // check request id is created or not
        // if it is created, then we need to lock it, not allow user to trigger proposal request again
        require(projects[projectId].requestProposalID == 0, "proposal requestID already exists");

        // FIXME: This prevents a msg.sender to create multiple requests at the same time?
        // For different projects, a solver is allowed to create one (latest proposal) for each.
        latestProposalRequestID[msg.sender] = requestID;

        projects[projectId].requestProposalID = requestID;

        totalProposalRequest++;

        // set request id associated private solver
        if (solverAddress != address(0)) {
            // private proposal request
            requestSolver[requestID] = solverAddress;
        }

        return requestID;
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
    ) public returns (bytes32) {
        require(solverAddress != address(0), "solverAddress is not valid");

        (bytes32 requestID, bytes32 projectDeploymentId) =
            deploymentRequest(projectId, solverAddress, dummyAddress, base64Proposal, serverURL, 0);

        // once we got request deploymentID, then we set project requestDeploymentID, which points to a list of deploymentID
        projects[projectId].requestDeploymentID = projectDeploymentId;

        // push request deploymentID into map, link to a project
        deploymentIdList[projectDeploymentId].push(requestID);

        emit RequestDeployment(projectId, msg.sender, solverAddress, requestID, base64Proposal, serverURL);

        return requestID;
    }

    function createMultipleDeploymentRequest(
        bytes32 projectId,
        address solverAddress,
        string[] memory base64Proposals,
        string memory serverURL
    ) public returns (bytes32) {
        require(solverAddress != address(0), "solverAddress is not valid");
        require(base64Proposals.length != 0, "base64Proposals array is empty");

        bytes32 projectDeploymentID;

        for (uint256 i = 0; i < base64Proposals.length; ++i) {
            (bytes32 requestID, bytes32 projectDeploymentId) =
                deploymentRequest(projectId, solverAddress, dummyAddress, base64Proposals[i], serverURL, i);

            if (projectDeploymentID != 0) {
                deploymentIdList[projectDeploymentID].push(requestID);
            } else {
                // push request deploymentID into map, link to a project
                projectDeploymentID = projectDeploymentId;
                deploymentIdList[projectDeploymentID].push(requestID);
            }

            emit RequestDeployment(projectId, msg.sender, solverAddress, requestID, base64Proposals[i], serverURL);
        }

        // once we got request deploymentID, then we set project requestDeploymentID, which points to a list of deploymentID
        projects[projectId].requestDeploymentID = projectDeploymentID;

        return projectDeploymentID;
    }

    function createPrivateDeploymentRequest(
        bytes32 projectId,
        address solverAddress,
        address privateWorkerAddress,
        string memory base64Proposal,
        string memory serverURL
    ) public returns (bytes32) {
        require(solverAddress != address(0), "solverAddress is not valid");

        (bytes32 requestID, bytes32 projectDeploymentId) =
            deploymentRequest(projectId, solverAddress, privateWorkerAddress, base64Proposal, serverURL, 0);

        // once we got request deploymentID, then we set project requestDeploymentID, which points to a list of deploymentID
        projects[projectId].requestDeploymentID = projectDeploymentId;

        // push request deploymentID into map, link to a project
        deploymentIdList[projectDeploymentId].push(requestID);

        emit RequestPrivateDeployment(
            projectId, msg.sender, privateWorkerAddress, solverAddress, requestID, base64Proposal, serverURL
        );

        // emit accept deployment event since this deployment request is accepted by blueprint
        emit AcceptDeployment(projectId, requestID, privateWorkerAddress);

        return requestID;
    }

    function createMultiplePrivateDeploymentRequest(
        bytes32 projectId,
        address solverAddress,
        address privateWorkerAddress,
        string[] memory base64Proposals,
        string memory serverURL
    ) public returns (bytes32) {
        require(solverAddress != address(0), "solverAddress is not valid");
        require(base64Proposals.length != 0, "base64Proposals array is empty");

        bytes32 projectDeploymentID;

        for (uint256 i = 0; i < base64Proposals.length; ++i) {
            (bytes32 requestID, bytes32 projectDeploymentId) =
                deploymentRequest(projectId, solverAddress, privateWorkerAddress, base64Proposals[i], serverURL, i);

            if (projectDeploymentID != 0) {
                deploymentIdList[projectDeploymentID].push(requestID);
            } else {
                projectDeploymentID = projectDeploymentId;
                // push request deploymentID into map, link to a project
                deploymentIdList[projectDeploymentID].push(requestID);
            }

            emit RequestDeployment(projectId, msg.sender, solverAddress, requestID, base64Proposals[i], serverURL);

            // emit accept deployment event since this deployment request is accepted by blueprint
            emit AcceptDeployment(projectId, requestID, privateWorkerAddress);
        }

        // once we got request deploymentID, then we set project requestDeploymentID, which points to a list of deploymentID
        projects[projectId].requestDeploymentID = projectDeploymentID;

        return projectDeploymentID;
    }

    function deploymentRequest(
        bytes32 projectId,
        address solverAddress,
        address workerAddress,
        string memory base64Proposal,
        string memory serverURL,
        uint256 index
    ) internal returns (bytes32 requestID, bytes32 projectDeploymentId) {
        // projectId backwards compatibility
        require(projects[projectId].id != 0 || projectIDs[projectId] != address(0), "projectId does not exist");

        require(bytes(serverURL).length > 0, "serverURL is empty");
        require(bytes(base64Proposal).length > 0, "base64Proposal is empty");

        // generate project used deployment id that linked to many deploymentsID associated with different service id
        projectDeploymentId =
            keccak256(abi.encodePacked(block.timestamp, msg.sender, base64Proposal, block.chainid, projectId));

        // check projectDeploymentId id is created or not
        // if it is created, which means project is start deployment process, should lock
        require(projects[projectId].requestDeploymentID == 0, "deployment requestID already exists");

        // generate unique deployment requestID message hash
        requestID = keccak256(abi.encodePacked(block.timestamp, msg.sender, base64Proposal, block.chainid, index));

        latestDeploymentRequestID[msg.sender] = requestID;

        totalDeploymentRequest++;

        // set solver reputation
        setReputation(solverAddress);

        DeploymentStatus memory deploymentStatus;
        if (workerAddress == address(0)) {
            // init deployment status, not picked by any worker
            deploymentStatus.status = Status.Issued;

            requestDeploymentStatus[requestID] = deploymentStatus;
        } else {
            // private deployment request
            // set pick up deployment status since this is private deployment request, which can be picked only by designated worker
            deploymentStatus.status = Status.Pickup;
            deploymentStatus.deployWorkerAddr = workerAddress;

            requestDeploymentStatus[requestID] = deploymentStatus;
        }

        // update project solver info
        projects[projectId].proposedSolverAddr = solverAddress;

        return (requestID, projectDeploymentId);
    }

    function createProjectIDAndDeploymentRequest(
        bytes32 projectId,
        string memory base64Proposal,
        string memory serverURL
    ) public returns (bytes32) {
        // set project id
        setProjectId(projectId);

        // create deployment request without solver recommendation, so leave solver address as dummyAddress
        // since this is public deployment request leave worker address as dummyAddress
        (bytes32 requestID, bytes32 projectDeploymentId) =
            deploymentRequest(projectId, dummyAddress, dummyAddress, base64Proposal, serverURL, 0);

        projects[projectId].requestDeploymentID = projectDeploymentId;

        deploymentIdList[projectDeploymentId].push(requestID);

        emit RequestDeployment(projectId, msg.sender, dummyAddress, requestID, base64Proposal, serverURL);

        return requestID;
    }

    function createProjectIDAndPrivateDeploymentRequest(
        bytes32 projectId,
        string memory base64Proposal,
        address privateWorkerAddress,
        string memory serverURL
    ) public returns (bytes32) {
        // set project id
        setProjectId(projectId);

        // create deployment request without solver recommendation, so leave solver address as dummyAddress
        // since this is public deployment request leave worker address as dummyAddress
        (bytes32 requestID, bytes32 projectDeploymentId) =
            deploymentRequest(projectId, dummyAddress, privateWorkerAddress, base64Proposal, serverURL, 0);

        projects[projectId].requestDeploymentID = projectDeploymentId;

        deploymentIdList[projectDeploymentId].push(requestID);

        emit RequestDeployment(projectId, msg.sender, dummyAddress, requestID, base64Proposal, serverURL);

        // emit accept deployment event since this deployment request is accepted by blueprint
        emit AcceptDeployment(projectId, requestID, privateWorkerAddress);

        return requestID;
    }

    function submitProofOfDeployment(bytes32 projectId, bytes32 requestID, string memory proofBase64) public {
        // projectId backwards compatibility
        require(projects[projectId].id != 0 || projectIDs[projectId] != address(0), "projectId does not exist");

        require(requestID.length > 0, "requestID is empty");
        require(requestDeploymentStatus[requestID].status != Status.Init, "requestID not exit");
        require(requestDeploymentStatus[requestID].deployWorkerAddr == msg.sender, "wrong worker address");

        require(requestDeploymentStatus[requestID].status != Status.GeneratedProof, "already submit proof");

        // set deployment status into generatedProof
        requestDeploymentStatus[requestID].status = Status.GeneratedProof;

        // save deployment proof to mapping
        deploymentProof[requestID] = proofBase64;

        emit GeneratedProofOfDeployment(projectId, requestID, proofBase64);
    }

    function submitDeploymentRequest(bytes32 projectId, bytes32 requestID) public returns (bool isAccepted) {
        // projectId backwards compatibility
        require(projects[projectId].id != 0 || projectIDs[projectId] != address(0), "projectId does not exist");

        require(requestID.length > 0, "requestID is empty");
        require(requestDeploymentStatus[requestID].status != Status.Init, "requestID does not exist");
        require(
            requestDeploymentStatus[requestID].status != Status.Pickup,
            "requestID already picked by another worker, try a different requestID"
        );

        require(
            requestDeploymentStatus[requestID].status != Status.GeneratedProof, "requestID has already submitted proof"
        );

        // currently, do first come, first server, will do a better way in the future
        requestDeploymentStatus[requestID].status = Status.Pickup;
        requestDeploymentStatus[requestID].deployWorkerAddr = msg.sender;

        // set project deployed worker address
        isAccepted = true;

        emit AcceptDeployment(projectId, requestID, requestDeploymentStatus[requestID].deployWorkerAddr);
    }

    function UpdateWorkerDeploymentConfig(bytes32 projectId, bytes32 requestID, string memory updatedBase64Config)
        public
    {
        // projectId backwards compatibility
        require(projects[projectId].id != 0 || projectIDs[projectId] != address(0), "projectId does not exist");

        require(requestDeploymentStatus[requestID].status != Status.Init, "requestID not exit");

        require(bytes(updatedBase64Config).length > 0, "updatedBase64Config is empty");

        require(requestDeploymentStatus[requestID].status != Status.Issued, "requestID is not picked up by any worker");

        // reset status if it is generated proof
        if (requestDeploymentStatus[requestID].status == Status.GeneratedProof) {
            requestDeploymentStatus[requestID].status = Status.Pickup;
        }

        emit UpdateDeploymentConfig(
            projectId, requestID, requestDeploymentStatus[requestID].deployWorkerAddr, updatedBase64Config
        );
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

    // get project info
    function getProjectInfo(bytes32 projectId) public view returns (address, bytes32, bytes32[] memory) {
        // only new upgrade blueprint use this function
        require(projects[projectId].id != 0, "projectId does not exist");
        bytes32[] memory requestDeploymentIDs = deploymentIdList[projects[projectId].requestDeploymentID];

        return (projects[projectId].proposedSolverAddr, projects[projectId].requestProposalID, requestDeploymentIDs);
    }

    function getDeploymentProof(bytes32 requestID) public view returns (string memory) {
        return deploymentProof[requestID];
    }
}
