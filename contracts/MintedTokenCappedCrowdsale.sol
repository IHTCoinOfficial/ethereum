pragma solidity ^0.4.18;

import "./Crowdsale.sol";
import "./MintableToken.sol";

/**
 * ICO crowdsale contract that is capped by amout of tokens.
 *
 * - Tokens are dynamically created during the crowdsale
 *
 *
 */
contract MintedTokenCappedCrowdsale is Crowdsale {

  /* Maximum amount of tokens this crowdsale can sell. */
  uint256 public maximumSellableTokens;

  function MintedTokenCappedCrowdsale(address _token, PricingStrategy _pricingStrategy, address _multisigWallet, uint256 _start, uint256 _end, uint256 _minimumFundingGoal, uint256 _maximumSellableTokens, address _tokenVestingAddress) Crowdsale(_token, _pricingStrategy, _multisigWallet, _start, _end, _minimumFundingGoal, _tokenVestingAddress) public {
    maximumSellableTokens = _maximumSellableTokens;
  }

  /**
   * Called from invest() to confirm if the curret investment does not break our cap rule.
   */
  function isBreakingCap(uint256 weiAmount, uint256 tokenAmount, uint256 weiRaisedTotal, uint256 tokensSoldTotal) public constant returns (bool limitBroken) {
    return tokensSoldTotal > maximumSellableTokens;
  }

  function isCrowdsaleFull() public constant returns (bool) {
    return tokensSold >= maximumSellableTokens;
  }

  /**
   * Dynamically create tokens and assign them to the investor.
   */
  function assignTokens(address receiver, uint256 tokenAmount) private {
    MintableToken mintableToken = MintableToken(token);
    mintableToken.mint(receiver, tokenAmount);
  }
}
