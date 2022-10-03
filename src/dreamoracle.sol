pragma solidity ^0.8.13;
 
contract DreamOracle 
{
   address public operator;
   mapping(address=>uint256) prices;
 
   constructor() 
   {
       operator = msg.sender;
   }
 
   function getPrice(address token) external view returns (uint256) 
   {
       require(prices[token] != 0, "the price cannot be zero");
       return prices[token];
   }
 
   function setPrice(address token, uint256 price) external // Pricing any token in eth
   {  
       require(msg.sender == operator, "only operator can set the price");
       prices[token] = price;
   }
}
