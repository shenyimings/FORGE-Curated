pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ManagerStore is Ownable {
    struct Manager {
        address managerAddress;
        string ipfsHash;
        bool isAuthorized;
    }

    mapping(address => Manager) public managersMap;
    address[] public authorizedManagers;
    address[] public allManagers;

    event ManagerRegistered(address indexed managerAddress, string ipfsHash);
    event ManagerAuthorized(address indexed managerAddress);
    event ManagerRemoved(address indexed managerAddress);

    constructor() Ownable(msg.sender) {}

    function registerManager(string memory ipfsHash) public {
        if (managersMap[msg.sender].managerAddress != msg.sender) {
            allManagers.push(msg.sender);
        } else if (managersMap[msg.sender].isAuthorized == true) {
            // remove manager from authorizedManagers list if it is already authorized
            _deauthorizeManager(msg.sender);
        }
        managersMap[msg.sender] = Manager(msg.sender, ipfsHash, false);

        emit ManagerRegistered(msg.sender, ipfsHash);
    }

    function authorizeManager(address managerAddress) public onlyOwner {
        require(managerAddress != address(0), "Invalid manager address");
        require(!managersMap[managerAddress].isAuthorized, "Manager already authorized");

        managersMap[managerAddress].isAuthorized = true;
        authorizedManagers.push(managerAddress);

        emit ManagerAuthorized(managerAddress);
    }

    function deauthorizeManager(address managerAddress) public onlyOwner {
        require(managerAddress != address(0), "Invalid manager address");
        require(managersMap[managerAddress].isAuthorized, "Manager not authorized");
        _deauthorizeManager(managerAddress);
    }

    function _deauthorizeManager(address managerAddress) private {
        managersMap[managerAddress].isAuthorized = false;

        for (uint256 i = 0; i < authorizedManagers.length; i++) {
            if (authorizedManagers[i] == managerAddress) {
                authorizedManagers[i] = authorizedManagers[authorizedManagers.length - 1];
                authorizedManagers.pop();
                break;
            }
        }

        emit ManagerRemoved(managerAddress);
    }

    function getAllAuthorizedManagersWithHashes() public view returns (Manager[] memory) {
        uint256 authorizedCount = authorizedManagers.length;
        Manager[] memory result = new Manager[](authorizedCount);

        for (uint256 i = 0; i < authorizedCount; i++) {
            result[i] = managersMap[authorizedManagers[i]];
        }

        return result;
    }

    function getAllManagersWithHashes() public view returns (Manager[] memory) {
        uint256 allCount = allManagers.length;
        Manager[] memory result = new Manager[](allCount);

        for (uint256 i = 0; i < allCount; i++) {
            result[i] = managersMap[allManagers[i]];
        }

        return result;
    }

    function getAllManagers() public view returns (address[] memory) {
        return allManagers;
    }

    function getAllAuthorizedManagers() public view returns (address[] memory) {
        return authorizedManagers;
    }
}
