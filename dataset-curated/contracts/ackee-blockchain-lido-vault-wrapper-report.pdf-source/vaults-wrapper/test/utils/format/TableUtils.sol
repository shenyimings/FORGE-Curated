// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IStETH} from "src/interfaces/core/IStETH.sol";
import {IWstETH} from "src/interfaces/core/IWstETH.sol";
import {IBoringOnChainQueue} from "src/interfaces/ggv/IBoringOnChainQueue.sol";

interface IWrapper {
    function balanceOf(address account) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function getStethShares(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function mintedStethSharesOf(address _account) external view returns (uint256 stethShares);
}

library TableUtils {
    using SafeCast for uint256;
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Context {
        IWrapper pool;
        IERC20 boringVault;
        IStETH steth;
        IWstETH wsteth;
        IBoringOnChainQueue boringQueue;
    }

    struct User {
        address user;
        string name;
    }

    function init(
        Context storage self,
        address _pool,
        address _boringVault,
        address _steth,
        address _wsteth,
        address _boringQueue
    ) internal {
        self.pool = IWrapper(_pool);
        self.boringVault = IERC20(_boringVault);
        self.steth = IStETH(_steth);
        self.wsteth = IWstETH(_wsteth);
        self.boringQueue = IBoringOnChainQueue(_boringQueue);
    }

    function printHeader(string memory title) internal pure {
        console.log();
        console.log();
        console.log(title);
        console.log(
            unicode"───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
        );
        printColumnHeaders();
    }

    function printColumnHeaders() internal pure {
        console.log(
            string.concat(
                padRight("user", 16),
                padLeft("balance", 20),
                padLeft("stv", 20),
                padLeft("eth", 20),
                padLeft("debt.stethShares", 20),
                padLeft("ggv", 20),
                padLeft("ggv.wstETHOut", 20),
                padLeft("wstETH", 20)
            )
        );
        console.log(
            unicode"───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
        );
    }

    function printUsers(Context storage self, string memory title, User[] memory _addresses, uint256 _discount)
        internal
        view
    {
        printHeader(title);

        for (uint256 i = 0; i < _addresses.length; i++) {
            printUserRow(self, _addresses[i].name, _addresses[i].user, _discount);
        }

        uint256 stethShareRate = self.steth.getPooledEthByShares(1e18);

        console.log(
            unicode"─────────────────────────────────────────────────"
        );
        console.log("  stETH Share Rate:", formatETH(stethShareRate));
        console.log("pool totalSupply", formatETH(self.pool.totalSupply()));
        console.log("pool totalAssets", formatETH(self.pool.totalAssets()));
    }

    function printUserRow(Context storage self, string memory userName, address _user, uint256 _discount)
        internal
        view
    {
        uint256 balance = _user.balance;
        uint256 stv = self.pool.balanceOf(_user);
        uint256 assets = self.pool.previewRedeem(stv);
        uint256 debtSteth = self.pool.mintedStethSharesOf(_user);
        uint256 ggv = self.boringVault.balanceOf(_user);
        uint256 ggvStethOut =
            self.boringQueue.previewAssetsOut(address(self.wsteth), ggv.toUint128(), _discount.toUint16());
        uint256 wsteth = self.wsteth.balanceOf(_user);

        console.log(
            string.concat(
                padRight(userName, 16),
                padLeft(VM.toString(balance), 24),
                padLeft(formatETH(stv), 20),
                padLeft(formatETH(assets), 20),
                padLeft(VM.toString(debtSteth), 20),
                padLeft(VM.toString(ggv), 20),
                padLeft(VM.toString(ggvStethOut), 20),
                padLeft(VM.toString(wsteth), 20)
            )
        );
    }

    function formatETH(uint256 weiAmount) internal pure returns (string memory) {
        return formatWithDecimals(weiAmount, 18);
    }

    function formatWithDecimals(uint256 amount, uint256 decimals) internal pure returns (string memory) {
        if (amount == 0) return "0.00";

        uint256 divisor = 10 ** decimals;
        uint256 integerPart = amount / divisor;
        uint256 fractionalPart = amount % divisor;

        uint256 scaledFractional = fractionalPart / (divisor / 100);

        return string.concat(VM.toString(integerPart), ".", padWithZeros(VM.toString(scaledFractional), 2));
    }

    function padWithZeros(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        bytes memory result = new bytes(length);
        uint256 i;

        for (i = 0; i < length - strBytes.length; i++) {
            result[i] = "0";
        }

        for (uint256 j = 0; j < strBytes.length; j++) {
            result[i + j] = strBytes[j];
        }

        return string(result);
    }

    function padRight(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        bytes memory result = new bytes(length);
        uint256 i;
        for (i = 0; i < strBytes.length; i++) {
            result[i] = strBytes[i];
        }
        for (; i < length; i++) {
            result[i] = " ";
        }
        return string(result);
    }

    function padLeft(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        bytes memory result = new bytes(length);
        uint256 padding = length - strBytes.length;
        uint256 i;
        for (i = 0; i < padding; i++) {
            result[i] = " ";
        }
        for (uint256 j = 0; j < strBytes.length; j++) {
            result[i + j] = strBytes[j];
        }
        return string(result);
    }
}
