
pragma solidity ^0.8.20;


contract InferRuleManager {

    enum CreateMethod { Create, Create2 }
    enum RuleState { INIT, UPDATED, IN_PROVING, PROVING_SUCCESS, PROVING_FAILURE, IN_USE}

    struct InferRule {
        uint64 id_;                 // unque id for InferRule
        bytes4 selctor_;            // filter: selctor
        address contract_;          // filter: contract

        bytes32 metahash_;          // filter: metadata_hash https://solidity-cn.readthedocs.io/zh/develop/metadata.html#id2

        address adder_;             // rule adder address
        uint32 type_;               // see: infer type define
        uint32 prove_threshold_;    // rule state change threshold of verified txs
        RuleState state_;           // 0=INIT,1=UPDATED,2=IN_PROVING,3=PROVING_SUCCESS,4=PROVING_FAILURE,5=IN_USE

        bytes code_;                // user defined infer rule
    }

    // slot 0
    mapping(uint64 => InferRule) private rules_;
    // slot 1
    mapping(address => uint64 []) private contract_rules_;
    // slot 2
    uint64 [] private active_ids_;
    // slot 3
    uint64 [] private wait_prove_rules_;
    // slot 4
    uint64 [] private success_rules_;

    // slot 5
    address private administrator_;
    uint64 private next_id_;
    uint32 private prove_threshold_; // Number of verified transactions required for rule from IN_PROVING to PROVING_SUCCESS

    // grantees were grant admin permission
    address [] private grantees_;

    constructor(uint32 _prove_threshold) {
        administrator_ = msg.sender;
        next_id_ = 1;
        prove_threshold_ = _prove_threshold;
    }

    function checkExist(address _addr, bytes4 _selector, bytes32 _metahash) private view returns(bool) {
        require(_addr != address(0) || _metahash != bytes32(0), "InferRule address AND metahash is 0.");
        if (contract_rules_[_addr].length == 0) {
            return false;
        }
        for (uint64 i = 0; i < contract_rules_[_addr].length; ++i) {
            if (rules_[contract_rules_[_addr][i]].selctor_ == _selector) {
                return true;
            }
        }
        return false;
    }

    function checkExist(uint64 _id) private view returns(bool) {
        if (rules_[_id].id_ == uint64(0)) {
            return false;
        }
        return true;
    }

    function checkSuperPermission(address _addr) private view returns(bool) {
        if (_addr == administrator_ || _addr == address(0)) {
            return true;
        }

        return false;
    }

    function checkGrantPermission(address _addr) private view returns(bool) {
        for (uint256 i = 0; i < grantees_.length; i++) {
            if (grantees_[i] == _addr) {
                return true;
            }
        }

        return false;
    }


    function checkAdminPermission(address _addr) private view returns(bool) {
        if (checkSuperPermission(_addr) || checkGrantPermission(_addr)) {
            return true;
        }

        return false;
    }

    function checkPermission(bytes32 _metahash) private view returns(bool) {
        if (checkAdminPermission(msg.sender)) {
            return true;
        }
        if (_metahash != bytes32(0)) {
            return false;
        }

        return false;
    }

    function checkPermission(address _adder) private view returns(bool) {
        if (checkAdminPermission(msg.sender) || msg.sender == _adder) {
            return true;
        }

        return false;
    }

    event RuleAdded(
        address from_,
        uint64 id_,
        uint32 type_,
        uint32 prove_threshold_,
        RuleState state_,
        address contract_,
        bytes4 selctor_,
        bytes32 metahash_,
        bytes code_
    );

    function addRule(uint32 _type, address _addr, bytes4 _selector, bytes32 _metahash, bytes calldata _code) public returns (uint64) {
        require(checkPermission(_metahash), "Permission denied: Only chairpersons can add rule.");
        require(!checkExist(_addr, _selector, _metahash), "InferRule already exist");

        uint64 _id = next_id_++;

        rules_[_id] = InferRule(_id, _selector, _addr, _metahash, msg.sender, _type, prove_threshold_, RuleState.INIT, _code);

        active_ids_.push(_id);
        contract_rules_[_addr].push(_id);

        // update to wait_prove_rules_
        wait_prove_rules_.push(_id);

        emit RuleAdded(msg.sender, _id, _type, prove_threshold_, RuleState.INIT, _addr, _selector, _metahash, _code);
        return _id;
    }

    event RuleUpdated(
        address from_,
        uint64 id_,
        uint32 type_,
        uint32 prove_threshold_,
        RuleState state_,
        address contract_,
        bytes4 selctor_,
        bytes32 metahash_,
        bytes code_
    );

    function updateRule(uint64 _id, uint32 _type, address _addr, bytes4 _selector, bytes32 _metahash, bytes calldata _code) public returns (uint64) {
        require(checkExist(_id), "InferRule not exist");
        require(checkPermission(rules_[_id].adder_), "Permission denied: Only chairpersons can update rule.");
        require((rules_[_id].contract_ == _addr) && (rules_[_id].selctor_ == _selector) && (rules_[_id].metahash_ == _metahash), "Can't update rule filters");

        rules_[_id].type_ = _type;
        rules_[_id].code_ = _code;
        rules_[_id].state_ = RuleState.UPDATED;

        // update to wait_prove_rules_
        bool contain = false;
        for (uint256 i = 0; i < wait_prove_rules_.length; i++) {
            if (wait_prove_rules_[i] == _id) {
                contain = true;
                break;
            }
        }
        if (!contain) {
            wait_prove_rules_.push(_id);
        }

        // clear success_rules_ ids
        for (uint256 i = 0; i < success_rules_.length; i++) {
            if (success_rules_[i] == _id) {
                success_rules_[i] = success_rules_[success_rules_.length - 1];
                success_rules_.pop();
                break;
            }
        }

        emit RuleUpdated(msg.sender, _id, _type, prove_threshold_, rules_[_id].state_, _addr, _selector, _metahash, _code);
        return _id;
    }

    event RuleDeleted(
        address from_,
        uint64 id_
    );
    function delRule(uint64 _id) public {
        require(checkExist(_id), "InferRule not exist");
        require(checkPermission(rules_[_id].adder_), "Permission denied: Only chairpersons can delete rule.");

        InferRule memory rule = rules_[_id];
        uint64[] storage contract_ids = contract_rules_[rule.contract_];

        // clear contract index ids
        for (uint i = 0; i < contract_ids.length; ++i) {
            if (contract_ids[i] == _id) {
                contract_ids[i] = contract_ids[contract_ids.length - 1];
                contract_ids.pop();
                break;
            }
        }
        if (contract_ids.length == 0) {
            delete contract_rules_[rule.contract_];
        }

        // clear active_ids ids
        for (uint256 i = 0; i < active_ids_.length; i++) {
            if (active_ids_[i] == _id) {
                active_ids_[i] = active_ids_[active_ids_.length - 1];
                active_ids_.pop();
                break;
            }
        }
        // clear wait_prove_rules_
        for (uint i = 0; i < wait_prove_rules_.length; ++i) {
            if (wait_prove_rules_[i] == _id) {
                wait_prove_rules_[i] = wait_prove_rules_[wait_prove_rules_.length - 1];
                wait_prove_rules_.pop();
                break;
            }
        }
        // clear success_rules_ ids
        for (uint256 i = 0; i < success_rules_.length; i++) {
            if (success_rules_[i] == _id) {
                success_rules_[i] = success_rules_[success_rules_.length - 1];
                success_rules_.pop();
                break;
            }
        }

        delete rules_[_id];
        emit RuleDeleted(msg.sender, _id);
    }

    // return all register rules
    function getAllRules() public view returns (InferRule[] memory) {
        uint256 count = active_ids_.length;
        InferRule[] memory allRules = new InferRule[](count);
        uint64 index = 0;

        for (uint256 i = 0; i < count; i++) {
            uint64 id = active_ids_[i];
            if (rules_[id].id_ != 0) {
                allRules[index] = rules_[id];
                index++;
            }
        }

        return allRules;
    }

    // return next_id_
    function getNextId() public view returns (uint64) {
        return next_id_;
    }

    // return spec contract register rules
    function getContractRules(address _addr) public view returns (InferRule[] memory) {
        uint64[] storage ids = contract_rules_[_addr];
        InferRule[] memory contractSpecificRules = new InferRule[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            contractSpecificRules[i] = rules_[ids[i]];
        }
        return contractSpecificRules;
    }

    event ProvingResultUpdated  (
        address from_,
        uint64[] success_ids_,
        uint64[] fail_ids_
    );

    function updateProvingResult(uint64[] calldata _success_ids, uint64[] calldata _fail_ids) public {
        require(checkAdminPermission(msg.sender), "Only administrator can execute this.");

        // update success rule state
        for (uint256 i = 0; i < _success_ids.length; i++) {
            uint64 id = _success_ids[i];
            require(checkExist(id), "InferRule not exist");

            InferRule storage rule = rules_[id];
            require(rule.state_ == RuleState.IN_PROVING, "Invalid state transition");
            rule.state_ = RuleState.PROVING_SUCCESS;

            // add to success list, and will change to IN_USE next epoch
            success_rules_.push(id);
        }

        // update fails rule state
        for (uint256 i = 0; i < _fail_ids.length; i++) {
            uint64 id = _fail_ids[i];
            require(checkExist(id), "InferRule not exist");

            InferRule storage rule = rules_[id];
            require(rule.state_ == RuleState.IN_PROVING, "Invalid state transition");
            rule.state_ = RuleState.PROVING_FAILURE;
        }

        emit ProvingResultUpdated(msg.sender, _success_ids, _fail_ids);
    }

    event RuleInProving(
        uint64[] ids_
    );
    event RuleInUse  (
        uint64[] ids_
    );
    function advanceEpoch() external {
        require(checkSuperPermission(msg.sender), "Permission denied");
        uint64[] memory wait_prove_ids = new uint64[](wait_prove_rules_.length);
        uint256 count = 0;
        for (uint256 i = 0; i < wait_prove_rules_.length; i++) {
            uint64 id = wait_prove_rules_[i];
            if (checkExist(id)) {
                InferRule storage rule = rules_[id];
                if (rule.state_ == RuleState.INIT || rule.state_ == RuleState.UPDATED) {
                    rule.state_ = RuleState.IN_PROVING;
                    wait_prove_ids[count] = id;
                    count++;
                }
            }
        }

        if (count > 0) {
            uint64[] memory proving_ids = new uint64[](count);
            for (uint256 j = 0; j < count; j++) {
                proving_ids[j] = wait_prove_ids[j];
            }
            emit RuleInProving(proving_ids);
            delete wait_prove_rules_;
        }

        if (success_rules_.length > 0) {
            for (uint256 i = 0; i < success_rules_.length; i++) {
                uint64 id = success_rules_[i];
                if (checkExist(id)) {
                    InferRule storage rule = rules_[id];
                    if (rule.state_ == RuleState.PROVING_SUCCESS) {
                        rule.state_ = RuleState.IN_USE;
                    }
                }
            }
            emit RuleInUse(success_rules_);
            delete success_rules_;
        }
    }

    event SuperTransferred(
        address old_administrator_,
        address new_administrator_
    );
    function tranferSuperAdmin(address _new_admin) external {
        require(checkSuperPermission(msg.sender), "Permission denied");
        require(administrator_ != _new_admin, "Permission denied, same address");

        address old_admin = administrator_;
        administrator_ = _new_admin;
        emit SuperTransferred(old_admin, _new_admin);
    }

    // return administrator_
    function getSuperAdmin() public view returns (address) {
        return administrator_;
    }

    // return administrator_
    function getGranteeAdmin() public view returns ( address[] memory) {
        return grantees_;
    }

    event AdminGranted(
        address grantee
    );
    function grantAdmin(address _addr) external {
        require(checkSuperPermission(msg.sender), "Permission denied");
        require(!checkGrantPermission(_addr), "Address already exist in grantees");

        grantees_.push(_addr);
        emit AdminGranted(_addr);
    }
    event AdminRevoked(
        address revoker
    );
    function revokeAdmin(address _addr) external {
        require(checkSuperPermission(msg.sender), "Permission denied");
        require(checkGrantPermission(_addr), "Address not exist in grantees");

        for (uint256 i = 0; i < grantees_.length; i++) {
            if (grantees_[i] == _addr) {
                grantees_[i] = grantees_[grantees_.length - 1];
                grantees_.pop();
                break;
            }
        }

        emit AdminRevoked(_addr);
    }
}
