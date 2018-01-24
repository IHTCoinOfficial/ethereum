pragma solidity ^0.4.18;

import "./PricingStrategy.sol";
import "./Crowdsale.sol";
import "./SafeMathLib.sol";
import './Ownable.sol';


/// @dev Time milestone based pricing with special support for pre-ico deals.
contract MilestonePricing is PricingStrategy, Ownable, SafeMathLib {

  uint public constant MAX_MILESTONE = 10;

  // This contains all pre-ICO addresses, and their prices (weis per token)
  mapping (address => uint256) public preicoAddresses;

  /**
  * Define pricing schedule using milestones.
  */
  struct Milestone {

      // UNIX timestamp when this milestone kicks in
      uint256 time;

      // How many tokens per satoshi you will get after this milestone has been passed
      uint256 price;
  }

  // Store milestones in a fixed array, so that it can be seen in a blockchain explorer
  // Milestone 0 is always (0, 0)
  // (TODO: change this when we confirm dynamic arrays are explorable)
  Milestone[10] public milestones;

  // How many active milestones we have
  uint256 public milestoneCount;

  /// @dev Contruction, creating a list of milestones
  /// @param _milestones uint[] milestones Pairs of (time, price)
  function MilestonePricing(uint256[] _milestones) public {
    // Need to have tuples, length check
    require(!(_milestones.length % 2 == 1 || _milestones.length >= MAX_MILESTONE*2));
    // if(_milestones.length % 2 == 1 || _milestones.length >= MAX_MILESTONE*2) {
    //   throw;
    // }

    milestoneCount = _milestones.length / 2;

    uint256 lastTimestamp = 0;

    for(uint256 i=0; i<_milestones.length/2; i++) {
      milestones[i].time = _milestones[i*2];
      milestones[i].price = _milestones[i*2+1];

      // No invalid steps
      require(!((lastTimestamp != 0) && (milestones[i].time <= lastTimestamp)));

      lastTimestamp = milestones[i].time;
    }

    // Last milestone price must be zero, terminating the crowdale
    require(milestones[milestoneCount-1].price == 0);
  }

  /// @dev This is invoked once for every pre-ICO address, set pricePerToken
  ///      to 0 to disable
  /// @param preicoAddress PresaleFundCollector address
  /// @param pricePerToken How many weis one token cost for pre-ico investors
  function setPreicoAddress(address preicoAddress, uint256 pricePerToken)
    public
    onlyOwner
  {
    preicoAddresses[preicoAddress] = pricePerToken;
  }

  /// @dev Iterate through milestones. You reach end of milestones when price = 0
  /// @return tuple (time, price)
  function getMilestone(uint256 n) public constant returns (uint256, uint) {
    return (milestones[n].time, milestones[n].price);
  }

  function getFirstMilestone() private constant returns (Milestone) {
    return milestones[0];
  }

  function getLastMilestone() private constant returns (Milestone) {
    return milestones[milestoneCount-1];
  }

  function getPricingStartsAt() public constant returns (uint256) {
    return getFirstMilestone().time;
  }

  function getPricingEndsAt() public constant returns (uint256) {
    return getLastMilestone().time;
  }

  function isSane(address _crowdsale) public view returns(bool) {
    Crowdsale crowdsale = Crowdsale(_crowdsale);
    return crowdsale.startsAt() == getPricingStartsAt() && crowdsale.endsAt() == getPricingEndsAt();
  }

  /// @dev Get the current milestone or bail out if we are not in the milestone periods.
  /// @return {[type]} [description]
  function getCurrentMilestone() private constant returns (Milestone) {
    uint256 i;

    for(i=0; i<milestones.length; i++) {
      if(now < milestones[i].time) {
        return milestones[i-1];
      }
    }
  }

  /// @dev Get the current price.
  /// @return The current price or 0 if we are outside milestone period
  function getCurrentPrice() public constant returns (uint result) {
    return getCurrentMilestone().price;
  }

  /// @dev Calculate the current price for buy in amount.
  function calculatePrice(uint256 value, uint256 weiRaised, uint256 tokensSold, address msgSender, uint256 decimals) public constant returns (uint256) {

    uint256 multiplier = 10 ** decimals;

    // This investor is coming through pre-ico
    if(preicoAddresses[msgSender] > 0) {
      return safeMul(value, multiplier) / preicoAddresses[msgSender];
    }

    uint256 price = getCurrentPrice();
    return safeMul(value, multiplier) / price;
  }

  function() payable public {
    revert(); // No money on this contract
  }

}