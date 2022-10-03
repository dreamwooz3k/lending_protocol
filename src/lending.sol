// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./dreamoracle.sol";

import "forge-std/Test.sol";

contract lending
{
    DreamOracle public oracle = new DreamOracle();

    struct loan
    {
        uint256 time;
        uint256 loan_value;
        uint256 bal_eth;
        uint256 bal_usdc;
        uint256 guarantee;
    }

    mapping(address => loan) public loan_list;
    address private usdc_addr;
    address private owner;
    address[] private investor_addr;

    constructor(address _usdc_addr)
    {
        owner=msg.sender;
        usdc_addr=_usdc_addr;
        oracle.setPrice(usdc_addr, 0.1 ether);
    }

    function deposit(address tokenAddress, uint256 amount) payable external
    {
        require(address(this)==tokenAddress || usdc_addr==tokenAddress, "not token address");
        //require(msg.value != 0 && tokenAddress==address(this), "not address value");

        if(tokenAddress==address(this))
        {
            loan_list[msg.sender].bal_eth+=msg.value;
        }
        else
        {
            bool check=false;
            require(ERC20(tokenAddress).balanceOf(msg.sender) >= amount, "balance less");
            ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
            loan_list[msg.sender].bal_usdc+=amount;
            for(uint256 i=0; i<investor_addr.length; i++)
            {
                if(msg.sender == investor_addr[i])
                {
                    check=true;
                }
            }
            if(!check)
            {
                investor_addr.push(msg.sender);
            }
        }
    }

    function borrow(address tokenAddress, uint256 amount) external
    {
        require(tokenAddress==usdc_addr, "address value check");
        require(ERC20(tokenAddress).balanceOf(address(this))>=amount, "landing pool less");
        uint256 usdc_value = oracle.getPrice(usdc_addr);
        require(loan_list[msg.sender].bal_eth >= amount*usdc_value*2, "guarantee deposit");
        loan_list[msg.sender].guarantee = amount*usdc_value*2;
        loan_list[msg.sender].bal_eth -= amount*usdc_value*2;
        loan_list[msg.sender].loan_value+=amount;
        loan_list[msg.sender].time=block.timestamp;
        ERC20(tokenAddress).transfer(msg.sender, amount);
    }

    function repay(address tokenAddress, uint256 amount) external
    {
        require(tokenAddress == usdc_addr);
        uint256 usdc_value = oracle.getPrice(usdc_addr);
        uint256 check_value;
        require(loan_list[msg.sender].bal_usdc != 0 || loan_list[msg.sender].loan_value != 0, 'usdc or loan amount check');
        require(loan_list[msg.sender].bal_usdc >= amount + repay_fee(msg.sender, amount), 'amount checks');

        if(amount >= loan_list[msg.sender].loan_value)
        {
            loan_list[msg.sender].bal_usdc-=(loan_list[msg.sender].loan_value + repay_fee(msg.sender, loan_list[msg.sender].loan_value));
            check_value=loan_list[msg.sender].guarantee;
            loan_list[msg.sender].loan_value=0;
            loan_list[msg.sender].guarantee=0;
            payable(msg.sender).transfer(check_value);
            send_fee(repay_fee(msg.sender,amount));
        }
        else
        {
            loan_list[msg.sender].bal_usdc-=(amount + repay_fee(msg.sender, amount));
            check_value=loan_list[msg.sender].guarantee;
            loan_list[msg.sender].guarantee-=(loan_list[msg.sender].guarantee*amount)/loan_list[msg.sender].loan_value;
            payable(msg.sender).transfer((check_value*amount)/loan_list[msg.sender].loan_value);
            loan_list[msg.sender].loan_value-=amount;
            if(repay_fee(msg.sender,amount)!=0)
            {
                send_fee(repay_fee(msg.sender,amount));   
            }
        }
    }

    function liquidate(address user, address tokenAddress, uint256 amount) external // amount = usdc 개수
    {
        require(tokenAddress==usdc_addr, "not token address");
        uint256 check = (loan_list[user].loan_value + repay_fee(user, loan_list[user].loan_value)) * 4 * oracle.getPrice(usdc_addr);
        require(loan_list[user].guarantee <= check/3, "tokenAddress Check or guarantee value check");
        require(loan_list[msg.sender].bal_usdc >= amount, "amount value check");
        uint256 borrow_value=loan_list[user].loan_value+repay_fee(msg.sender, loan_list[user].loan_value);
        uint256 liquidate_value = loan_list[user].guarantee;
        uint256 reward;
        if(liquidate_value > borrow_value)
        {
            reward=liquidate_value-borrow_value*oracle.getPrice(usdc_addr);           
        }
        if(amount*oracle.getPrice(usdc_addr) >= liquidate_value)
        {
            loan_list[msg.sender].bal_usdc -= borrow_value;
            payable(msg.sender).transfer(liquidate_value);
        }
        else
        {
            loan_list[msg.sender].bal_usdc -= (amount-((reward*amount)/(borrow_value*oracle.getPrice(usdc_addr)))); // reward 지급
            payable(msg.sender).transfer(amount*oracle.getPrice(usdc_addr));
        }

    }

    function withdraw(address tokenAddress, uint256 amount) external
    {
        require(tokenAddress == address(this) || tokenAddress == usdc_addr);
        
        if(tokenAddress == address(this) && loan_list[msg.sender].loan_value==0)
        {
            require(loan_list[msg.sender].bal_eth >= amount, "amount value check");
            loan_list[msg.sender].bal_eth-=amount*oracle.getPrice(usdc_addr);
            payable(msg.sender).transfer(amount);
        }
        else
        {
            require(loan_list[msg.sender].bal_usdc >= amount, "amount value check");
            loan_list[msg.sender].bal_usdc-=amount;
            ERC20(usdc_addr).transfer(msg.sender, amount);
        }
    }

    function repay_fee(address user, uint256 _amount) private view returns (uint256 fee)
    {
        fee=_amount;
        uint256 day = (block.timestamp - loan_list[user].time) / 1 days;
        for (uint i = 0; i < day; i++) 
        {
            fee = fee * 1001 / 1000;
        }
        fee -= _amount;
        return fee;
    }

    function send_fee(uint256 _fee) private
    {
        uint256 check;
        for(uint i=0; i<investor_addr.length; i++)
        {
            if(loan_list[investor_addr[i]].bal_usdc == 0)
            {
                check=i;
            }
            else
            {
                ERC20(usdc_addr).transfer(investor_addr[i], _fee*(loan_list[investor_addr[i]].bal_usdc/ERC20(usdc_addr).balanceOf(address(this))));
            }
        }
        delete investor_addr[check];
    }

    function oracle_set(uint256 value, address _token) public
    {
        require(owner==msg.sender, "not owner");
        oracle.setPrice(_token, value);
    }
}
