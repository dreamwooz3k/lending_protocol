pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./dreamoracle.sol";
import "./Atoken.sol";
import "./Debt_token.sol";

import "forge-std/Test.sol";

contract Lending
{

    DreamOracle public oracle;  // admin is address(this)
    Atoken public atoken;
    Debt_token public debt_token;

    address public usdc_addr;
    
    struct borrower
    {
        uint256 time;
        uint256 loan;
        uint256 guarantee;
        uint256 lock_guarantee;
    }

    mapping(address => borrower) public borrower_list;

    constructor(address usdc, address dreamoracle)
    {
        usdc_addr = usdc;
        oracle = DreamOracle(dreamoracle);

        atoken = new Atoken();
        debt_token = new Debt_token();
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
            ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
            atoken.mint(msg.sender, amount);
        }
    }

    function borrow(address tokenAddress, uint256 amount) external
    {
        require(tokenAddress == usdc_addr, "Check token address");
        
        uint256 usdc_value = oracle.getPrice(usdc_addr); // ETH units per USDC
        require(borrower_list[msg.sender].guarantee >= amount * usdc_value * 2, "LTV 50% : lack of collateral");
        
        borrower_list[msg.sender].loan += amount;
        borrower_list[msg.sender].guarantee -= amount * usdc_value * 2;
        borrower_list[msg.sender].lock_guarantee += amount * usdc_value * 2;
        borrower_list[msg.sender].time = block.timestamp;
        
        ERC20(tokenAddress).transfer(msg.sender, amount);
        debt_token.mint(msg.sender, amount);
    }

    function withdraw(address tokenAddress, uint256 amount) external
    {
        require(tokenAddress == usdc_addr || tokenAddress == address(0), "Check token address");
        require(debt_token.balanceOf(msg.sender) == 0, "Debt exists and cannot be withdrawn");
        
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

        ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        update_fee(msg.sender);
        debt_token.burn(msg.sender, amount);
        uint256 total_fee = debt_token.balanceOf(msg.sender) - borrower_list[msg.sender].loan;

        if(amount > total_fee)
        {
            uint256 repay_eth = borrower_list[msg.sender].lock_guarantee * (oracle.getPrice(usdc_addr) * amount - oracle.getPrice(usdc_addr) * total_fee) / (oracle.getPrice(usdc_addr) * borrower_list[msg.sender].loan);
            payable(msg.sender).transfer(repay_eth); 
        }
    }

    function liquidate(address borrower_addr, address tokenAddress, uint256 amount) external
    {
        update_fee(borrower_addr);
        require(borrower_list[borrower_addr].lock_guarantee * 3 / 4 <= borrower_list[borrower_addr].loan, "Liquidation Threshold 75% : Impossible to liquidate");
        require(debt_token.balanceOf(msg.sender) == 0, "A person in debt cannot liquidate.");
        require(amount * oracle.getPrice(usdc_addr) <= borrower_list[borrower_addr].lock_guarantee, "An amount greater than the amount that can be liquidated has been received");
        //require(atoken.balacneOf(msg.sender) * oracle.getPrice(usdc_addr) >= amount);
        
        ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        borrower_list[borrower_addr].lock_guarantee -= amount * oracle.getPrice(usdc_addr);
        payable(msg.sender).transfer(amount * oracle.getPrice(usdc_addr) * 5 / 100); // liquidationBonus 5%

        if(borrower_list[borrower_addr].lock_guarantee == 0)
        {
            borrower_list[borrower_addr].loan = 0;
            debt_token.burn(borrower_addr, debt_token.balanceOf(borrower_addr));
        }
    }

    function update_fee(address borrower_addr) public
    {
        uint256 fee = repay_fee(borrower_addr);
        debt_token.mint(borrower_addr, fee);
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

    function debttoken_balanceOf(address user) public view returns(uint256)
    {
        return debt_token.balanceOf(user);
    }

    function guarantee_balanceOf(address user) public view returns(uint256)
    {
        return borrower_list[user].guarantee;
    }
}
