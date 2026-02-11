// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockAnsResolver.sol";
import "./IMockAnsResolver.sol";
import "../interfaces/IOctoDistributor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MockAgenticCompany {
   bytes32[] public employees;
   IMockAnsResolver public ansResolver;
   IOctoDistributor public octoDistributor;
   address public specToken;
   address public usdcToken;


   constructor(address ansResolver_, address _octoDistributor, address _specToken, address _usdcToken) {
       ansResolver = IMockAnsResolver(ansResolver_);
        octoDistributor = IOctoDistributor(_octoDistributor);
        specToken = _specToken;
        usdcToken = _usdcToken;
   }

   function hire(address employee) external {
       bytes32 ansNode = ansResolver.ans(employee);
       employees.push(ansNode);
   }

   function fire(address employee) external {
       bytes32 ansNode = ansResolver.ans(employee);
       for (uint256 i = 0; i < employees.length; i++) {
           if (employees[i] == ansNode) {
               employees[i] = employees[employees.length - 1];
               employees.pop();
               break;
           }
       }
   }

   function distributeHiringBonus(uint256 totalSpec, uint256 totalUsdc, address agentToken, uint256 totalAgentTokens) external {
        uint256 usdcPerEmployee = totalUsdc / employees.length;
        uint256 specPerEmployee = totalSpec / employees.length;
        uint256 agentTokenPerEmployee = totalAgentTokens / employees.length;
        IERC20(specToken).approve(address(octoDistributor), totalSpec);
        IERC20(usdcToken).approve(address(octoDistributor), totalUsdc);
        IERC20(agentToken).approve(address(octoDistributor), totalAgentTokens);
        IOctoDistributor.HiringDistribution[] memory distributions = new IOctoDistributor.HiringDistribution[](employees.length);
       for (uint256 i = 0; i < employees.length; i++) {
              distributions[i] = IOctoDistributor.HiringDistribution({
                recipientAnsNode: employees[i],
                specAmount: specPerEmployee,
                agentTokenAmount: agentTokenPerEmployee,
                usdcAmount: usdcPerEmployee
                });
       }
       octoDistributor.transferHiringDistributions(
                distributions,
                agentToken,
                totalSpec,
                totalAgentTokens,
                totalUsdc
              );
   }

   function getAllEmployees() external view returns (bytes32[] memory) {
       return employees;
   }

   function getEmployeeAtIndex(uint256 index) external view returns (bytes32) {
       require(index < employees.length, "Invalid index");
       return employees[index];
   }

   function employeeCount() external view returns (uint256) {
       return employees.length;
   }
}