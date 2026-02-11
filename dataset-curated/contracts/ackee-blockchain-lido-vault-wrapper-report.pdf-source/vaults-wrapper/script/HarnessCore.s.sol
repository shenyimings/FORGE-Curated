// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

interface IHashConsensus {
    function updateInitialEpoch(uint256 initialEpoch) external;
}

/// @notice Prepares Lido core locally to match CoreHarness setup used in tests
/// - sets initial epoch on HashConsensus
/// - sets Lido max external ratio to 100% and resumes
/// - funds Lido with a large initial submit to pass share-limit checks
/// Requires an agent key with permissions to call Lido setters and HashConsensus;
/// on Anvil use any pre-funded key that matches the agent account in deployed-local.json
contract HarnessCore is Script {
    function run() external {
        string memory locatorAddressStr = vm.envString("CORE_LOCATOR_ADDRESS");
        string memory rpcUrl = vm.envOr("RPC_URL", string("http://localhost:9123"));
        uint256 initialSubmit = vm.envOr("INITIAL_LIDO_SUBMISSION", uint256(20_000 ether));

        address locator = vm.parseAddress(locatorAddressStr);

        // Discover stETH from Locator
        (bool lidoOk, address steth) = _safeStaticCallAddr(locator, abi.encodeWithSignature("lido()"));
        require(lidoOk && steth != address(0), "locator.lido() unavailable");

        // Discover Agent (Aragon) from Locator proxy admin
        (bool agentOk, address agent) = _safeStaticCallAddr(locator, abi.encodeWithSignature("proxy__getAdmin()"));
        require(agentOk && agent != address(0), "locator.proxy__getAdmin() unavailable");

        // Discover HashConsensus for AccountingOracle via Locator
        (bool aoOk, address accountingOracle) =
            _safeStaticCallAddr(locator, abi.encodeWithSignature("accountingOracle()"));
        require(aoOk && accountingOracle != address(0), "locator.accountingOracle() unavailable");
        (bool hcOk, address hashConsensus) =
            _safeStaticCallAddr(accountingOracle, abi.encodeWithSignature("getConsensusContract()"));
        require(hcOk && hashConsensus != address(0), "getConsensusContract() unavailable");

        // 1) Impersonate agent on local Anvil
        _cast(_arr6("cast", "rpc", "anvil_impersonateAccount", vm.toString(agent), "--rpc-url", rpcUrl));

        // 1.1) Fund agent to cover value + gas
        _cast(
            _arr7("cast", "rpc", "anvil_setBalance", vm.toString(agent), "0x3635C9ADC5DEA0000000", "--rpc-url", rpcUrl)
        ); // ~256,000 ETH

        // 2) (optional) updateInitialEpoch(1) on HashConsensus — skipped by default
        // This call may revert depending on current core state/permissions. Enable if needed.
        // _cast(_arr10(
        //     "cast","send",
        //     "--from", vm.toString(a.agent),
        //     "--unlocked",
        //     vm.toString(hashConsensus),
        //     "updateInitialEpoch(uint256)",
        //     "1",
        //     "--rpc-url", rpcUrl
        // ));

        // 3) Lido.setMaxExternalRatioBP(10000) (best-effort; ok if already 10000)
        _cast(
            _arr10(
                "cast",
                "send",
                "--from",
                vm.toString(agent),
                "--unlocked",
                vm.toString(steth),
                "setMaxExternalRatioBP(uint256)",
                "10000",
                "--rpc-url",
                rpcUrl
            )
        );

        // 4) Resume pool ops, lift staking limit, and resume staking (best-effort)
        _cast(
            _arr9(
                "cast",
                "send",
                "--from",
                vm.toString(agent),
                "--unlocked",
                vm.toString(steth),
                "resume()",
                "--rpc-url",
                rpcUrl
            )
        );
        _cast(
            _arr9(
                "cast",
                "send",
                "--from",
                vm.toString(agent),
                "--unlocked",
                vm.toString(steth),
                "removeStakingLimit()",
                "--rpc-url",
                rpcUrl
            )
        );
        _cast(
            _arr9(
                "cast",
                "send",
                "--from",
                vm.toString(agent),
                "--unlocked",
                vm.toString(steth),
                "resumeStaking()",
                "--rpc-url",
                rpcUrl
            )
        );

        // 5) Lido.submit(agent) with value initialSubmit (best-effort)
        _cast(
            _arr12(
                "cast",
                "send",
                "--from",
                vm.toString(agent),
                "--unlocked",
                "--value",
                vm.toString(initialSubmit),
                vm.toString(steth),
                "submit(address)",
                vm.toString(agent),
                "--rpc-url",
                rpcUrl
            )
        );

        console2.log("Harnessed core via impersonation:");
        console2.log(" locator:", locator);
        console2.log(" stETH:", steth);
        console2.log(" hashConsensus:", hashConsensus);
        console2.log(" agent:", agent);
        console2.log(" submitted:", initialSubmit);
        (bool tsOk, uint256 ts) = _safeStaticCallUint(steth, abi.encodeWithSignature("getTotalShares()"));
        if (tsOk) {
            console2.log(" total shares:", ts);
        } else {
            console2.log(" total shares: unknown");
        }
    }

    function _cast(string[] memory args) internal {
        vm.ffi(args);
    }

    function _safeStaticCallUint(address target, bytes memory data) private view returns (bool ok, uint256 value) {
        (bool success, bytes memory ret) = target.staticcall(data);
        if (!success || ret.length < 32) return (false, 0);
        return (true, abi.decode(ret, (uint256)));
    }

    function _safeStaticCallBool(address target, bytes memory data) private view returns (bool ok, bool value) {
        (bool success, bytes memory ret) = target.staticcall(data);
        if (!success || ret.length < 32) return (false, false);
        return (true, abi.decode(ret, (bool)));
    }

    function _safeStaticCallAddr(address target, bytes memory data) private view returns (bool ok, address value) {
        (bool success, bytes memory ret) = target.staticcall(data);
        if (!success || ret.length < 32) return (false, address(0));
        return (true, abi.decode(ret, (address)));
    }

    function _arr6(string memory a, string memory b, string memory c, string memory d, string memory e, string memory f)
        private
        pure
        returns (string[] memory r)
    {
        r = new string[](6);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
    }

    function _arr9(
        string memory a,
        string memory b,
        string memory c,
        string memory d,
        string memory e,
        string memory f,
        string memory g,
        string memory h,
        string memory i
    ) private pure returns (string[] memory r) {
        r = new string[](9);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
        r[7] = h;
        r[8] = i;
    }

    function _arr10(
        string memory a,
        string memory b,
        string memory c,
        string memory d,
        string memory e,
        string memory f,
        string memory g,
        string memory h,
        string memory i,
        string memory j
    ) private pure returns (string[] memory r) {
        r = new string[](10);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
        r[7] = h;
        r[8] = i;
        r[9] = j;
    }

    function _arr12(
        string memory a,
        string memory b,
        string memory c,
        string memory d,
        string memory e,
        string memory f,
        string memory g,
        string memory h,
        string memory i,
        string memory j,
        string memory k,
        string memory l
    ) private pure returns (string[] memory r) {
        r = new string[](12);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
        r[7] = h;
        r[8] = i;
        r[9] = j;
        r[10] = k;
        r[11] = l;
    }

    function _arr7(
        string memory a,
        string memory b,
        string memory c,
        string memory d,
        string memory e,
        string memory f,
        string memory g
    ) private pure returns (string[] memory r) {
        r = new string[](7);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
    }

    function _arr13(
        string memory a,
        string memory b,
        string memory c,
        string memory d,
        string memory e,
        string memory f,
        string memory g,
        string memory h,
        string memory i,
        string memory j,
        string memory k,
        string memory l,
        string memory m
    ) private pure returns (string[] memory r) {
        r = new string[](13);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
        r[7] = h;
        r[8] = i;
        r[9] = j;
        r[10] = k;
        r[11] = l;
        r[12] = m;
    }

    function _arr14(
        string memory a,
        string memory b,
        string memory c,
        string memory d,
        string memory e,
        string memory f,
        string memory g,
        string memory h,
        string memory i,
        string memory j,
        string memory k,
        string memory l,
        string memory m,
        string memory n
    ) private pure returns (string[] memory r) {
        r = new string[](14);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
        r[7] = h;
        r[8] = i;
        r[9] = j;
        r[10] = k;
        r[11] = l;
        r[12] = m;
        r[13] = n;
    }

    function _arr16(
        string memory a,
        string memory b,
        string memory c,
        string memory d,
        string memory e,
        string memory f,
        string memory g,
        string memory h,
        string memory i,
        string memory j,
        string memory k,
        string memory l,
        string memory m,
        string memory n,
        string memory o,
        string memory p
    ) private pure returns (string[] memory r) {
        r = new string[](16);
        r[0] = a;
        r[1] = b;
        r[2] = c;
        r[3] = d;
        r[4] = e;
        r[5] = f;
        r[6] = g;
        r[7] = h;
        r[8] = i;
        r[9] = j;
        r[10] = k;
        r[11] = l;
        r[12] = m;
        r[13] = n;
        r[14] = o;
        r[15] = p;
    }
}
