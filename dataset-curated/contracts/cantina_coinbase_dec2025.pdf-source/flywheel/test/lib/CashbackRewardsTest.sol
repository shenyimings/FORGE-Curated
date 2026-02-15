// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ERC3009PaymentCollector} from "commerce-payments/collectors/ERC3009PaymentCollector.sol";

import {OperatorRefundCollector} from "commerce-payments/collectors/OperatorRefundCollector.sol";
import {IERC3009} from "commerce-payments/interfaces/IERC3009.sol";
import {Test} from "forge-std/Test.sol";

import {LibString} from "solady/utils/LibString.sol";

import {MockERC3009Token} from "../../lib/commerce-payments/test/mocks/MockERC3009Token.sol";

import {Flywheel} from "../../src/Flywheel.sol";
import {CashbackRewards} from "../../src/hooks/CashbackRewards.sol";

contract CashbackRewardsTest is Test {
    // Test bounds constants when necessary for fuzzing
    uint120 internal constant MIN_PAYMENT_AMOUNT = 1e4; // 0.01 USDC
    uint120 internal constant MAX_PAYMENT_AMOUNT = type(uint120).max; // Maximum possible payment in escrow system
    uint120 internal constant MIN_REWARD_AMOUNT = 1; // 1 wei (minimum non-zero)
    uint120 internal constant DEFAULT_CAMPAIGN_BALANCE = 1000e6; // 1000 USDC
    uint120 internal constant MAX_REWARD_AMOUNT = DEFAULT_CAMPAIGN_BALANCE; // Bound by campaign balance

    // For tests that need to exceed campaign balance
    uint120 internal constant EXCESSIVE_MIN_REWARD = DEFAULT_CAMPAIGN_BALANCE + 1; // Just over campaign balance

    // Percentage validation constants
    uint16 internal constant TEST_MAX_REWARD_BASIS_POINTS = 100; // 1% for restricted campaigns
    uint16 internal constant MAX_REWARD_BASIS_POINTS_DIVISOR = 10000; // 100%

    // Allocation bounds for multi-step workflows
    uint120 internal constant MIN_ALLOCATION_AMOUNT = 1e4; // 0.01 USDC
    uint120 internal constant MAX_ALLOCATION_AMOUNT = DEFAULT_CAMPAIGN_BALANCE; // Bound by campaign balance

    uint256 internal constant OWNER_PK = uint256(keccak256("owner"));
    uint256 internal constant MANAGER_PK = uint256(keccak256("manager"));
    uint256 internal constant OPERATOR_PK = uint256(keccak256("operator"));
    uint256 internal constant BUYER_PK = uint256(keccak256("buyer"));
    uint256 internal constant RECEIVER_PK = uint256(keccak256("receiver"));

    uint16 internal constant FEE_BPS = 0; // No payment fees

    bytes32 constant _RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    address public constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    Flywheel public flywheel;
    CashbackRewards public cashbackRewards;
    AuthCaptureEscrow public escrow;
    MockERC3009Token public usdc;
    ERC3009PaymentCollector public paymentCollector;
    OperatorRefundCollector public refundCollector;

    address public owner;
    address public manager;
    address public operator;
    address public buyer;
    address public receiver;
    address public unlimitedCashbackCampaign;
    address public limitedCashbackCampaign; // Campaign with max reward percentage limit

    string public constant CAMPAIGN_URI = "https://example.com/campaign/metadata";

    function setUp() public virtual {
        // Set up Multicall3 (required for ERC3009PaymentCollector)
        vm.etch(MULTICALL3, _getMulticall3Code());

        escrow = new AuthCaptureEscrow();
        flywheel = new Flywheel();
        cashbackRewards = new CashbackRewards(address(flywheel), address(escrow));

        usdc = new MockERC3009Token("USD Coin", "USDC", 6);

        paymentCollector = new ERC3009PaymentCollector(address(escrow), MULTICALL3);
        refundCollector = new OperatorRefundCollector(address(escrow));

        owner = vm.addr(OWNER_PK);
        manager = vm.addr(MANAGER_PK);
        buyer = vm.addr(BUYER_PK);
        receiver = vm.addr(RECEIVER_PK);
        operator = vm.addr(OPERATOR_PK);

        vm.label(owner, "Owner");
        vm.label(manager, "Manager");
        vm.label(operator, "Operator");
        vm.label(buyer, "Buyer");
        vm.label(receiver, "Receiver");
        vm.label(address(flywheel), "Flywheel");
        vm.label(address(escrow), "AuthCaptureEscrow");
        vm.label(address(cashbackRewards), "CashbackRewards");
        vm.label(address(usdc), "USDC");

        _createUnlimitedCampaign();
        _createLimitedCampaign();

        _setupInitialTokenBalances();
    }

    /// @notice Create a standard PaymentInfo struct for testing
    function createPaymentInfo(address payer, uint120 maxAmount)
        public
        view
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return createPaymentInfo(payer, maxAmount, address(usdc));
    }

    /// @notice Create a PaymentInfo struct with custom token
    function createPaymentInfo(address payer, uint120 maxAmount, address token)
        public
        view
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: operator,
            payer: payer,
            receiver: receiver,
            token: token,
            maxAmount: maxAmount,
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + 1 hours),
            refundExpiry: uint48(block.timestamp + 1 hours),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(0),
            salt: uint256(keccak256(abi.encode(payer, maxAmount, block.timestamp)))
        });
    }

    /// @notice Create hook data for cashback rewards
    function createCashbackHookData(AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint120 rewardAmount)
        public
        pure
        returns (bytes memory)
    {
        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](1);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: rewardAmount});
        return abi.encode(paymentRewards, true);
    }

    /// @notice Create hook data for cashback rewards with revertOnError = false
    function createCashbackHookDataNoRevert(AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint120 rewardAmount)
        public
        pure
        returns (bytes memory)
    {
        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](1);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: paymentInfo, payoutAmount: rewardAmount});
        return abi.encode(paymentRewards, false);
    }

    /// @notice Create hook data for mixed payment rewards (some valid, some invalid) with revertOnError = false
    function createMixedCashbackHookDataNoRevert(
        AuthCaptureEscrow.PaymentInfo memory validPayment,
        uint120 validReward,
        AuthCaptureEscrow.PaymentInfo memory invalidPayment,
        uint120 invalidReward
    ) public pure returns (bytes memory) {
        CashbackRewards.PaymentReward[] memory paymentRewards = new CashbackRewards.PaymentReward[](2);
        paymentRewards[0] = CashbackRewards.PaymentReward({paymentInfo: validPayment, payoutAmount: validReward});
        paymentRewards[1] = CashbackRewards.PaymentReward({paymentInfo: invalidPayment, payoutAmount: invalidReward});
        return abi.encode(paymentRewards, false);
    }

    /// @notice Sign ERC3009 receiveWithAuthorization for payment
    function signERC3009Payment(AuthCaptureEscrow.PaymentInfo memory paymentInfo, uint256 signerPk)
        public
        view
        returns (bytes memory)
    {
        bytes32 nonce = _getPayerAgnosticHash(paymentInfo);

        bytes32 digest = _getERC3009Digest(
            paymentInfo.token,
            paymentInfo.payer,
            address(paymentCollector),
            paymentInfo.maxAmount,
            0, // validAfter
            paymentInfo.preApprovalExpiry,
            nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Authorize a payment through the escrow
    function authorizePayment(AuthCaptureEscrow.PaymentInfo memory paymentInfo)
        public
        returns (bytes32 paymentInfoHash)
    {
        bytes memory signature = signERC3009Payment(paymentInfo, BUYER_PK);

        vm.prank(operator);
        escrow.authorize(paymentInfo, paymentInfo.maxAmount, address(paymentCollector), signature);

        return escrow.getHash(paymentInfo);
    }

    /// @notice Charge a payment through the escrow
    function chargePayment(AuthCaptureEscrow.PaymentInfo memory paymentInfo) public returns (bytes32 paymentInfoHash) {
        bytes memory signature = signERC3009Payment(paymentInfo, BUYER_PK);

        vm.prank(operator);
        escrow.charge(paymentInfo, paymentInfo.maxAmount, address(paymentCollector), signature, FEE_BPS, address(0));

        return escrow.getHash(paymentInfo);
    }

    /// @notice Get current payment state from escrow
    function getPaymentState(AuthCaptureEscrow.PaymentInfo memory paymentInfo)
        public
        view
        returns (AuthCaptureEscrow.PaymentState memory)
    {
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        (bool hasCollectedPayment, uint120 capturableAmount, uint120 refundableAmount) =
            escrow.paymentState(paymentInfoHash);
        return AuthCaptureEscrow.PaymentState({
            hasCollectedPayment: hasCollectedPayment,
            capturableAmount: capturableAmount,
            refundableAmount: refundableAmount
        });
    }

    /// @notice Get rewards info for a payment and campaign
    function getRewardsInfo(AuthCaptureEscrow.PaymentInfo memory paymentInfo, address campaign)
        public
        view
        returns (CashbackRewards.RewardState memory)
    {
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        (uint120 allocated, uint120 distributed) = cashbackRewards.rewards(campaign, paymentInfoHash);
        return CashbackRewards.RewardState({allocated: allocated, distributed: distributed});
    }

    /// @notice Create an unlimited cashback campaign (no max reward basis points)
    function _createUnlimitedCampaign() internal {
        // Encode hook data: (owner, manager, uri, maxRewardBasisPoints)
        bytes memory hookData = abi.encode(owner, manager, CAMPAIGN_URI, uint16(0)); // No max reward limit

        // Create campaign
        vm.prank(manager);
        unlimitedCashbackCampaign = flywheel.createCampaign(
            address(cashbackRewards),
            0, // nonce
            hookData
        );

        vm.label(unlimitedCashbackCampaign, "CashbackCampaign");

        // Activate campaign
        vm.prank(manager);
        flywheel.updateStatus(unlimitedCashbackCampaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    /// @notice Create a limited cashback campaign (1% max reward basis points)
    function _createLimitedCampaign() internal {
        // Encode hook data: (owner, manager, uri, maxRewardBasisPoints)
        bytes memory hookData = abi.encode(owner, manager, CAMPAIGN_URI, TEST_MAX_REWARD_BASIS_POINTS); // 1% max reward

        // Create campaign
        vm.prank(manager);
        limitedCashbackCampaign = flywheel.createCampaign(
            address(cashbackRewards),
            0, // nonce
            hookData
        );

        vm.label(limitedCashbackCampaign, "RestrictedCampaign");

        // Activate campaign
        vm.prank(manager);
        flywheel.updateStatus(limitedCashbackCampaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    /// @notice Setup initial token balances for the campaigns
    function _setupInitialTokenBalances() internal {
        // Give buyer tokens for payments (generous amount for comprehensive testing)
        usdc.mint(buyer, MAX_PAYMENT_AMOUNT);

        // Give campaign some tokens for rewards
        usdc.mint(unlimitedCashbackCampaign, DEFAULT_CAMPAIGN_BALANCE);

        // Give limited campaign some tokens for rewards too
        usdc.mint(limitedCashbackCampaign, DEFAULT_CAMPAIGN_BALANCE);

        // Give operator some tokens for refunds
        usdc.mint(operator, DEFAULT_CAMPAIGN_BALANCE);
    }

    /// @notice Get ERC3009 digest for signing
    function _getERC3009Digest(
        address token,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(_RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        return keccak256(abi.encodePacked("\x19\x01", IERC3009(token).DOMAIN_SEPARATOR(), structHash));
    }

    /// @notice Get payer-agnostic hash for ERC3009 nonce
    function _getPayerAgnosticHash(AuthCaptureEscrow.PaymentInfo memory paymentInfo) internal view returns (bytes32) {
        address originalPayer = paymentInfo.payer;
        paymentInfo.payer = address(0);
        bytes32 hash = escrow.getHash(paymentInfo);
        paymentInfo.payer = originalPayer;
        return hash;
    }

    /// @notice Helper to get Multicall3 bytecode
    function _getMulticall3Code() internal pure returns (bytes memory) {
        return hex"6080604052600436106100f35760003560e01c80634d2301cc1161008a578063a8b0574e11610059578063a8b0574e1461025a578063bce38bd714610275578063c3077fa914610288578063ee82ac5e1461029b57600080fd5b80634d2301cc146101ec57806372425d9d1461022157806382ad56cb1461023457806386d516e81461024757600080fd5b80633408e470116100c65780633408e47014610191578063399542e9146101a45780633e64a696146101c657806342cbb15c146101d957600080fd5b80630f28c97d146100f8578063174dea711461011a578063252dba421461013a57806327e86d6e1461015b575b600080fd5b34801561010457600080fd5b50425b6040519081526020015b60405180910390f35b61012d610128366004610a85565b6102ba565b6040516101119190610bbe565b61014d610148366004610a85565b6104ef565b604051610111929190610bd8565b34801561016757600080fd5b50437fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0140610107565b34801561019d57600080fd5b5046610107565b6101b76101b2366004610c60565b610690565b60405161011193929190610cba565b3480156101d257600080fd5b5048610107565b3480156101e557600080fd5b5043610107565b3480156101f857600080fd5b50610107610207366004610ce2565b73ffffffffffffffffffffffffffffffffffffffff163190565b34801561022d57600080fd5b5044610107565b61012d610242366004610a85565b6106ab565b34801561025357600080fd5b5045610107565b34801561026657600080fd5b50604051418152602001610111565b61012d610283366004610c60565b61085a565b6101b7610296366004610a85565b610a1a565b3480156102a757600080fd5b506101076102b6366004610d18565b4090565b60606000828067ffffffffffffffff8111156102d8576102d8610d31565b60405190808252806020026020018201604052801561031e57816020015b6040805180820190915260008152606060208201528152602001906001900390816102f65790505b5092503660005b8281101561047757600085828151811061034157610341610d60565b6020026020010151905087878381811061035d5761035d610d60565b905060200281019061036f9190610d8f565b6040810135958601959093506103886020850185610ce2565b73ffffffffffffffffffffffffffffffffffffffff16816103ac6060870187610dcd565b6040516103ba929190610e32565b60006040518083038185875af1925050503d80600081146103f7576040519150601f19603f3d011682016040523d82523d6000602084013e6103fc565b606091505b50602080850191909152901515808452908501351761046d577f08c379a000000000000000000000000000000000000000000000000000000000600052602060045260176024527f4d756c746963616c6c333a2063616c6c206661696c656400000000000000000060445260846000fd5b5050600101610325565b508234146104e6576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601a60248201527f4d756c746963616c6c333a2076616c7565206d69736d6174636800000000000060448201526064015b60405180910390fd5b50505092915050565b436060828067ffffffffffffffff81111561050c5761050c610d31565b60405190808252806020026020018201604052801561053f57816020015b606081526020019060019003908161052a5790505b5091503660005b8281101561068657600087878381811061056257610562610d60565b90506020028101906105749190610e42565b92506105836020840184610ce2565b73ffffffffffffffffffffffffffffffffffffffff166105a66020850185610dcd565b6040516105b4929190610e32565b6000604051808303816000865af19150503d80600081146105f1576040519150601f19603f3d011682016040523d82523d6000602084013e6105f6565b606091505b5086848151811061060957610609610d60565b602090810291909101015290508061067d576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601760248201527f4d756c746963616c6c333a2063616c6c206661696c656400000000000000000060448201526064016104dd565b50600101610546565b5050509250929050565b43804060606106a086868661085a565b905093509350939050565b6060818067ffffffffffffffff8111156106c7576106c7610d31565b60405190808252806020026020018201604052801561070d57816020015b6040805180820190915260008152606060208201528152602001906001900390816106e55790505b5091503660005b828110156104e657600084828151811061073057610730610d60565b6020026020010151905086868381811061074c5761074c610d60565b905060200281019061075e9190610e76565b925061076d6020840184610ce2565b73ffffffffffffffffffffffffffffffffffffffff166107906040850185610dcd565b60405161079e929190610e32565b6000604051808303816000865af19150503d80600081146107db576040519150601f19603f3d011682016040523d82523d6000602084013e6107e0565b606091505b506020808401919091529015158083529084013517610851577f08c379a000000000000000000000000000000000000000000000000000000000600052602060045260176024527f4d756c746963616c6c333a2063616c6c206661696c656400000000000000000060445260646000fd5b50600101610714565b6060818067ffffffffffffffff81111561087657610876610d31565b6040519080825280602002602001820160405280156108bc57816020015b6040805180820190915260008152606060208201528152602001906001900390816108945790505b5091503660005b82811015610a105760008482815181106108df576108df610d60565b602002602001015190508686838181106108fb576108fb610d60565b905060200281019061090d9190610e42565b925061091c6020840184610ce2565b73ffffffffffffffffffffffffffffffffffffffff1661093f6020850185610dcd565b60405161094d929190610e32565b6000604051808303816000865af19150503d806000811461098a576040519150601f19603f3d011682016040523d82523d6000602084013e61098f565b606091505b506020830152151581528715610a07578051610a07576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601760248201527f4d756c746963616c6c333a2063616c6c206661696c656400000000000000000060448201526064016104dd565b506001016108c3565b5050509392505050565b6000806060610a2b60018686610690565b919790965090945092505050565b60008083601f840112610a4b57600080fd5b50813567ffffffffffffffff811115610a6357600080fd5b6020830191508360208260051b8501011115610a7e57600080fd5b9250929050565b60008060208385031215610a9857600080fd5b823567ffffffffffffffff811115610aaf57600080fd5b610abb85828601610a39565b90969095509350505050565b6000815180845260005b81811015610aed57602081850181015186830182015201610ad1565b81811115610aff576000602083870101525b50601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0169290920160200192915050565b600082825180855260208086019550808260051b84010181860160005b84811015610bb1578583037fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe001895281518051151584528401516040858501819052610b9d81860183610ac7565b9a86019a9450505090830190600101610b4f565b5090979650505050505050565b602081526000610bd16020830184610b32565b9392505050565b600060408201848352602060408185015281855180845260608601915060608160051b870101935082870160005b82811015610c52577fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa0888703018452610c40868351610ac7565b95509284019290840190600101610c06565b509398975050505050505050565b600080600060408486031215610c7557600080fd5b83358015158114610c8557600080fd5b9250602084013567ffffffffffffffff811115610ca157600080fd5b610cad86828701610a39565b9497909650939450505050565b838152826020820152606060408201526000610cd96060830184610b32565b95945050505050565b600060208284031215610cf457600080fd5b813573ffffffffffffffffffffffffffffffffffffffff81168114610bd157600080fd5b600060208284031215610d2a57600080fd5b5035919050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052604160045260246000fd5b7f4e487b7100000000000000000000000000000000000000000000000000000000600052603260045260246000fd5b600082357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff81833603018112610dc357600080fd5b9190910192915050565b60008083357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe1843603018112610e0257600080fd5b83018035915067ffffffffffffffff821115610e1d57600080fd5b602001915036819003821315610a7e57600080fd5b8183823760009101908152919050565b600082357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc1833603018112610dc357600080fd5b600082357fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa1833603018112610dc357600080fdfea2646970667358221220bb2b5c71a328032f97c676ae39a1ec2148d3e5d6f73d95e9b17910152d61f16264736f6c634300080c0033";
    }

    /// @notice Helper to concatenate a string and an address
    function _concat(string memory a, address b) internal pure returns (string memory) {
        return LibString.concat(a, LibString.toHexStringChecksummed(b));
    }
}
