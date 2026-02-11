// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ChainCfg {
    struct Config {
        string key;
        string value;
    }

    struct ConfigCheckpoint {
        uint64 blockNum;
        uint64 effectiveBlockNum;
        Config[] configs;
    }


    ConfigCheckpoint[] configCps;

    event ConfigUpdate(uint64 indexed blockNum, uint64 indexed effectiveBlockNum, string[] keys, string[] values);
    
    address public rootSys;
    address public constant sysStaking = 0x4100000000000000000000000000000000000000;
    address public constant intrinsicSys = 0x1111111111111111111111111111111111111111;

    constructor() {
    }

    modifier onlyOwner() {
        require(msg.sender == rootSys || msg.sender == sysStaking || msg.sender == intrinsicSys, "Not owner");
        _;
    }

    function changeSys(address _newOwner)
        public
        onlyOwner
    {
        rootSys = _newOwner;
    }

    function get_config(string memory key) public view returns (string memory) {
        if (configCps.length != 0) {
            for (uint256 i = 0; i < configCps[configCps.length - 1].configs.length; i++) {
                Config storage conf = configCps[configCps.length - 1].configs[i];
                if (keccak256(abi.encodePacked(key)) == keccak256(abi.encodePacked(conf.key))) {
                    return conf.value;
                }
            }
        }
        return "";
    }

    function get_configs() public view returns (Config[] memory) {
        if (configCps.length != 0) {
            return configCps[configCps.length - 1].configs;
        }
        Config[] memory configs;
        return configs;
    }

    function set_config(string[] memory keys, string[] memory values) external onlyOwner {
        require(keys.length == values.length, "KVs are not match");
        if (configCps.length == 3) {
            delete configCps[0];
            for (uint256 i = 1; i < configCps.length; i++) {
                configCps[i - 1] = configCps[i];
            }
            configCps.pop(); 
        }

        uint256 old_config_cps_number = configCps.length;

        ConfigCheckpoint storage cfgCp = configCps.push();
        cfgCp.blockNum = uint64(block.number);
        cfgCp.effectiveBlockNum = uint64(block.number + 1);

        if (old_config_cps_number != 0) {
            require(configCps[configCps.length - 2].effectiveBlockNum <= block.number, "INVALID_STATE");

            for (uint256 i = 0; i < configCps[configCps.length - 2].configs.length; i++) {
                Config storage conf = configCps[configCps.length - 2].configs[i];
                bool found = false;
                for (uint256 j = 0; j < keys.length; j++) {
                    if (keccak256(abi.encodePacked(conf.key)) == keccak256(abi.encodePacked(keys[j]))) {
                        found = true; 
                        break;
                    }
                }
                if (!found) {
                    cfgCp.configs.push(Config({
                        key: conf.key,
                        value: conf.value
                    }));
                }
            }
        }

        for (uint256 i = 0; i < keys.length; i++) {
            cfgCp.configs.push(Config({
                key: keys[i],
                value: values[i]
            }));
        }

        emit ConfigUpdate(uint64(block.number), uint64(block.number + 1), keys, values);
    }
}