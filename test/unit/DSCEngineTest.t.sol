// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {DeployDscScript} from "../../script/DeployDsc.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

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
  address public liquidator = makeAddr("liquidator");
  uint256 public constant AMOUNT_COLLATERAL = 1 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
  uint256 public constant STARTING_DSC_BALANCE = 1000e18;

  // for testing
  address[] public tokenAddresses;
  address[] public priceFeedAddresses;

  function setUp() public {
    deployer = new DeployDscScript();
    (dsce, dsc, config) = deployer.run();
    (ethUsdPriceFeedAddress, btcUsdPriceFeedAddress, weth, wbtc,) = config.activeNetworkConfig();

    ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
    ERC20Mock(wbtc).mint(user, STARTING_ERC20_BALANCE);
    ERC20Mock(weth).mint(liquidator, STARTING_ERC20_BALANCE * 2);
  }

  ///////////////////////////
  //// constructor //////////
  ///////////////////////////
  function testRevertsIfTokenLengthDoesntMatchPriceFeedsLength() public {
    tokenAddresses.push(weth);
    tokenAddresses.push(wbtc);
    priceFeedAddresses.push(ethUsdPriceFeedAddress);
    vm.expectRevert(DSCEngine.DSCEngine__MismatchLength.selector);
    new DSCEngine(address(dsc), tokenAddresses, priceFeedAddresses);
  }

  function testRevertsIfTokenLengthDoesntMatchPriceFeedsLength2() public {
    tokenAddresses.push(weth);
    priceFeedAddresses.push(ethUsdPriceFeedAddress);
    priceFeedAddresses.push(btcUsdPriceFeedAddress);
    vm.expectRevert(DSCEngine.DSCEngine__MismatchLength.selector);
    new DSCEngine(address(dsc), tokenAddresses, priceFeedAddresses);
  }

  function testGetTokenAmountFromUsd() public view {
    uint256 usdAmount = 1000 ether;
    uint256 expectedWethAmount = 0.5 ether;
    uint256 actualWethAmount = dsce.getTokenAmountFromUsd(weth, usdAmount);
    assertEq(actualWethAmount, expectedWethAmount);
  }

  function testRevertsWithApprovedCollateralOfZeroAmount() public {
    vm.startPrank(user);
    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    dsce.depositCollateral(weth, 0);
    vm.stopPrank();
  }

  function testRevertsWithUnapprovedCollateral() public {
    ERC20Mock someToken = new ERC20Mock("SomeToken", "SomeToken", user, 1000e8);
    vm.startPrank(user);
    ERC20Mock(someToken).approve(address(dsce), AMOUNT_COLLATERAL);
    vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(someToken)));
    dsce.depositCollateral(address(someToken), 1);
    vm.stopPrank();
  }

  function testCanDepositCollateralAndGetAccountInfo() public depositCollateral(user) {
    (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dsce.getAccountInformation(user);
    uint256 expectedDscMinted = 0;
    uint256 expectedCollateralValueInUsd = 2000e18;
    assertEq(totalDscMinted, expectedDscMinted);
    assertEq(totalCollateralValueInUsd, expectedCollateralValueInUsd);
  }

  modifier depositCollateral(address _user) {
    vm.startPrank(_user);
    // approve the engine to spend the collateral. This is a MUST.
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
    _;
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

  function testCanMintDsc() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    dsce.mintDsc(1000e18);
    vm.stopPrank();
  }

  function testCanBurnDsc() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    dsce.mintDsc(STARTING_DSC_BALANCE);
    dsc.approve(address(dsce), STARTING_DSC_BALANCE);
    dsce.burnDsc(STARTING_DSC_BALANCE);
    vm.stopPrank();
  }

  //////////////////////////////////
  //// HealthFactor Tests //////////
  //////////////////////////////////

  function testRevertsIfHealthFactorIsBroken() public depositCollateral(user) {
    uint256 expectedHealthFactor = dsce.calculateHealthFactor(2000e18, 2000e18);
    vm.startPrank(user);
    vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, expectedHealthFactor));
    dsce.mintDsc(2000e18);
    vm.stopPrank();
  }

  function testLiquidationFunctionality() public depositCollateral(user) depositCollateral(liquidator) {
    vm.startPrank(user);
    dsce.mintDsc(1000e18);
    // user give 1 ether of dsc to the liquidator
    dsc.transfer(liquidator, 1 ether);
    vm.stopPrank();

    // mimic the price of the weth which drops to 1000
    MockV3Aggregator(ethUsdPriceFeedAddress).updateAnswer(1800e8);

    vm.startPrank(liquidator);
    dsc.approve(address(dsce), 1 ether);
    dsce.liquidate(weth, user, 1 ether);
    vm.stopPrank();
  }
}
