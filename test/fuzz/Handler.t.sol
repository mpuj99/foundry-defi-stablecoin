// Handler is going to narrow down the way we call the function


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // we don't put uint256 because if you put +1 is going to revert with an overflow

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    address[] public usersWithDscDeposited; 
    
    
    
    
    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _decentralizedStableCoin) {
        engine = _dscEngine;
        dsc = _decentralizedStableCoin;
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

    }

    
    function mintDsc(uint256 amountToMint, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if(maxDscToMint < 0) {
            return;
        }
        amountToMint = bound(amountToMint, 0, uint256(maxDscToMint));
        if (amountToMint == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintDsc(amountToMint);
        vm.stopPrank();
        //usersWithDscDeposited.push(sender);

        timesMintIsCalled++;
    
    
    }   




    /**
     * 
     * @param collateralSeed random fuzz number that calls _getCollateralFromSeed
     * @param amountCollateral random fuzz number
     * 
     * @notice We bound the parameter collateralSeed to only pick the valid addresses(weth, wbtc) with the help of _getCollateralFromSeed() function.
     * @notice We bound the parameter amountCollateral to not be zero, as we have an applied modifier that reverts if it's zero
     */

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Bound as well the amountCollateral
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // We keep track of all the addresses are depositing collateral to then mint, because te function mint wasn't called at all, probably because it was using random
        //addresses to mint, we don't want that.
        usersWithCollateralDeposited.push(msg.sender);
    }


    
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral, uint256 addressSeed) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        uint256 maxAmountCollateralToRedeem = engine.getCollateralDepositedOfUser(sender, address(collateral));
        console.log("Balance of: ", maxAmountCollateralToRedeem);
        amountCollateral = bound(amountCollateral, 0, maxAmountCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    //function burnDsc(uint256 amountToBurn, uint256 addressSeed) public {

    //}

    // Helper functions

    /**
     * 
     * @param collateralSeed random fuzz number
     * @notice from the number he puts he outputs one of the valid tokens (weth, wbtc) by getting the "rest" of the division(evens == weth, odd == wbtc)
     */
    function _getCollateralFromSeed(uint256 collateralSeed) public view returns (ERC20Mock) {
        if(collateralSeed % 2 == 0){
            return weth;
        } else {
            return wbtc;
        }
        
        
    }



}