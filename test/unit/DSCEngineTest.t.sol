// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {StdCheats} from "forge-std/StdCheats.sol";



contract DSCEngineTest is StdCheats, Test {
    
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address token, uint256 amount); // if redeemFrom != redeemedTo, then it was liquidated
    
    
    
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    address public USER = makeAddr("user");
    address public ALICE = makeAddr("alice");
    uint256 public amountCollateral = 10 ether;
    uint256 public amountToMint = 100 ether; // We put 100 ether but it simulates that we want to mint $100
    
    
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;



    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(USER, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
        

    }


    /////////////////////////
    /// Modifiers        ////
    /////////////////////////

    
    modifier depositCollateralAndMint() {
        vm.startPrank(USER);
        // In order to deposit weth we need to approve
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.despositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        // In order to deposit weth we need to approve
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }
    
    
    
    
    /////////////////////////
    /// Constructor test ////
    /////////////////////////

    function testRevertsIfTokenLenghtDoesntMatchPriceFeeds() public {
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed, btcUsdPriceFeed];
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLenght.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        vm.stopPrank();
        
    }







    ///////////////////
    /// Price Test ////
    ///////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 *2000 ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $2000 = 1 ETH, $100 --> 0.05
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }




    ////////////////////////////////
    /// depositCollateral Tests ////
    ////////////////////////////////

    // This test needs its own setUp

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, amountCollateral);

        mockDsc.transferOwnership(address(mockDscEngine));
        vm.stopPrank();

        vm.startPrank(USER);
        // I'm approving that the engineDsc (mockDscEngine) can tranfer DscTokens (mockDsc) to the contract itself, this tokens are from the user (USER) and the contract
        // engine can take it from him because the one that is calling it the approve function is the USER.
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.depositCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();

    }
    
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();

    }


    // Here we create a new token, is has its own address, but it revert with this condition:
    // if (s_priceFeed[token] == address(0)) {revert DSCEnginge__NotAllowedToken}
    // It doesn't mean that the ranToken is the address(0) itself, with this condition we say that when some token doens't have it's own priceFeed linked then revert.
    // Because we have to pass the token addresses and the priceAddresses linked in the constructor
    function testRevertsWithUnapprovedCollateral() public {
        
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, amountCollateral);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), amountCollateral);
        vm.stopPrank();
    }


    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userDscBalance = dsc.balanceOf(USER);
        uint256 userCollateralBalance = engine.getCollateralDepositedOfUser(USER, weth);
        assertEq(userDscBalance, 0);
        assertEq(userCollateralBalance, amountCollateral);
    }

    

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        // AMOUNT COLLATERAL = 10 ether * $2000 (default price set in the mock) = 20.000.000000000000000000 
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValue = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        uint256 expectedCollateralValueInUsd = engine.getUsdValue(weth, amountCollateral);
        // AMOUNT COLLATERAL = 10.000000000000000000
        assertEq(amountCollateral, expectedCollateralValue);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(expectedCollateralValueInUsd, collateralValueInUsd);

    }


    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////



    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * engine.getAditionalFeedPrecision())) / engine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);

        uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.despositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }


    
    
    function testDepositCollateralAndMintDsc() public depositCollateralAndMint {

        uint256 expectedCollateralValue = amountCollateral;
        uint256 expectedDscMinted = amountToMint;

        assertEq(expectedCollateralValue, engine.getCollateralDepositedOfUser(USER, weth));
        assertEq(expectedDscMinted, engine.getDscMinted(USER));
    }



    //////////////////////
    // mintDsc Tests    //
    //////////////////////


    // Needs it's own custom setUp()

    function testRevertsIfMintFail() public {
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedMintDSC mockMint = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockMint));
        
        mockMint.transferOwnership(address(mockDscEngine));
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDscEngine), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDscEngine.despositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();


    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        amountToMint = 0;
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.despositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
    }


    // This is very similar to the test: testRevertsIfMintedDscBreaksHealthFactor() but the only difference is that we deposit collateral using the modifier and then we mint
    // independently the amountDSC that should break the health factor because are the same amount in USD (20000e18);
    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * engine.getAditionalFeedPrecision())) / engine.getPrecision();
        
        vm.startPrank(USER);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintDsc(amountToMint);
        uint256 expectedMintedAmount = amountToMint;
        uint256 actualMintedAmount = engine.getDscMinted(USER);
        assertEq(expectedMintedAmount, actualMintedAmount);
    }


    // Finish this!!!!!!!!!

    /*function testRevertsWhenTransferFailInDepositCollateral() public {
        vm.startPrank(USER);
        // In order to deposit weth we need to approve
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TranferFailed.selector);
        engine.depositCollateral(weth, 11 ether);
        vm.stopPrank();
    }*/



    


    //////////////////////////////
    /// Redeem and Burn tests ////
    //////////////////////////////


    function testRevertsIfBurnAmountIsZero() public depositCollateralAndMint {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.burnDsc(0);
    }


    function testCanBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        engine.burnDsc(1);
    }


    function testCanBurnDsc() public depositCollateralAndMint {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        engine.burnDsc(amountToMint);
        uint256 expectedMintedDsc = 0;
        uint256 actualMintedDsc = engine.getDscMinted(USER);
        vm.stopPrank();
        assertEq(expectedMintedDsc, actualMintedDsc);
    }

    function testRevertsIfTranferFails() public {
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransfer mockTransfer = new MockFailedTransfer();
        tokenAddresses = [address(mockTransfer)];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockTransfer));
        mockTransfer.mint(USER, amountCollateral);
        mockTransfer.transferOwnership(address(mockEngine));
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(address(mockTransfer)).approve(address(mockEngine), amountCollateral);

        mockEngine.depositCollateral(address(mockTransfer), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.redeemCollateral(address(mockTransfer), amountCollateral);
        vm.stopPrank();

    }

    
    function testRevertsIfRedeemAmountIsZero() public depositCollateralAndMint {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }


    function testCanRedeemCollateral() public depositCollateralAndMint {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, amountCollateral);
        uint256 expectedCollateral = 0;
        uint256 actualCollateral = engine.getCollateralDepositedOfUser(weth, USER);
        assertEq(expectedCollateral, actualCollateral);
    }


    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, false, false, address(engine));
        emit CollateralRedeemed(USER, USER, weth, amountCollateral);
        vm.prank(USER);
        engine.redeemCollateral(weth, amountCollateral);
    }



    function testRedeemCollateralForDscMoreThanZero() public depositCollateralAndMint {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.redeemCollateralForDsc(weth, 0, amountToMint);
        vm.stopPrank();
    }

    

    function testRedeemCollateralAndBurnDsc() public depositCollateralAndMint {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        //vm.expectRevert(DSCEngine.DSCEngine__DscOrCollateralIsZero.selector);
        engine.redeemCollateralForDsc(weth, amountCollateral, amountToMint);
        
        
        uint256 expectedCollateral = 0;
        uint256 expectedDscMinted = 0;
        uint256 actualCollateral = engine.getAccountCollateralValue(USER);
        uint256 actualDscMinted = engine.getDscMinted(USER);
        assertEq(expectedCollateral, actualCollateral);
        assertEq(expectedDscMinted, actualDscMinted);

        vm.stopPrank();

    }



    /////////////////////////
    /// Health factor test ////
    /////////////////////////

    

    function testProperlyReportsHealthFactor() public depositCollateralAndMint {
        uint256 expectedHEalthfactor = 100 ether;
        uint256 actualHealthFactor = engine.getHealthfactor(USER);
        // 100$ minted with 20000 collateral at 50% liquidation threshold
        // means taht we must have $200 collateral at all times
        // 20000 * 0.5 = 10000
        // 10000 / 100 = 100 health factor 

        assertEq(expectedHEalthfactor, actualHealthFactor);
    }


    function testHealthFactorCanGoBelowOne() public depositCollateralAndMint {
        int256 ethUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember we need $200 at all times if we have $100 of debt
        // 10 ether * 18 = $180

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthfactor(USER);

        assert(userHealthFactor < 1e18);
    }

    
    
    
    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setUp

    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange setUp
        MockMoreDebtDSC mockDebt = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDebt));
        mockDebt.transferOwnership(address(mockEngine));

        // Arrange - user
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), amountCollateral);
        mockEngine.despositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockEngine), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockEngine.despositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        mockDebt.approve(address(mockEngine), debtToCover);

        // ACT
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH --> $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Act assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockEngine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();



    }




    function testRevertsLiquidationIfHealthFactorIsOk() public depositCollateralAndMint {
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        
        vm.startPrank(liquidator);
        // In order to deposit weth we need to approve
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.despositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOK.selector);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        // Arrange user
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.despositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Update price of weth
        int256 updatedPriceWeth = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(updatedPriceWeth);
        uint256 userHealthFactor = engine.getHealthfactor(USER);

        // Arrange liquidator
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.despositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
        _;
    }



    function testLiquidation() public liquidated {
        uint256 amountLiquidated = engine.getTokenAmountFromUsd(weth, amountToMint) + (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus());
        uint256 usdAmountLiquidated = engine.getUsdValue(weth, amountLiquidated);
        
        uint256 expectedMintedUserDsc = 0;
        uint256 expectedUserCollateral = engine.getUsdValue(weth, amountCollateral) - (usdAmountLiquidated);
        uint256 actualMintedDsc = engine.getDscMinted(USER);
        uint256 actualCollateral = engine.getAccountCollateralValue(USER);

        assertEq(expectedUserCollateral, actualCollateral);
        assertEq(expectedMintedUserDsc, actualMintedDsc);
    
    }



    function testGetTokenAddressFromUser() public depositedCollateral {
        vm.startPrank(USER);
        address actualTokenAddress = engine.getTokenAddressFromUser(USER);
        address expectedTokenAddress = weth;
        assertEq(actualTokenAddress, expectedTokenAddress);
        vm.stopPrank();

    }




}