pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Atoken is Ownable, ERC20
{
    constructor() ERC20("Atoken", "A")
    {
        
    }

    function mint(address borrower, uint256 amount) onlyOwner public
    {
        _mint(borrower, amount); 
    }

    function burn(address borrower, uint256 amount) onlyOwner public
    {
        _burn(borrower, amount);
    }
}
