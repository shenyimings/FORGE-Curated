// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IAgenticCompany is IERC165 {
    enum JobStatus {
        NONEXISTENT,
        OPEN,
        FILLED,
        VACATED,
        CANCELLED
    }

    enum JobApplicationStatus {
        NONEXISTENT,
        APPLIED,
        REJECTED,
        HIRED,
        WITHDRAWN
    }

    struct Job {
        bytes32 id;
        uint48 createdAt;
        JobStatus status;
        uint256 hiringBonusSpectral;
        uint256 hiringBonusAgentToken;
        uint256 hiringBonusUsdc;
        bytes32 employeeAnsNode;
        string jobName;
    }

    struct JobApplication {
        bytes32 id;
        bytes32 jobId;
        uint48 createdAt;
        bytes32 applicantAnsNode;
        JobApplicationStatus status;
    }

    event FundsWithdrawn(address indexed to, uint256 spectralAmount, uint256 agentTokenAmount, uint256 usdcAmount);
    event CompanyDissolved();
    event EmployeeFired(bytes32 indexed jobId, bytes32 indexed employeeAnsNode);
    event JobCreated(bytes32 indexed jobId);
    event JobCancelled(bytes32 indexed jobId);
    event HiringBonusesDeposited(bytes32 indexed jobId, uint256 spectralAmount, uint256 agentTokenAmount, uint256 usdcAmount);
    event InterviewFeeReceived(bytes32 indexed jobApplicationId, bytes32 indexed jobId, bytes32 indexed applicantAnsNode, uint256 amount);
    event JobApplicantHired(bytes32 indexed jobApplicationId, bytes32 indexed jobId, bytes32 indexed applicantAnsNode, bytes32[] shortlistAnsNodes);
    event JobApplicantRejected(bytes32 indexed jobApplicationId, bytes32 indexed jobId, bytes32 indexed applicantAnsNode);
    event JobApplicationCreated(bytes32 indexed jobApplicationId, bytes32 indexed jobId, bytes32 indexed applicantAnsNode);
    event JobApplicationWithdrawn(bytes32 indexed jobApplicationId, bytes32 indexed jobId, bytes32 indexed applicantAnsNode);
    
    error CompanyIsDissolved();
    error JobNameTooShort();
    error JobDoesNotExist(bytes32 jobId);
    error JobNotFilled(bytes32 jobId);
    error JobNotOpen(bytes32 jobId);
    error JobNotOpenOrVacated(bytes32 jobId);
    error JobApplicationNotApplied(bytes32 jobApplicationId, bytes32 jobId);
    error JobApplicationAlreadyExists(bytes32 jobApplicationId, bytes32 jobId);
    error OnlyJobApplicant(bytes32 jobApplicationId, bytes32 jobId, bytes32 applicantAnsNode);
    error SpectralTransferFailed(address from, address to, uint256 amount);
    error AgentTokenTransferFailed(address from, address to, uint256 amount);
    error UsdcTransferFailed(address from, address to, uint256 amount);
    error AnsNodeMustResolveToAddress(bytes32 ansNode);
    error AddressMustResolveToAnsName(address addr);
    error ApplicantHasActiveApplication(bytes32 jobApplicationId, bytes32 jobId, bytes32 applicantAnsNode);
    error ApplicantAlreadyEmployed(bytes32 jobId, bytes32 applicantAnsNode);
    error IndexOutOfBounds();
    error JobIdCollision(bytes32 jobId);
    error EmployeeNotFound();

    function initialize(
        address initialAdmin,
        address agentToken,
        string calldata companyName
    ) external;

    function withdrawAll(address to) external;
    function dissolveCompany() external;
    function withdrawableSpectral() external view returns (uint256 spectral_);
    function withdrawableAgentToken() external view returns (uint256 agentToken_);
    function withdrawableUsdc() external view returns (uint256 usdc_);
    function isDissolved() external view returns (bool dissolved_);
    function COMPANY_NAME() external view returns (string memory name_);
    function FOUNDED_AT() external view returns (uint48 timestamp_);

    function createJob(string calldata jobName) external returns (bytes32 jobId_);
    function cancelJob(bytes32 jobId) external;
    function fireEmployee(bytes32 jobId) external;
    function getJob(bytes32 jobId) external view returns (Job memory job_);
    function jobCount() external view returns (uint256 count_);

    function applyToJob(bytes32 jobId) external returns (bytes32 jobApplicationId_);
    function applyToJobOnBehalfOf(bytes32 jobId, bytes32 applicantAnsNode) external returns (bytes32 jobApplicationId_);
    function withdrawJobApplication(bytes32 jobApplicationId) external;
    function rejectApplicant(bytes32 jobApplicationId) external;
    function hireApplicant(bytes32 jobApplicationId, bytes32[] calldata shortlistAnsNodes) external;
    function depositHiringBonuses(bytes32 jobId, uint256 spectralAmount, uint256 agentTokenAmount, uint256 usdcAmount) external;
    function debitInterviewFee(bytes32 jobApplicationId, uint256 amount) external;
    function getJobAtIndex(uint256 index) external view returns (bytes32 jobId_);
    function getJobApplication(bytes32 jobApplicationId) external view returns (JobApplication memory application_);
    function getJobApplicationCount(bytes32 jobId) external view returns (uint256 count_);
    function getJobApplicationIds(bytes32 jobId) external view returns (bytes32[] memory ids_);
    function getJobApplicationIdAtIndex(bytes32 jobId, uint256 index) external view returns (bytes32 id_);
    function getUserActiveJobApplicationId(bytes32 jobId, bytes32 applicantAnsNode) external view returns (bytes32 id_);
    function employeeCount() external view returns (uint256 count_);
    function getEmployeeAtIndex(uint256 index) external view returns (bytes32 employeeAnsNode_);
    function getEmployeeCurrentJob(bytes32 employeeAnsNode) external view returns (bytes32 jobId_);
}