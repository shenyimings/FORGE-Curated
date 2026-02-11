// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "./IzkToken.sol";
import "./IWithdrawVault.sol";
import "./IVault.sol";
import "./utils.sol";

contract Vault is Pausable, AccessControl, IVault {
    using SafeERC20 for IERC20;
    using SafeERC20 for IzkToken;

    mapping(address => uint256) private tvl;

    // Supported tokens list
    mapping(address => bool) public supportedTokens;

    //zkTokens list
    mapping(address => IzkToken) public supportedTokenToZkToken;
    mapping(address => address) public zkTokenToSupportedToken;

    uint256 public lastClaimQueueID = 10_000;
    mapping(uint256 => ClaimItem) private claimQueue;

    // Main information
    mapping(address => mapping(address => AssetsInfo)) private userAssetsInfo;

    // Reward rate
    struct RewardRateState {
        address token;
        uint256 rewardRate;
        uint256 updatedTime;
    }
    mapping(address => RewardRateState[]) private rewardRateState;

    // Role
    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 private constant BOT_ROLE = keccak256("BOT_ROLE");

    // Misc
    address private ceffu;
    uint256 private penaltyRate = 50; // 0.5%
    mapping(address => uint256) public minStakeAmount;
    mapping(address => uint256) public maxStakeAmount;
    uint256 public WAITING_TIME;
    uint256 private constant BASE = 10_000;

    mapping(address => uint256) public totalStakeAmountByToken;
    mapping(address => uint256) private _lastRewardUpdatedTime;
    mapping(address => uint256) public totalRewardsAmountByToken;

    uint256 private initialTime;
    IWithdrawVault private withdrawVault;
    address private airdropAddr;

    bool flashNotEnable = true;
    bool cancelNotEnable = true;

    constructor(
        address[] memory _tokens,
        address[] memory _zkTokens,
        uint256[] memory _newRewardRate,
        uint256[] memory _minStakeAmount,
        uint256[] memory _maxStakeAmount,
        address _admin,
        address _bot,
        address _ceffu,
        uint256 _waitingTime,
        address payable withdrawVaultAddress,
        address _airdropAddr
    ) {
        Utils.CheckIsZeroAddress(_ceffu);
        Utils.CheckIsZeroAddress(_admin);
        Utils.CheckIsZeroAddress(_bot);
        airdropAddr = _airdropAddr;

        uint256 len = _tokens.length;
        require(Utils.MustGreaterThanZero(len));
        require(
            len == _newRewardRate.length &&
            len == _minStakeAmount.length &&
            len == _maxStakeAmount.length && 
            len == _zkTokens.length
        );

        // Grant role
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(BOT_ROLE, _bot);

        ceffu = _ceffu;
        emit UpdateCeffu(address(0), _ceffu);

        WAITING_TIME = _waitingTime;
        emit UpdateWaitingTime(0, _waitingTime);

        initialTime = block.timestamp;

        // Set the supported tokens and reward rate
        for (uint256 i = 0; i < len; i++) {
            require(_minStakeAmount[i] < _maxStakeAmount[i]);

            // supported tokens
            address token = _tokens[i];
            minStakeAmount[token] = _minStakeAmount[i];
            maxStakeAmount[token] = _maxStakeAmount[i];
            supportedTokens[token] = true;
            emit AddSupportedToken(token, _minStakeAmount[i], _maxStakeAmount[i]);

            IzkToken tokenTemp = IzkToken(_zkTokens[i]);
            supportedTokenToZkToken[token] = tokenTemp;
            zkTokenToSupportedToken[address(tokenTemp)] = token;
            emit ZkTokenCreated(address(tokenTemp));

            // reward rate
            RewardRateState memory rewardRateItem = RewardRateState({
                token: token,
                rewardRate: _newRewardRate[i],
                updatedTime: block.timestamp
            });
            rewardRateState[token].push(rewardRateItem);
            emit UpdateRewardRate(token, 0, _newRewardRate[i]);

            _lastRewardUpdatedTime[token] = block.timestamp;
        
        }

        withdrawVault = IWithdrawVault(withdrawVaultAddress);

        _pause();
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///                                           Controller                                              ///
    /////////////////////////////////////////////////////////////////////////////////////////////////////////


    modifier OnlyFlashEnable{
        require(!flashNotEnable, "flash withdraw not enable");
    _;
    }
    modifier OnlyCancelEnable{
        require(!cancelNotEnable, "cancel claim not enable");
    _;
    }

    event FlashStatusChanged(bool indexed oldStatus, bool indexed newStatus);
    event CancelStatusChanged(bool indexed oldStatus, bool indexed newStatus);

    function setFlashEnable(bool _enable) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_enable != flashNotEnable, "nothing changed");
        bool oldStatus = flashNotEnable;
        flashNotEnable = _enable;
        emit FlashStatusChanged(oldStatus, _enable);
    }
    function setCancelEnable(bool _enable) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_enable != cancelNotEnable, "nothing changed");
        bool oldStatus = cancelNotEnable;
        cancelNotEnable = _enable;

        emit CancelStatusChanged(oldStatus, _enable);
    }

    modifier onlySupportedToken(address _token) {
        require(supportedTokens[_token], "Unsupported");
        _;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///                                             write                                                 ///
    /////////////////////////////////////////////////////////////////////////////////////////////////////////

    // function signature: 000000ed, the less function matching, the more gas saved
    function stake_66380860(address _token,  uint256 _stakedAmount) external onlySupportedToken(_token) whenNotPaused {
        AssetsInfo storage assetsInfo = userAssetsInfo[msg.sender][_token];
        uint256 currentStakedAmount = assetsInfo.stakedAmount;

        require(Utils.Add(currentStakedAmount, _stakedAmount) >= minStakeAmount[_token]);
        require(Utils.Add(currentStakedAmount, _stakedAmount) <= maxStakeAmount[_token]);

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _stakedAmount);

        _updateRewardState(msg.sender, _token);
        uint256 exchangeRate = _getExchangeRate(_token);

        totalStakeAmountByToken[_token] += _stakedAmount;
        uint256 mintAmount = _stakedAmount * 1e18 / exchangeRate;
        supportedTokenToZkToken[_token].mint(msg.sender, mintAmount);

        // update status
        assetsInfo.stakeHistory.push(
            StakeItem({
                stakeTimestamp: block.timestamp,
                amount: _stakedAmount,
                token: _token,
                user: msg.sender
            })
        );
        unchecked {
            assetsInfo.stakedAmount += _stakedAmount;
            tvl[_token] += _stakedAmount;
        }

        emit Stake(msg.sender, _token, _stakedAmount);
    }

    // function signature: 0000004e, the less function matching, the more gas saved
    function requestClaim_8135334(
        address _token, 
        uint256 _amount
    ) external onlySupportedToken(_token) whenNotPaused returns(uint256 _returnID) {
        _updateRewardState(msg.sender, _token);
        uint256 exchangeRate = _getExchangeRate(_token);

        AssetsInfo storage assetsInfo = userAssetsInfo[msg.sender][_token];
        uint256 currentStakedAmount = assetsInfo.stakedAmount;
        uint256 currentAccumulatedRewardAmount = assetsInfo.accumulatedReward;

        require(
            Utils.MustGreaterThanZero(_amount) && 
            (_amount <= Utils.Add(currentStakedAmount, currentAccumulatedRewardAmount) || _amount == type(uint256).max), 
            "Invalid amount"
        );

        ClaimItem storage queueItem = claimQueue[lastClaimQueueID];

        // Withdraw from reward first; if insufficient, continue withdrawing from principal
        uint256 totalAmount = _amount;
        (totalAmount, , ) = _handleWithdraw(_amount, assetsInfo, queueItem, false);

        require(totalAmount > 0, "No assets to withdraw");

        // update status
        assetsInfo.pendingClaimQueueIDs.push(lastClaimQueueID);

        totalStakeAmountByToken[_token] -= queueItem.principalAmount;
        totalRewardsAmountByToken[_token] -= queueItem.rewardAmount;

        uint256 sharesToBurn = totalAmount * 1e18 / exchangeRate;
        uint256 zkBalance = supportedTokenToZkToken[_token].balanceOf(msg.sender);
        
        if(sharesToBurn > zkBalance || assetsInfo.stakedAmount == 0) sharesToBurn = zkBalance;

        supportedTokenToZkToken[_token].burn(msg.sender, sharesToBurn);

        // update queue
        queueItem.token = _token;
        queueItem.user = msg.sender;
        queueItem.totalAmount = totalAmount;
        queueItem.requestTime = block.timestamp;
        queueItem.claimTime = Utils.Add(block.timestamp, WAITING_TIME);

        unchecked {
            _returnID = lastClaimQueueID;
            ++lastClaimQueueID;
        }

        emit RequestClaim(msg.sender, _token, totalAmount, _returnID);
    }

    function cancelClaim(uint256 _queueId, address _token) external whenNotPaused OnlyCancelEnable{
        ClaimItem memory claimItem = claimQueue[_queueId];
        delete claimQueue[_queueId];

        address token = claimItem.token;
        AssetsInfo storage assetsInfo = userAssetsInfo[msg.sender][token];
        uint256[] memory pendingClaimQueueIDs = userAssetsInfo[msg.sender][token].pendingClaimQueueIDs;
        
        require(Utils.MustGreaterThanZero(claimItem.totalAmount));
        require(claimItem.user == msg.sender);
        require(!claimItem.isDone, "claimed");
        require(token == _token, "wrong token");

        for(uint256 i = 0; i < pendingClaimQueueIDs.length; i++) {
            if(pendingClaimQueueIDs[i] == _queueId) {
                assetsInfo.pendingClaimQueueIDs[i] = pendingClaimQueueIDs[pendingClaimQueueIDs.length-1];
                assetsInfo.pendingClaimQueueIDs.pop();
                break;
            }
        }

        uint256 principal = claimItem.principalAmount;
        uint256 reward = claimItem.rewardAmount;

        assetsInfo.stakedAmount += principal;
        assetsInfo.accumulatedReward += reward;
        assetsInfo.lastRewardUpdateTime = block.timestamp;

        _updateRewardState(msg.sender, _token);
        uint256 exchangeRate = _getExchangeRate(_token);
        uint256 amountToMint = (principal + reward) * 1e18 / exchangeRate;

        totalStakeAmountByToken[_token] += principal;
        totalRewardsAmountByToken[_token] += reward;

        supportedTokenToZkToken[_token].mint(msg.sender, amountToMint);

        emit CancelClaim(msg.sender, _token, principal + reward, _queueId);
    }

    // function signature: 000000e5, the less function matching, the more gas saved
    function claim_41202704(uint256 _queueID, address _token) external whenNotPaused{
        ClaimItem memory claimItem = claimQueue[_queueID];
        address token = claimItem.token;
        AssetsInfo storage assetsInfo = userAssetsInfo[msg.sender][token];
        uint256[] memory pendingClaimQueueIDs = userAssetsInfo[msg.sender][token].pendingClaimQueueIDs;
        
        require(Utils.MustGreaterThanZero(claimItem.totalAmount));
        require(block.timestamp >= claimItem.claimTime);
        require(claimItem.user == msg.sender);
        require(!claimItem.isDone, "claimed");
        require(token == _token, "wrong token");

        // update status
        claimQueue[_queueID].isDone = true;
        for(uint256 i = 0; i < pendingClaimQueueIDs.length; i++) {
            if(pendingClaimQueueIDs[i] == _queueID) {
                assetsInfo.pendingClaimQueueIDs[i] = pendingClaimQueueIDs[pendingClaimQueueIDs.length-1];
                assetsInfo.pendingClaimQueueIDs.pop();
                break;
            }
        }
        tvl[token] -= claimItem.principalAmount;

        assetsInfo.claimHistory.push(
            ClaimItem({
                isDone: true,
                token: token,
                user: msg.sender,
                totalAmount: claimItem.totalAmount,
                principalAmount: claimItem.principalAmount,
                rewardAmount: claimItem.rewardAmount,
                requestTime: claimItem.requestTime,
                claimTime: block.timestamp
            })
        );
        withdrawVault.transfer(token, msg.sender, claimItem.totalAmount);

        emit ClaimAssets(msg.sender, token, claimItem.totalAmount, _queueID);
    }

    function flashWithdrawWithPenalty(
        address _token,
        uint256 _amount
    ) external onlySupportedToken(_token) whenNotPaused OnlyFlashEnable{
        AssetsInfo storage assetsInfo = userAssetsInfo[msg.sender][_token];
        _updateRewardState(msg.sender, _token);
        uint256 exchangeRate = _getExchangeRate(_token);

        uint256 currentStakedAmount = assetsInfo.stakedAmount;
        uint256 currentAccumulatedRewardAmount = assetsInfo.accumulatedReward;

        require(
            Utils.MustGreaterThanZero(_amount) && 
            (_amount <= Utils.Add(currentStakedAmount, currentAccumulatedRewardAmount) || _amount == type(uint256).max)
        );

        uint256 totalAmount = _amount;
        uint256 principalAmount;
        uint256 rewardAmount;
        (totalAmount, principalAmount, rewardAmount) = _handleWithdraw(_amount, assetsInfo, claimQueue[lastClaimQueueID], true);

        require(totalAmount > 0, "no assets to withdraw");
    
        totalStakeAmountByToken[_token] -= principalAmount;
        totalRewardsAmountByToken[_token] -= rewardAmount;

        uint256 sharesToBurn = (totalAmount * 1e18) / exchangeRate;
        uint256 zkBalance = supportedTokenToZkToken[_token].balanceOf(msg.sender);

        if(sharesToBurn > zkBalance || assetsInfo.stakedAmount == 0) sharesToBurn = zkBalance;

        supportedTokenToZkToken[_token].burn(msg.sender, sharesToBurn);

        uint256 amountToSent = totalAmount * (BASE - penaltyRate) / BASE;
        uint256 fee = totalAmount - amountToSent;

        require(getContractBalance(_token) >= amountToSent, "not enough balance");

        IERC20(_token).safeTransfer(msg.sender, amountToSent);

        tvl[_token] -= principalAmount;

        assetsInfo.claimHistory.push(
            ClaimItem({
                isDone: true,
                token: _token,
                user: msg.sender,
                totalAmount: totalAmount,
                principalAmount: principalAmount,
                rewardAmount: rewardAmount,
                requestTime: block.timestamp,
                claimTime: block.timestamp
            })
        );

        emit FlashWithdraw(msg.sender, _token, totalAmount, fee);
    }

    function _handleWithdraw(
        uint256 _amount,
        AssetsInfo storage assetsInfo,
        ClaimItem storage queueItem,
        bool isFlash
    ) internal returns(uint256, uint256, uint256){
        uint256 totalAmount = _amount;
        uint256 principalAmount;
        uint256 rewardAmount;
        uint256 currentAccumulatedRewardAmount = assetsInfo.accumulatedReward;
        if(_amount == type(uint256).max){
            totalAmount = Utils.Add(currentAccumulatedRewardAmount, assetsInfo.stakedAmount);
            rewardAmount = currentAccumulatedRewardAmount;

            assetsInfo.accumulatedReward = 0;

            principalAmount = assetsInfo.stakedAmount;
            assetsInfo.stakedAmount = 0;
        }else if(currentAccumulatedRewardAmount >= _amount) {
            assetsInfo.accumulatedReward -= _amount;
            rewardAmount = _amount;
        } else {
            rewardAmount = currentAccumulatedRewardAmount;
            assetsInfo.accumulatedReward = 0;

            uint256 difference = _amount - currentAccumulatedRewardAmount;
            assetsInfo.stakedAmount -= difference;
            principalAmount = difference;
        }
        if(!isFlash) {
            queueItem.rewardAmount = rewardAmount;
            queueItem.principalAmount = principalAmount;

        }
        return(totalAmount, principalAmount, rewardAmount);
    }

    function _updateRewardState(address _user, address _token) internal {
        AssetsInfo storage assetsInfo = userAssetsInfo[_user][_token];
        uint256 newAccumulatedReward = 0;
        uint256 newAccumulatedRewardForAll;
        if(assetsInfo.lastRewardUpdateTime != 0) { // not the first time to stake
            newAccumulatedReward = _getClaimableRewards(_user, _token);
        }
        
        newAccumulatedRewardForAll = _getClaimableRewards(address(this), _token);

        assetsInfo.accumulatedReward = newAccumulatedReward;
        assetsInfo.lastRewardUpdateTime = block.timestamp;

        _lastRewardUpdatedTime[_token] = block.timestamp;
        totalRewardsAmountByToken[_token] = newAccumulatedRewardForAll;
    }

    function _getExchangeRate(address _token) internal view returns(uint256 exchangeRate){
        uint256 totalSupplyZKToken = supportedTokenToZkToken[_token].totalSupply();
        if (totalSupplyZKToken == 0) {
            exchangeRate = 1e18;
        } else {
            exchangeRate = ((totalStakeAmountByToken[_token] + totalRewardsAmountByToken[_token]) * 1e18) / totalSupplyZKToken;
        }
    }

    function convertToShares(uint256 tokenAmount, address _token) public view returns(uint256 shares) {
        uint256 totalSupplyZKToken = supportedTokenToZkToken[_token].totalSupply();
        uint256 totalStaked = totalStakeAmountByToken[_token];
        uint256 totalRewards = _getClaimableRewards(address(this), _token);

        uint256 exchangeRate = totalSupplyZKToken == 0 ? 
        1e18 : (totalStaked + totalRewards) * 1e18 / totalSupplyZKToken;
        shares = (tokenAmount * 1e18) / exchangeRate;
    }

    function convertToAssets(uint256 shares, address _token) public view returns(uint256 tokenAmount) {
        uint256 totalSupplyZKToken = supportedTokenToZkToken[_token].totalSupply();
        uint256 totalStaked = totalStakeAmountByToken[_token];
        uint256 totalRewards = _getClaimableRewards(address(this), _token);

        uint256 exchangeRate = totalSupplyZKToken == 0 ? 
        1e18 : (totalStaked + totalRewards) * 1e18 / totalSupplyZKToken;

        tokenAmount = (shares * exchangeRate) / 1e18;
    }

    function transferOrTransferFrom(address token, address from, address to, uint256 amount) public returns (bool) {
        require(from != to, "from can not be same as the to");
        require(amount > 0, "amount must be greater than 0");

        uint256 tokenBefore = getZKTokenAmount(from, token);
        require(tokenBefore >= amount, "balance");
        if(msg.sender != from){
            require(supportedTokenToZkToken[token].allowance(from, msg.sender) >= amount, "allowance");
            supportedTokenToZkToken[token].updateAllowance(from, msg.sender, amount);
            supportedTokenToZkToken[token].transferFrom(from, to, amount);
        }else{
            supportedTokenToZkToken[token].transferFrom(msg.sender, to, amount);
        }

        _assetsInfoUpdate(token, from, to, amount, tokenBefore);

        return true;
    }

    // airdrop
    function sendLpTokens(address token, address to, uint256 amount, bool flag) external {
        require(msg.sender == airdropAddr);
        supportedTokenToZkToken[token].transferFrom(airdropAddr, to, amount);
        
        AssetsInfo storage assetsInfo = userAssetsInfo[to][token];
        if(flag == true){
            assetsInfo.lastRewardUpdateTime = initialTime;
        }else{
            _updateRewardState(to, token);
        }

        assetsInfo.stakedAmount += amount;

        totalStakeAmountByToken[token] += amount;
        tvl[token] += amount;
    }

    function _assetsInfoUpdate(address token, address from, address to, uint256 amount, uint256 tokenBefore) internal{
        _updateRewardState(from, token);
        _updateRewardState(to, token);
        AssetsInfo storage assetsInfoFrom = userAssetsInfo[from][token];
        uint256 stakedAmount = assetsInfoFrom.stakedAmount;
        uint256 accumulatedReward = assetsInfoFrom.accumulatedReward;

        AssetsInfo storage assetsInfoTo = userAssetsInfo[to][token];

        uint256 percent = amount * 1e18 / tokenBefore;
        uint256 deltaStaked = (stakedAmount * percent / 1e18);
        uint256 deltaReward = (accumulatedReward * percent / 1e18);

        assetsInfoTo.stakedAmount += deltaStaked;
        assetsInfoFrom.stakedAmount -= deltaStaked;
        assetsInfoTo.accumulatedReward += deltaReward;
        assetsInfoFrom.accumulatedReward -= deltaReward;
        assetsInfoTo.lastRewardUpdateTime = block.timestamp ;
    }

    function transferToCeffu(
        address _token,
        uint256 _amount
    ) external onlySupportedToken(_token) onlyRole(BOT_ROLE) {
        require(Utils.MustGreaterThanZero(_amount), "must > 0");
        require(_amount <= IERC20(_token).balanceOf(address(this)), "Not enough balance");

        IERC20(_token).safeTransfer(ceffu, _amount);

        emit CeffuReceive(_token, ceffu, _amount);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///                                          emergency                                                ///
    /////////////////////////////////////////////////////////////////////////////////////////////////////////

    function emergencyWithdraw(address _token, address _receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // `_token` could be not supported, so that we could sweep the tokens which are sent to this contract accidentally
        Utils.CheckIsZeroAddress(_token);
        Utils.CheckIsZeroAddress(_receiver);

        IERC20(_token).safeTransfer(_receiver, IERC20(_token).balanceOf(address(this)));
        emit EmergencyWithdrawal(_token, _receiver);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///                                        configuration                                              ///
    /////////////////////////////////////////////////////////////////////////////////////////////////////////

    function addSupportedToken(
        address _token,
        uint256 _minAmount,
        uint256 _maxAmount,
        address _zkToken
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Utils.CheckIsZeroAddress(_token);
        require(!supportedTokens[_token], "Supported");

        // update the supported tokens
        supportedTokens[_token] = true;
        setStakeLimit(_token, _minAmount, _maxAmount);
        emit AddSupportedToken(_token, _minAmount, _maxAmount);

        IzkToken tokenTemp = IzkToken(_zkToken);
        supportedTokenToZkToken[_token] = tokenTemp;
        zkTokenToSupportedToken[address(tokenTemp)] = _token;
        emit ZkTokenCreated(address(tokenTemp));
    }

    function setRewardRate(
        address _token, 
        uint256 _newRewardRate
    ) external onlySupportedToken(_token) onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newRewardRate < BASE, "Invalid rate");

        RewardRateState[] memory rewardRateArray = rewardRateState[_token];
        uint256 currentRewardRate = rewardRateArray[rewardRateArray.length - 1].rewardRate;
        require(currentRewardRate != _newRewardRate && Utils.MustGreaterThanZero(_newRewardRate), "Invalid new rate");

        // add the new reward rate to the array
        RewardRateState memory rewardRateItem = RewardRateState({
            updatedTime: block.timestamp,
            token: _token,
            rewardRate: _newRewardRate
        });
        rewardRateState[_token].push(rewardRateItem);

        emit UpdateRewardRate(_token, currentRewardRate, _newRewardRate);
    }

    function setAirdropAddr(address newAirdropAddr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        //allow equal address(0), when we want to disable airdrop
        airdropAddr = newAirdropAddr;
    }

    function setPenaltyRate(uint256 newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRate <= BASE && newRate != penaltyRate, "Invalid");

        emit UpdatePenaltyRate(penaltyRate, newRate);
        penaltyRate = newRate;
    }


    function setCeffu(address _newCeffu) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Utils.CheckIsZeroAddress(_newCeffu);
        require(_newCeffu != ceffu);

        emit UpdateCeffu(ceffu, _newCeffu);
        ceffu = _newCeffu;
    }

    function setStakeLimit(
        address _token,
        uint256 _minAmount,
        uint256 _maxAmount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) onlySupportedToken(_token) {
        require(Utils.MustGreaterThanZero(_minAmount) && _minAmount < _maxAmount);

        emit UpdateStakeLimit(_token, minStakeAmount[_token], maxStakeAmount[_token], _minAmount, _maxAmount);
        minStakeAmount[_token] = _minAmount;
        maxStakeAmount[_token] = _maxAmount;
    }

    function setWaitingTime(uint256 _newWaitingTime) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_newWaitingTime != WAITING_TIME, "Invalid");

        emit UpdateWaitingTime(WAITING_TIME, _newWaitingTime);
        WAITING_TIME = _newWaitingTime;        
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///                                          view / pure                                              ///
    /////////////////////////////////////////////////////////////////////////////////////////////////////////

    function calculateReward(
        uint256 _stakedAmount, 
        uint256 _rewardRate, 
        uint256 _elapsedTime
    ) internal pure returns (uint256 result) {
        // (stakedAmount * rewardRate * elapsedTime) / (ONE_YEAR * 10000)
        // Parameter descriptions:
        // - stakedAmount: The amount staked by the user
        // - rewardRate: The annual reward rate (e.g., 700 means 7%)
        // - elapsedTime: The time interval over which the reward is calculated, in seconds
        // - ONE_YEAR: The total number of seconds in one year (365.25 days)
        assembly {
            // uint256 ONE_YEAR = uint256(365.25 * 24 * 60 * 60); // 365.25 days per year: 31557600
            let ONE_YEAR := 31557600

            // Calculate numerator = stakedAmount * rewardRate * elapsedTime
            let numerator := mul(_stakedAmount, _rewardRate)
            numerator := mul(numerator, _elapsedTime)

            // Calculate denominator = ONE_YEAR * 10000
            let denominator := mul(ONE_YEAR, BASE)

            // Perform the division result = numerator / denominator
            result := div(numerator, denominator)
        }
    }

    function _getClaimableRewards(address _user, address _token) internal view returns (uint256) {
        uint256 currentStakedAmount;
        uint256 lastRewardUpdate;
        uint256 currentRewardAmount;

        if(_user != address(this)){
            AssetsInfo memory assetsInfo = userAssetsInfo[_user][_token];
            currentStakedAmount = assetsInfo.stakedAmount;
            lastRewardUpdate = assetsInfo.lastRewardUpdateTime;
            currentRewardAmount = assetsInfo.accumulatedReward;
        } else {
            currentStakedAmount = totalStakeAmountByToken[_token];
            lastRewardUpdate = _lastRewardUpdatedTime[_token];
            currentRewardAmount = totalRewardsAmountByToken[_token];
        }

        RewardRateState[] memory rewardRateArray = rewardRateState[_token];
        uint256 rewardRateLength = rewardRateArray.length;
        RewardRateState memory currentRewardRateState = rewardRateArray[rewardRateLength - 1];

        if(lastRewardUpdate == 0) return 0;

        // 1. Retrieve the last deposit time `begin`
        // 2. Retrieve the current deposit time `end`
        // 3. Check whether the reward rate changed between time `begin` and time `end`
        // 4. Determine if the reward rate has changed since the last deposit:
        //    - If no changes occurred, directly calculate and add the reward.
        //    - If changes occurred, divide the deposit time into segments based on different rates 
        //      and accumulate the rewards accordingly.
        if(currentRewardRateState.updatedTime <= lastRewardUpdate){
            /*
                   begin                   end
                    |~~~~~~ position ~~~~~~~|
                |--------- reward rate 1 --------------|--------- upcoming reward rate 2 --------------|
            */

            uint256 elapsedTime = block.timestamp - lastRewardUpdate;
            uint256 reward = calculateReward(
                currentStakedAmount,
                currentRewardRateState.rewardRate,
                elapsedTime
            );

            return currentRewardAmount + reward;
        } else {
            /*
                   begin                                                       end
                    |~~~~~~~~~~~~~~~~~~~~~~ position ~~~~~~~~~~~~~~~~~~~~~~~~~~~|
                |--------- reward rate 1 --------------|-- reward rate 2 --|-------- reward rate 3 --------|
            */

            // a. based on the reward rate at the time of the last stake, find the corresponding index in the rate array
            uint256 beginIndex = 0;
            for (uint256 i = 0; i < rewardRateLength; i++) {
                if (lastRewardUpdate < rewardRateArray[i].updatedTime) {
                    beginIndex = i;
                    break;
                }
            }

            // b. iterate to the latest-1 reward rate
            uint256 tempLastRewardUpdateTime = lastRewardUpdate;
            for (uint256 i = beginIndex; i < rewardRateLength; i++) {
                if(i == 0) continue;

                uint256 tempElapsedTime = rewardRateArray[i].updatedTime - tempLastRewardUpdateTime;
                uint256 tempReward = calculateReward(
                    currentStakedAmount,
                    rewardRateArray[i - 1].rewardRate,
                    tempElapsedTime
                );
                tempLastRewardUpdateTime = rewardRateArray[i].updatedTime;
                unchecked{
                    currentRewardAmount += tempReward;
                }
            }

            // c. the reward generated by the latest reward rate
            uint256 elapsedTime = block.timestamp - currentRewardRateState.updatedTime;
            uint256 reward = calculateReward(
                currentStakedAmount,
                currentRewardRateState.rewardRate,
                elapsedTime
            );

            return currentRewardAmount + reward;
        }
    }

    // principal + rewards
    function getClaimableAssets(address _user, address _token) external view returns (uint256) {
        AssetsInfo memory assetsInfo = userAssetsInfo[_user][_token];
        
        return Utils.Add(assetsInfo.stakedAmount, _getClaimableRewards(_user, _token));
    }

    // current rewards
    function getClaimableRewards(address _user, address _token) external view returns (uint256) {
        return _getClaimableRewards(_user, _token);
    }

    // history rewards + current rewards
    function getTotalRewards(address _user, address _token) external view returns (uint256) {
        uint256 historyRewards = 0;
        uint256 currentRewards = _getClaimableRewards(_user, _token);

        AssetsInfo memory stakeInfo = userAssetsInfo[_user][_token];
        for(uint256 i = 0; i < stakeInfo.claimHistory.length; i++) {
            historyRewards += stakeInfo.claimHistory[i].rewardAmount;
        }

        return Utils.Add(historyRewards, currentRewards);
    }

    // Calculate the total withdrawable amount for a user at a future time, 
    // based on the user's current staked amount and the current reward rate.
    function getClaimableRewardsWithTargetTime(
        address _user,
        address _token,
        uint256 _targetTime
    ) external view returns (uint256) {
        require(_targetTime > block.timestamp, "Invalid time");

        AssetsInfo memory assetsInfo = userAssetsInfo[_user][_token];
        RewardRateState[] memory rewardRateArray = rewardRateState[_token];
        RewardRateState memory currentRewardRateState = rewardRateArray[rewardRateArray.length - 1];

        uint256 newAccumulatedReward = 0;
        if(assetsInfo.lastRewardUpdateTime != 0) { // not the first time to stake
            newAccumulatedReward = _getClaimableRewards(_user, _token);
        }

        uint256 elapsedTime = _targetTime - block.timestamp;
        uint256 reward = calculateReward(
            assetsInfo.stakedAmount,
            currentRewardRateState.rewardRate,
            elapsedTime
        );

        return Utils.Add(newAccumulatedReward, reward);
    }

    function getStakedAmount(address _user, address _token) public view onlySupportedToken(_token) returns (uint256) {
        AssetsInfo memory stakeInfo = userAssetsInfo[_user][_token];
        return stakeInfo.stakedAmount;
    }

    function getZKTokenAmount(address _user, address _token) public view onlySupportedToken(_token) returns (uint256) {
        return supportedTokenToZkToken[_token].balanceOf(_user);
    }

    function getContractBalance(address _token) public view returns (uint256) {
        Utils.CheckIsZeroAddress(_token);
        return IERC20(_token).balanceOf(address(this));
    }

    function getStakeHistory(
        address _user,
        address _token,
        uint256 _index
    ) external view onlySupportedToken(_token) returns (StakeItem memory) {
        AssetsInfo memory stakeInfo = userAssetsInfo[_user][_token];
        require(_index < stakeInfo.stakeHistory.length, "index");

        return stakeInfo.stakeHistory[_index];
    }

    function getClaimHistory(
        address _user,
        address _token,
        uint256 _index
    ) external view onlySupportedToken(_token) returns (ClaimItem memory) {
        AssetsInfo memory stakeInfo = userAssetsInfo[_user][_token];
        require(_index < stakeInfo.claimHistory.length, "index");

        return stakeInfo.claimHistory[_index];
    }

    function getStakeHistoryLength(address _user, address _token) external view returns(uint256) {
        AssetsInfo memory stakeInfo = userAssetsInfo[_user][_token];

        return stakeInfo.stakeHistory.length;
    }
    function getClaimHistoryLength(address _user, address _token) public view returns(uint256) {
        AssetsInfo memory stakeInfo = userAssetsInfo[_user][_token];
        
        return stakeInfo.claimHistory.length;
    }

    // Check the current withdrawal request in progress for a specific user
    function getClaimQueueIDs(address _user, address _token) external view returns (uint256[] memory) {
        AssetsInfo memory assetsInfo = userAssetsInfo[_user][_token];
        return assetsInfo.pendingClaimQueueIDs;
    }

    // Measure the reward rate as a percentage, and return the numerator and denominator
    function getCurrentRewardRate(address _token) external view returns (uint256, uint256) {
        RewardRateState[] memory rewardRateStateArray = rewardRateState[_token];
        RewardRateState memory currentRewardRateState = rewardRateStateArray[rewardRateStateArray.length - 1];

        return (currentRewardRateState.rewardRate, BASE);
    }

    function getClaimQueueInfo(uint256 _index) external view returns(ClaimItem memory) {
        return claimQueue[_index];
    }

    function getTVL(address _token) external view returns(uint256){
        return tvl[_token];
    }

    receive() external payable {
        revert();
    }
}
