// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {DeployDscScript} from "../../script/DeployDsc.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
  DeployDscScript deployer;
  DSCEngine dsce;
  DecentralizedStableCoin dsc;
  HelperConfig config;
  address ethUsdPriceFeedAddress;
  address btcUsdPriceFeedAddress;
  address weth;
  address wbtc;

  address public user = makeAddr("user");
  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

  function setUp() public {
    deployer = new DeployDscScript();
    (dsce, dsc, config) = deployer.run();
    (ethUsdPriceFeedAddress, btcUsdPriceFeedAddress, weth, wbtc,) = config.activeNetworkConfig();

    ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
    ERC20Mock(wbtc).mint(user, STARTING_ERC20_BALANCE);
  }

  ///////////////////////////
  //// Initialization ///////
  ///////////////////////////
  function test_dsce_engine_is_initialized() public view {
    assertEq(address(dsce.getDecentralizedStableCoin()), address(dsc));
  }

  function testValuesAreThere() public view {
    console2.log("weth", weth);
    console2.log("wbtc", wbtc);
    console2.log("ethUsdPriceFeedAddress", ethUsdPriceFeedAddress);
    console2.log("btcUsdPriceFeedAddress", btcUsdPriceFeedAddress);
    assertFalse(weth == address(0));
    assertFalse(wbtc == address(0));
    assertFalse(ethUsdPriceFeedAddress == address(0));
    assertFalse(btcUsdPriceFeedAddress == address(0));
  }

  function test_dsce_engine_has_tokens() public view {
    assertEq(dsce.getCollateralTokens()[0], address(weth));
    assertEq(dsce.getCollateralTokens()[1], address(wbtc));
  }

  ///////////////////////////
  //// Price Tests //////////
  ///////////////////////////
  function testGetUsdValue() public view {
    uint256 ethAmount = 1 ether;
    uint256 expectedUsd = 2000e18;
    uint256 actualUsd = dsce.getUsdValueOfCollateral(address(weth), ethAmount);
    assertEq(actualUsd, expectedUsd);
  }

  //////////////////////////////////
  //// DepositCollateral Tests /////
  //////////////////////////////////
  function testRevertsIfStartMintingWithZeroCollateral() public {
    vm.startPrank(user);
    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    dsce.mintDsc(0);
    vm.stopPrank();
  }

  function testRevertsIfCollateralIsZero() public {
    vm.startPrank(user);
    console2.log("balance ether:");
    console2.log(address(user).balance);
    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    dsce.depositCollateral(weth, 0);
    vm.stopPrank();
  }
}
