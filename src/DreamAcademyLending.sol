pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IPriceOracle.sol";
import "forge-std/Test.sol";
import "./abdk.sol";

contract DreamAcademyLending
{
    struct borrower
    {
        uint256 loan;
        uint256 init_loan;

        uint256 guarantee;

        uint256 entry_point;
    }

    struct staker
    {
        uint256 stake;
        uint256 yield;
        uint256 entry_point;
        uint256 before_yield;
        uint256 accrued_snap;
    }

    struct lending
    {
        uint256 loan;
        uint256 init_loan;
        
        uint256 entry_point;
    }

    uint256 check;
    uint256 check_block;

    mapping(address => borrower) public borrowers;
    mapping(address => staker) public stakers;
    mapping(address => uint256[]) public token_lp;
    mapping(address => uint256[]) public block_snap;
    
    lending public lending_info;

    IPriceOracle oracle;
    ERC20 usdc;
    int128 borrowRate;
    constructor(IPriceOracle _oracle, address _usdc)
    {
        oracle = _oracle;
        usdc = ERC20(_usdc);
        borrowRate = ABDKMath64x64.divu(100000013882, 1e11);
    }

    function initializeLendingProtocol(address token) payable external
    {
        require(ERC20(address(token)).transferFrom(msg.sender, address(this), msg.value), "init transfer from fail");
    }

    function deposit(address token, uint256 amount) payable external
    {
        require(token == address(usdc) || token == address(0x0), "token address check");

        if(token == address(0x0) && msg.value > 0)
        {
            require(msg.value==amount, "Deposit: amount check");
            borrowers[msg.sender].guarantee += amount;
        }
        else
        {
            if(check>1)
            {
                block_snap[token][check-1] = usdc.balanceOf(address(this));
            }
            require(ERC20(token).transferFrom(msg.sender, address(this), amount), "amount value check");
            stakers[msg.sender].stake += amount;
            stakers[msg.sender].entry_point = check;
        }
    }

    function borrow(address token, uint256 amount) external
    {
        require(token == address(usdc), "token address check");
        require(borrowers[msg.sender].guarantee * oracle.getPrice(address(0x0)) >= (amount + borrowers[msg.sender].loan) * 2 * oracle.getPrice(address(token)), "LTV 50% : lack of collateral");
        require(ERC20(token).transfer(msg.sender, amount), "borrow fail");

        update_borrow_fee(msg.sender);

        borrowers[msg.sender].loan += amount;
        borrowers[msg.sender].init_loan += amount;
        borrowers[msg.sender].entry_point = block.number;

        lending_info.loan += amount;
        lending_info.init_loan += amount;
        lending_info.entry_point = block.number;
    }

    function update_borrow_fee(address borrower_addr) private
    {
        borrowers[borrower_addr].loan += borrow_fee(borrower_addr); 
        borrowers[borrower_addr].entry_point = block.number;

        uint256 term = (block.number - lending_info.entry_point);

        if(term!=0 && lending_info.entry_point !=0)
        {
            lending_info.loan=ABDKMath64x64.mulu(ABDKMath64x64.pow(borrowRate, term), lending_info.loan);
            lending_info.entry_point = block.number;
        }
    }

    function borrow_fee(address borrower_addr) private returns(uint256 fee)
    {
        if(borrowers[borrower_addr].loan == 0)
        {
            fee=0; 
            return fee;
        }

        uint256 term = (block.number - borrowers[borrower_addr].entry_point);
        fee = ABDKMath64x64.mulu(ABDKMath64x64.pow(borrowRate, term), borrowers[borrower_addr].loan);
        fee -= borrowers[borrower_addr].loan;
    }

    function repay(address token, uint256 amount) external
    {
        require(token == address(usdc), "token address check");
        update_borrow_fee(msg.sender);
        require(amount < borrowers[msg.sender].loan, "amount is too large");

        uint256 total_fee = borrowers[msg.sender].loan - borrowers[msg.sender].init_loan;
        uint256 amount_fee = total_fee/(borrowers[msg.sender].init_loan/amount);

        require(usdc.transferFrom(msg.sender, address(this), amount+ amount_fee), "borrow transferFrom error");

        uint256 repay_ratio = borrowers[msg.sender].init_loan *  1 ether / (amount-amount_fee);
        uint256 repay_amount = (borrowers[msg.sender].guarantee * 1 ether) / repay_ratio; 

        borrowers[msg.sender].loan -= (amount + amount_fee);
        borrowers[msg.sender].init_loan -= (amount-total_fee);

        lending_info.loan -= (amount + amount_fee);
        lending_info.init_loan -= (amount - total_fee);
    }

    function withdraw(address token, uint256 amount) external
    {
        require(token == address(usdc) || token == address(0x0), "token address check");

        update_borrow_fee(msg.sender);
        stakers[msg.sender].stake += stakers[msg.sender].yield;
        stakers[msg.sender].yield=0;

        if(token == address(0x0))
        {
            uint256 lv_amount;

            if(4 * borrowers[msg.sender].loan * oracle.getPrice(address(usdc)) <= 3 * borrowers[msg.sender].guarantee * oracle.getPrice(address(0x0)))
            {
                lv_amount = ABDKMath64x64.mulu(ABDKMath64x64.divu((3 * borrowers[msg.sender].guarantee * oracle.getPrice(address(0x0))) - (4 * borrowers[msg.sender].loan * oracle.getPrice(address(usdc))), 3 * borrowers[msg.sender].guarantee * oracle.getPrice(address(0x0)) ), borrowers[msg.sender].guarantee);
            }

            require(borrowers[msg.sender].guarantee * oracle.getPrice(address(0x0)) >  borrowers[msg.sender].loan * oracle.getPrice(address(usdc)) * 2 || amount <= lv_amount, "amount value check");

            borrowers[msg.sender].guarantee -= amount;
            payable(msg.sender).transfer(amount);
        }
        else
        {
            stakers[msg.sender].stake += getAccruedSupplyAmount(token) - stakers[msg.sender].stake;
            stakers[msg.sender].entry_point = check;
            require(stakers[msg.sender].stake >= amount, "amount value check");
            stakers[msg.sender].stake -= amount;
            usdc.transfer(msg.sender, amount);
        }
    }

    function getAccruedSupplyAmount(address token) public returns(uint256)
    {
        require(token == address(usdc), "token address check");

        uint256 fee_sum;

        for(uint i=0; i<token_lp[token].length; i++)
        {
            fee_sum += token_lp[token][i];
        }

        update_borrow_fee(msg.sender);
        uint256 total_fee = lending_info.loan - (lending_info.init_loan + fee_sum);

        token_lp[token].push(total_fee);
        block_snap[token].push(usdc.balanceOf(address(this)));
        check+=1;

        uint256 stakingRate;

        for(uint i=stakers[msg.sender].entry_point; i < token_lp[token].length; i++)
        {
            console.log(i);
            stakingRate += ABDKMath64x64.mulu(ABDKMath64x64.divu(stakers[msg.sender].stake, block_snap[token][i]), token_lp[token][i]);
        }

        if(check_block != block.number)
        {
            stakers[msg.sender].entry_point = check;
            console.log(stakingRate);
            stakers[msg.sender].stake += stakingRate;
            stakers[msg.sender].yield = stakingRate;
            stakingRate=0;
            check_block = block.number;
        }
        
        return stakers[msg.sender].stake + stakingRate;
    }

    function liquidate(address borrower_addr, address token, uint256 amount) external
    {
        update_borrow_fee(borrower_addr);
        uint256 liquidation_threshold = borrowers[borrower_addr].guarantee / 1 ether * oracle.getPrice(address(0)) * 3 ether / 4 / oracle.getPrice(address(usdc));
        require(amount * 4 <= borrowers[borrower_addr].loan, "otherwise only 25%");
        require(4 * borrowers[borrower_addr].loan * oracle.getPrice(address(token)) >= 3 * borrowers[borrower_addr].guarantee * oracle.getPrice(address(0x0)));
        require(amount <= borrowers[borrower_addr].loan , "An amount greater than the amount that can be liquidated has been received");
        require(ERC20(token).transferFrom(msg.sender, address(this), amount), "liquidate : transferFrom Error");
        uint256 total_fee = borrowers[borrower_addr].loan - borrowers[borrower_addr].init_loan;
        borrowers[borrower_addr].loan -= amount;
        lending_info.loan -= amount;
        uint256 liquidate_eth;

        if(amount > total_fee)
        {
            borrowers[borrower_addr].init_loan -= (amount - total_fee);
            lending_info.init_loan -= (amount - total_fee);

            liquidate_eth = amount* oracle.getPrice(address(usdc)) / oracle.getPrice(address(0x0));
            console.log(liquidate_eth);
            borrowers[borrower_addr].guarantee -= liquidate_eth;
            payable(msg.sender).transfer(liquidate_eth); // liquidationBonus 5%
        }
    }
}