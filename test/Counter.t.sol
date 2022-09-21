// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
 
import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/lending.sol";
import "src/dreamoracle.sol";
 
contract MintableToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
 
    }
 
    function mint(address receiver, uint256 value) public {
        super._mint(receiver, value);
    }
}
 
contract DexTest is Test {
 
    lending len;
    MintableToken usdt;

    address alice;
    address bob;
 
    function setUp() public {
        alice = address(1000);
        bob = address(2);
        usdt = new MintableToken("USDT", "UDT");
        usdt.mint(address(this), 1000 ether);
        len = new lending(address(usdt));
        usdt.mint(address(len), 1000 ether);
        usdt.mint(address(bob), 1000 ether);
        usdt.approve(address(len), 100 ether);
        //len.deposit(address(usdt), 100 ether);
    }
 
    function testDepositBorrow1() public 
    {

        vm.deal(alice, 100 ether);
        vm.startPrank(alice);
        (bool success, ) = payable(address(len)).call{value: 1 ether, gas: 500000}(abi.encodeWithSignature("deposit(address,uint256)", address(len), 1 ether));
        len.borrow(address(usdt), 4);
        vm.stopPrank();        
    }

    function testDepositBorrow2() public 
    {
        usdt.mint(alice, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.startPrank(alice);
        (bool success, ) = payable(address(len)).call{value: 1 ether, gas: 500000}(abi.encodeWithSignature("deposit(address,uint256)", address(len), 1 ether));
        len.borrow(address(usdt), 5);
        ERC20(usdt).approve(address(len), 10); // 1 ether
        len.deposit(address(usdt), 10);
        len.repay(address(usdt), 5);
        len.withdraw(address(usdt), 5);
        vm.stopPrank();
        ERC20(address(usdt)).balanceOf(alice);
    }

    function testliquidate() public
    {
        usdt.mint(alice, 100 ether);
        usdt.mint(bob, 100 ether);

        vm.deal(alice, 100 ether);
        vm.startPrank(alice);
        (bool success, ) = payable(address(len)).call{value: 1 ether, gas: 500000}(abi.encodeWithSignature("deposit(address,uint256)", address(len), 1 ether));
        len.borrow(address(usdt), 5);
        vm.stopPrank();
        len.oracle_set(0.15 ether, address(usdt));
        vm.startPrank(bob);
        ERC20(usdt).approve(address(len), 100 ether);
        len.deposit(address(usdt), 5);
        len.liquidate(alice, address(usdt), 5);
        vm.stopPrank();
    }

    function testrepay_fee() public
    {
        usdt.mint(alice, 100 ether);
        usdt.mint(bob, 100 ether);
        vm.startPrank(bob);
        console.log(ERC20(usdt).balanceOf(bob));
        ERC20(usdt).approve(address(len), 100 ether);
        len.deposit(address(usdt), 50000);
        vm.deal(alice, 100 ether);
        vm.stopPrank();
        vm.startPrank(alice);
        (bool success, ) = payable(address(len)).call{value: 1 ether, gas: 500000}(abi.encodeWithSignature("deposit(address,uint256)", address(len), 1 ether));
        len.borrow(address(usdt), 5);
        vm.warp(1 days);
        ERC20(usdt).approve(address(len), 6);
        len.deposit(address(usdt), 6);
        len.repay(address(usdt), 5);
        console.log(ERC20(usdt).balanceOf(bob));
        vm.stopPrank();
    }
}