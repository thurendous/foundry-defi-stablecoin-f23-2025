// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDscScript} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDscScript deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;
    HelperConfig config;
    address ethUsdPriceFeedAddress;
    address btcUsdPriceFeedAddress;
    Handler handler;

    function setUp() public {
        deployer = new DeployDscScript();
        (dsce, dsc, config) = deployer.run();
        (ethUsdPriceFeedAddress, btcUsdPriceFeedAddress, weth, wbtc,) = config.activeNetworkConfig();
        // console2.log("ethUsdPriceFeedAddress", ethUsdPriceFeedAddress);
        // console2.log("btcUsdPriceFeedAddress", btcUsdPriceFeedAddress);
        // console2.log("weth", weth);
        // console2.log("wbtc", wbtc);
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
        console2.log("target address", address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to the total supply of the debt (dsc)
        // assert that the protocol has more value than the total supply of the debt
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        uint256 wethValue = dsce.getUsdValueOfCollateral(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValueOfCollateral(wbtc, totalBtcDeposited);


        console2.log("totalSupply", totalSupply);
        console2.log("wethValue", wethValue);
        console2.log("wbtcValue", wbtcValue);
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
