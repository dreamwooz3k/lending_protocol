pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Debt_token is Ownable, ERC20
{   
    constructor() ERC20("Debt_token", "debt")
    {
        
    }

    function mint(address borrower_addr, uint256 amount) onlyOwner public
    {
        _mint(borrower_addr, amount); 
    }

    function burn(address borrower_addr, uint256 amount) onlyOwner public
    {
        _burn(borrower_addr, amount);
    }
}