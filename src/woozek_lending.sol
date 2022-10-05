pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./dreamoracle.sol";
import "./Atoken.sol";

import "forge-std/Test.sol";

contract Lending
{

    DreamOracle public oracle;  // admin is address(this)
    Atoken public atoken;

    address public usdc_addr;
    
    struct borrower
    {
        uint256 time;
        uint256 loan;
        uint256 borrow_loan;
        uint256 guarantee;
        uint256 lock_guarantee;
    }

    mapping(address => borrower) public borrower_list;

    constructor(address usdc, address dreamoracle)
    {
        usdc_addr = usdc;
        oracle = DreamOracle(dreamoracle);

        atoken = new Atoken();
    }

    function deposit(address tokenAddress, uint256 amount) payable external
    {
        require(tokenAddress == usdc_addr || (tokenAddress == address(0) && msg.value != 0), "Check that the deposit call was successful");        
        
        if(tokenAddress == address(0))
        {
            borrower_list[msg.sender].guarantee += msg.value;
        }
        
        else
        {
            require(ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount), "Deposit : transferFrom Error");
            atoken.mint(msg.sender, amount);
        }
    }

    function borrow(address tokenAddress, uint256 amount) external
    {
        require(tokenAddress == usdc_addr, "Check token address");

        uint256 eth_value = oracle.getPrice(address(0));
        uint256 usdc_value = oracle.getPrice(usdc_addr);

        require(borrower_list[msg.sender].guarantee / usdc_value * eth_value >= amount * 2, "LTV 50% : lack of collateral");
    
        update_fee(msg.sender);
        borrower_list[msg.sender].loan += amount;
        borrower_list[msg.sender].borrow_loan += amount;
        borrower_list[msg.sender].guarantee -= amount / 1 ether * usdc_value / eth_value * 2 ether;
        borrower_list[msg.sender].lock_guarantee += amount / 1 ether * usdc_value / eth_value * 2 ether;
        borrower_list[msg.sender].time = block.timestamp;
        
        ERC20(tokenAddress).transfer(msg.sender, amount / 1 ether);
    }

    function withdraw(address tokenAddress, uint256 amount) external
    {
        require(tokenAddress == usdc_addr || tokenAddress == address(0), "Check token address");
        require(borrower_list[msg.sender].loan == 0, "Debt exists and cannot be withdrawn");
        
        if(tokenAddress == usdc_addr)
        {
            uint256 stake = ERC20(tokenAddress).balanceOf(address(this)) * atoken.balanceOf(msg.sender) / atoken.totalSupply();
            if(amount % stake == 0)
            {
                atoken.burn(msg.sender, atoken.balanceOf(msg.sender) * amount/stake);
            }
            else
            {
                atoken.burn(msg.sender, atoken.balanceOf(msg.sender) * amount/stake + 1); // 보정
            }

            ERC20(tokenAddress).transfer(msg.sender, amount);
        }

        else
        {
            require(borrower_list[msg.sender].guarantee >= amount, "Check amount value");

            borrower_list[msg.sender].guarantee -= amount;
            payable(msg.sender).transfer(amount);
        }
    }

    function repay(address tokenAddress, uint256 amount) external
    {
        require(tokenAddress == usdc_addr, "Check token address");

        uint256 fee = repay_fee(msg.sender);
        require(borrower_list[msg.sender].loan + fee >= amount, "Check amount value");
        
        require(ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount / 1 ether), "repay : transferFrom Error");

        uint256 eth_value = oracle.getPrice(address(0));
        uint256 usdc_value = oracle.getPrice(address(usdc_addr));

        update_fee(msg.sender);
        uint256 total_fee = borrower_list[msg.sender].loan - borrower_list[msg.sender].borrow_loan;

        if(amount > total_fee)
        {
            uint256 repay_eth = borrower_list[msg.sender].lock_guarantee * (amount-total_fee) / borrower_list[msg.sender].borrow_loan;
            borrower_list[msg.sender].borrow_loan -= amount-total_fee;
            payable(msg.sender).transfer(repay_eth); 
        }
        borrower_list[msg.sender].loan-=amount;
    }

    function liquidate(address borrower_addr, address tokenAddress, uint256 amount) external
    {
        console.log(amount);
        console.log(borrower_list[borrower_addr].loan);
        update_fee(borrower_addr);
        require(borrower_list[borrower_addr].lock_guarantee / 1 ether * oracle.getPrice(address(0)) / oracle.getPrice(usdc_addr) * 3 ether / 4 <= borrower_list[borrower_addr].loan, "Liquidation Threshold 75% : Impossible to liquidate");
        require(amount <= borrower_list[borrower_addr].loan , "An amount greater than the amount that can be liquidated has been received");
        require(ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount / 1 ether), "liquidate : transferFrom Error");

        uint256 total_fee = borrower_list[msg.sender].loan - borrower_list[msg.sender].borrow_loan;
        borrower_list[borrower_addr].loan -= amount;
        uint256 liquidate_eth;

        if(amount > total_fee)
        {
            borrower_list[borrower_addr].borrow_loan -= amount - total_fee;
            if(amount >= oracle.getPrice(address(0)))
            {
                liquidate_eth = amount / 1 ether * oracle.getPrice(address(usdc_addr)) / oracle.getPrice(address(0));
                borrower_list[borrower_addr].lock_guarantee -= liquidate_eth;
            }
            else
            {
                liquidate_eth = amount* oracle.getPrice(address(usdc_addr)) / oracle.getPrice(address(0));
                borrower_list[borrower_addr].lock_guarantee -= liquidate_eth;
            }
            payable(msg.sender).transfer(liquidate_eth * 5 / 100); // liquidationBonus 5%
        }
    }

    function update_fee(address borrower_addr) public
    {
        uint256 fee = repay_fee(borrower_addr);
        borrower_list[borrower_addr].loan += fee;
    }

    function repay_fee(address borrower_addr) private returns(uint256 fee)
    {
        fee = borrower_list[borrower_addr].loan;
        uint256 day = (block.timestamp - borrower_list[borrower_addr].time) / 1 days;

        for(uint256 i = 0; i < day; i++)
        {
            fee = fee * 1001 / 1000;
        }

        fee -= borrower_list[borrower_addr].loan;
        borrower_list[borrower_addr].time = block.timestamp;
    }

    function atoken_balanceOf(address user) public view returns(uint256)
    {
        return atoken.balanceOf(user);
    }

    function guarantee_balanceOf(address user) public view returns(uint256)
    {
        return borrower_list[user].guarantee;
    }
}
