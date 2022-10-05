// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/woozek_lending.sol";
import "../src/dreamoracle.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20
{
    constructor() ERC20("USDC", "us")
    {

    }

    function mint(address user, uint256 amount) external
    {
        _mint(user, amount);
    }

    function burn(address user, uint256 amount) external
    {
        _burn(user, amount);
    }
}

contract Lending_test is Test 
{

    USDC public usdc;
    Lending public lending;
    DreamOracle public dreamoracle;

    address public alice;
    address public bob;
    function setUp() public 
    {
        usdc = new USDC();
        dreamoracle = new DreamOracle();
        lending = new Lending(address(usdc), address(dreamoracle));

        dreamoracle.setPrice(address(usdc), 1 ether);
        dreamoracle.setPrice(address(0), 200 ether);
        usdc.mint(address(lending), 100 ether);
        usdc.mint(address(this), type(uint224).max-1);
        usdc.approve(address(lending), type(uint224).max-1);

        alice = address(0xa);
        vm.deal(alice, 100 ether);
        usdc.mint(alice, 100 ether);
        vm.prank(alice);
        usdc.approve(address(lending), 100 ether);

        bob = address(0xb);
        vm.deal(bob, 100 ether);
        usdc.mint(bob, 100 ether);
        vm.prank(bob);
        usdc.approve(address(lending), 100 ether);
    }

    function testDeposit() public 
    {
        vm.prank(bob);
        lending.deposit(address(usdc), 10 ether);
        assertEq(lending.atoken_balanceOf(bob), 10 ether);

        vm.prank(alice);
        address(lending).call{value: 10 ether}(abi.encodeWithSignature("deposit(address,uint256)", address(0), 10 ether));
        assertEq(lending.guarantee_balanceOf(alice), 10 ether);
        console.log(lending.atoken_balanceOf(alice));

        vm.expectRevert("Check that the deposit call was successful");
        lending.deposit(address(1), 123);
        
    }

    function testborrow() public
    {
        vm.startPrank(bob);
        address(lending).call{value: 1 ether}(abi.encodeWithSignature("deposit(address,uint256)", address(0), 1 ether));
        lending.borrow(address(usdc), 100 ether);
        assertEq(lending.guarantee_balanceOf(bob), 0);
        assertEq(usdc.balanceOf(bob), 100 ether + 100 ether);
    }

    function testwithdraw() public
    {
        vm.prank(bob);
        lending.deposit(address(usdc), 10 ether);
        assertEq(lending.atoken_balanceOf(bob), 10 ether);
        vm.prank(bob);
        lending.withdraw(address(usdc), 10 ether);
        assertEq(ERC20(address(usdc)).balanceOf(bob), 100 ether);
    
        vm.startPrank(alice);
        address(lending).call{value: 10 ether}(abi.encodeWithSignature("deposit(address,uint256)", address(0), 10 ether));
        lending.withdraw(address(0), 10 ether);
        assertEq(alice.balance, 100 ether);
    }

    function testrepay() public
    {
        vm.startPrank(bob);
        address(lending).call{value: 1 ether}(abi.encodeWithSignature("deposit(address,uint256)", address(0), 1 ether));
        lending.borrow(address(usdc), 100 ether);
        lending.repay(address(usdc), 100 ether);
        assertEq(bob.balance, 100 ether);
    }

    function testliquidate() public
    {
        vm.startPrank(bob);
        address(lending).call{value: 1 ether}(abi.encodeWithSignature("deposit(address,uint256)", address(0), 1 ether));
        lending.borrow(address(usdc), 100 ether);
        vm.stopPrank();
        
        usdc.approve(address(lending), 150 ether);
        dreamoracle.setPrice(address(usdc), 1.5 ether);
        lending.liquidate(bob, address(usdc), 90 ether);

        assertEq(lending.lock_guarantee_balanceOf(bob), 325000000000000000);
    }

    function testfee() public
    {
        uint256 before_balance = address(this).balance;
        vm.startPrank(bob);
        address(lending).call{value: 1 ether}(abi.encodeWithSignature("deposit(address,uint256)", address(0), 1 ether));
        lending.borrow(address(usdc), 100 ether);
        uint256 t = block.timestamp;
        vm.stopPrank();
        vm.warp(t + 500 days);
        lending.update_fee(bob);
        lending.liquidate(bob, address(usdc), 64830941641303877091);
        assertEq(before_balance, address(this).balance);
    }

    receive() payable external
    {
        
    }
}
