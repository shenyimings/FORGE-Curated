// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../../lib/common/src/libs/ContinuousIndexingMath.sol";
import { Upgrades, UnsafeUpgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMExtension } from "../../src/interfaces/IMExtension.sol";
import { IMTokenLike } from "../../src/interfaces/IMTokenLike.sol";
import { IRegistrarLike } from "../../src/swap/interfaces/IRegistrarLike.sol";

import { MYieldToOne } from "../../src/projects/yieldToOne/MYieldToOne.sol";
import { MYieldFee } from "../../src/projects/yieldToAllWithFee/MYieldFee.sol";
import { MEarnerManager } from "../../src/projects/earnerManager/MEarnerManager.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";
import { UniswapV3SwapAdapter } from "../../src/swap/UniswapV3SwapAdapter.sol";

import { Helpers } from "./Helpers.sol";

contract BaseIntegrationTest is Helpers, Test {
    address public constant standardGovernor = 0xB024aC5a7c6bC92fbACc8C3387E628a07e1Da016;
    address public constant registrar = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;

    IMTokenLike public constant mToken = IMTokenLike(0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b);

    uint16 public constant YIELD_FEE_RATE = 2000; // 20%

    bytes32 internal constant EARNERS_LIST = "earners";
    uint32 public constant M_EARNER_RATE = ContinuousIndexingMath.BPS_SCALED_ONE / 10; // 10% APY

    uint56 public constant EXP_SCALED_ONE = 1e12;

    // Large M holder on Ethereum Mainnet
    address public constant mSource = 0x3f0376da3Ae4313E7a5F1dA184BAFC716252d759;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant YIELD_RECIPIENT_MANAGER_ROLE = keccak256("YIELD_RECIPIENT_MANAGER_ROLE");
    bytes32 public constant EARNER_MANAGER_ROLE = keccak256("EARNER_MANAGER_ROLE");
    bytes32 public constant M_SWAPPER_ROLE = keccak256("M_SWAPPER_ROLE");

    address constant WRAPPED_M = 0x437cc33344a0B27A429f795ff6B469C72698B291;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant UNISWAP_V3_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address public admin = makeAddr("admin");
    address public blacklistManager = makeAddr("blacklistManager");
    address public yieldRecipient = makeAddr("yieldRecipient");
    address public yieldRecipientManager = makeAddr("yieldRecipientManager");
    address public yieldFeeManager = makeAddr("yieldFeeManager");
    address public claimRecipientManager = makeAddr("claimRecipientManager");
    address public earnerManager = makeAddr("earnerManager");
    address public feeRecipient = makeAddr("feeRecipient");

    address public alice;
    uint256 public aliceKey;

    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public charlie = makeAddr("charlie");
    address public david = makeAddr("david");

    address[] public accounts = [alice, bob, carol, charlie, david];

    MYieldToOne public mYieldToOne;
    MYieldFee public mYieldFee;
    MEarnerManager public mEarnerManager;
    SwapFacility public swapFacility;
    UniswapV3SwapAdapter public swapAdapter;

    string public constant NAME = "M USD Extension";
    string public constant SYMBOL = "MUSDE";

    function setUp() public virtual {
        (alice, aliceKey) = makeAddrAndKey("alice");
        accounts = [alice, bob, carol, charlie, david];

        address[] memory whitelistedTokens = new address[](3);
        whitelistedTokens[0] = WRAPPED_M;
        whitelistedTokens[1] = USDC;
        whitelistedTokens[2] = USDT;

        swapAdapter = new UniswapV3SwapAdapter(
            WRAPPED_M, // baseToken (wrapped M)
            UNISWAP_V3_ROUTER,
            admin,
            whitelistedTokens
        );

        swapFacility = SwapFacility(
            UnsafeUpgrades.deployUUPSProxy(
                address(new SwapFacility(address(mToken), address(registrar), address(swapAdapter))),
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin)
            )
        );

        vm.startPrank(admin);

        swapFacility.grantRole(M_SWAPPER_ROLE, alice);
        swapFacility.grantRole(M_SWAPPER_ROLE, bob);
        swapFacility.grantRole(M_SWAPPER_ROLE, feeRecipient);

        vm.stopPrank();
    }

    function _addToList(bytes32 list, address account) internal {
        vm.prank(standardGovernor);
        IRegistrarLike(registrar).addToList(list, account);
    }

    function _removeFomList(bytes32 list, address account) internal {
        vm.prank(standardGovernor);
        IRegistrarLike(registrar).removeFromList(list, account);
    }

    function _giveM(address account, uint256 amount) internal {
        vm.prank(mSource);
        mToken.transfer(account, amount);
    }

    function _giveEth(address account, uint256 amount) internal {
        vm.deal(account, amount);
    }

    function _swapInM(address mExtension, address account, address recipient, uint256 amount) internal {
        vm.prank(account);
        mToken.approve(address(swapFacility), amount);

        vm.prank(account);
        swapFacility.swapInM(mExtension, amount, recipient);
    }

    function _swapInMWithPermitVRS(
        address mExtension,
        address account,
        uint256 signerPrivateKey,
        address recipient,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _getPermit(
            address(swapFacility),
            account,
            signerPrivateKey,
            amount,
            nonce,
            deadline
        );

        vm.prank(account);
        swapFacility.swapInMWithPermit(mExtension, amount, recipient, deadline, v_, r_, s_);
    }

    function _swapMOut(address mExtension, address account, address recipient, uint256 amount) internal {
        vm.prank(account);
        IMExtension(mExtension).approve(address(swapFacility), amount);

        vm.prank(account);
        swapFacility.swapOutM(mExtension, amount, recipient);
    }

    function _set(bytes32 key, bytes32 value) internal {
        vm.prank(standardGovernor);
        IRegistrarLike(registrar).setKey(key, value);
    }

    function _fundAccounts() internal {
        for (uint256 i = 0; i < accounts.length; ++i) {
            _giveM(accounts[i], 10e6);
            _giveEth(accounts[i], 0.1 ether);
        }
    }

    /* ============ utils ============ */

    function _makeKey(string memory name_) internal returns (uint256 key_) {
        (, key_) = makeAddrAndKey(name_);
    }

    function _getPermit(
        address mExtension,
        address account,
        uint256 signerPrivateKey,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v_, bytes32 r_, bytes32 s_) {
        return
            vm.sign(
                signerPrivateKey,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        mToken.DOMAIN_SEPARATOR(),
                        keccak256(abi.encode(mToken.PERMIT_TYPEHASH(), account, mExtension, amount, nonce, deadline))
                    )
                )
            );
    }
}
