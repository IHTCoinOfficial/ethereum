pragma solidity ^0.4.18;

import "./SafeMathLib.sol";
import "./Haltable.sol";
import "./PricingStrategy.sol";
import "./FinalizeAgent.sol";
import "./FractionalERC20.sol";
import "./Allocatable.sol";
import "./TokenVesting.sol";


/**
 * Abstract base contract for token sales.
 *
 * Handle
 * - start and end dates
 * - accepting investments
 * - minimum funding goal and refund
 * - various statistics during the crowdfund
 * - different pricing strategies
 * - different investment policies (require server side customer id, allow only whitelisted addresses)
 *
 */
contract Crowdsale is Allocatable, Haltable, SafeMathLib {

  /* Max investment count when we are still allowed to change the multisig address */
  uint public MAX_INVESTMENTS_BEFORE_MULTISIG_CHANGE = 5;

  /* The token we are selling */
  FractionalERC20 public token;

  /* Token Vesting Contract */
  address public tokenVestingAddress;

  /* How we are going to price our offering */
  PricingStrategy public pricingStrategy;

  /* Post-success callback */
  FinalizeAgent public finalizeAgent;

  /* tokens will be transfered from this address */
  address public multisigWallet;

  /* if the funding goal is not reached, investors may withdraw their funds */
  uint256 public minimumFundingGoal;

  /* the UNIX timestamp start date of the crowdsale */
  uint256 public startsAt;

  /* the UNIX timestamp end date of the crowdsale */
  uint256 public endsAt;

  /* the number of tokens already sold through this contract*/
  uint256 public tokensSold = 0;

  /* How many wei of funding we have raised */
  uint256 public weiRaised = 0;

  /* How many distinct addresses have invested */
  uint256 public investorCount = 0;

  /* How much wei we have returned back to the contract after a failed crowdfund. */
  uint256 public loadedRefund = 0;

  /* How much wei we have given back to investors.*/
  uint256 public weiRefunded = 0;

  /* Has this crowdsale been finalized */
  bool public finalized;

  /* Do we need to have unique contributor id for each customer */
  bool public requireCustomerId;

  /**
    * Do we verify that contributor has been cleared on the server side (accredited investors only).
    * This method was first used in FirstBlood crowdsale to ensure all contributors have accepted terms on sale (on the web).
    */
  bool public requiredSignedAddress;

  /* Server side address that signed allowed contributors (Ethereum addresses) that can participate the crowdsale */
  address public signerAddress;

  /** How much ETH each address has invested to this crowdsale */
  mapping (address => uint256) public investedAmountOf;

  /** How much tokens this crowdsale has credited for each investor address */
  mapping (address => uint256) public tokenAmountOf;

  /** Addresses that are allowed to invest even before ICO offical opens. For testing, for ICO partners, etc. */
  mapping (address => bool) public earlyParticipantWhitelist;

  /** This is for manul testing for the interaction from owner wallet. You can set it to any value and inspect this in blockchain explorer to see that crowdsale interaction works. */
  uint256 public ownerTestValue;

  /** State machine
   *
   * - Preparing: All contract initialization calls and variables have not been set yet
   * - Prefunding: We have not passed start time yet
   * - Funding: Active crowdsale
   * - Success: Minimum funding goal reached
   * - Failure: Minimum funding goal not reached before ending time
   * - Finalized: The finalized has been called and succesfully executed
   * - Refunding: Refunds are loaded on the contract for reclaim.
   */
  enum State{Unknown, Preparing, PreFunding, Funding, Success, Failure, Finalized, Refunding}

  // A new investment was made
  event Invested(address investor, uint256 weiAmount, uint256 tokenAmount, uint128 customerId);

  // Refund was processed for a contributor
  event Refund(address investor, uint256 weiAmount);

  // The rules were changed what kind of investments we accept
  event InvestmentPolicyChanged(bool requireCustId, bool requiredSignedAddr, address signerAddr);

  // Address early participation whitelist status changed
  event Whitelisted(address addr, bool status);

  // Crowdsale end time has been changed
  event EndsAtChanged(uint256 endAt);

  function Crowdsale(address _token, PricingStrategy _pricingStrategy, address _multisigWallet, 
  uint256 _start, uint256 _end, uint256 _minimumFundingGoal, address _tokenVestingAddress) public 
  {

    owner = msg.sender;

    token = FractionalERC20(_token);

    tokenVestingAddress = _tokenVestingAddress;

    setPricingStrategy(_pricingStrategy);

    multisigWallet = _multisigWallet;
    require(multisigWallet != 0);

    require(_start != 0);

    startsAt = _start;

    require(_end != 0);

    endsAt = _end;

    // Don't mess the dates
    require(startsAt < endsAt);

    // Minimum funding goal can be zero
    minimumFundingGoal = _minimumFundingGoal;
  }

  /**
   * Don't expect to just send in money and get tokens.
   */
  function() payable public {
    invest(msg.sender);
  }

  /**
   * Make an investment.
   *
   * Crowdsale must be running for one to invest.
   * We must have not pressed the emergency brake.
   *
   * @param receiver The Ethereum address who receives the tokens
   * @param customerId (optional) UUID v4 to track the successful payments on the server side
   *
   */
  function investInternal(address receiver, uint128 customerId) stopInEmergency private {

    // Determine if it's a good time to accept investment from this participant
    if(getState() == State.PreFunding) {
      // Are we whitelisted for early deposit
      require(earlyParticipantWhitelist[receiver]);
      uint256 multiplier = 10 ** token.decimals();
      require(msg.value >= safeMul(15,multiplier) && msg.value <= safeMul(50,multiplier));
    
    } else if(getState() == State.Funding) {
      // Retail participants can only come in when the crowdsale is running
    } else {
      // Unwanted state
      require(false);
    }

    uint weiAmount = msg.value;
    uint tokenAmount = pricingStrategy.calculatePrice(weiAmount, weiRaised, tokensSold, msg.sender, token.decimals());

    require(tokenAmount != 0);


    if(investedAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }

    // Update investor
    investedAmountOf[receiver] = safeAdd(investedAmountOf[receiver],weiAmount);
    tokenAmountOf[receiver] = safeAdd(tokenAmountOf[receiver],tokenAmount);

    // Update totals
    weiRaised = safeAdd(weiRaised,weiAmount);
    tokensSold = safeAdd(tokensSold,tokenAmount);

    // Check that we did not bust the cap
    require(!isBreakingCap(weiAmount, tokenAmount, weiRaised, tokensSold));

    assignTokens(receiver, tokenAmount);

    // Pocket the money
    require(multisigWallet.send(weiAmount));

    // Tell us invest was success
    Invested(receiver, weiAmount, tokenAmount, customerId);
  }

  /**
   * allocate tokens for the early investors.
   *
   * Preallocated tokens have been sold before the actual crowdsale opens.
   * This function mints the tokens and moves the crowdsale needle.
   *
   * Investor count is not handled; it is assumed this goes for multiple investors
   * and the token distribution happens outside the smart contract flow.
   *
   * No money is exchanged, as the crowdsale team already have received the payment.
   *
   * @param weiPrice Price of a single full token in wei
   *
   */
  function preallocate(address receiver, uint256 tokenAmount, uint256 weiPrice, uint256 principleLockAmount, uint256 principleLockPeriod, uint256 bonusLockAmount, uint256 bonusLockPeriod) public onlyAllocateAgent {


    uint256 weiAmount = (weiPrice * tokenAmount)/10**uint256(token.decimals()); // This can be also 0, we give out tokens for free

    weiRaised = safeAdd(weiRaised,weiAmount);
    tokensSold = safeAdd(tokensSold,tokenAmount);

    investedAmountOf[receiver] = safeAdd(investedAmountOf[receiver],weiAmount);
    tokenAmountOf[receiver] = safeAdd(tokenAmountOf[receiver],tokenAmount);

    // cannot lock more than total tokens
    uint256 totalLockAmount = safeAdd(principleLockAmount, bonusLockAmount);
    require(totalLockAmount <= tokenAmount);
    
    // assign locked token to Vesting contract
    if (totalLockAmount > 0) {

      if (principleLockAmount > 0) {
        require(principleLockPeriod > 0);
      }
      if (bonusLockAmount > 0) {
        require(bonusLockPeriod > 0);
      }

      TokenVesting tokenVesting = TokenVesting(tokenVestingAddress);
      
      // to prevent minting of tokens which will be useless as vesting amount cannot be updated
      require(!tokenVesting.isVestingSet(receiver));
      assignTokens(tokenVestingAddress,totalLockAmount);
      
      // set vesting with default schedule
      tokenVesting.setVesting(receiver, principleLockAmount, principleLockPeriod, bonusLockAmount, bonusLockPeriod); 
    }

    // assign remaining tokens to contributor
    if (tokenAmount - totalLockAmount > 0) {
      assignTokens(receiver, tokenAmount - totalLockAmount);
    }

    // Tell us invest was success
    Invested(receiver, weiAmount, tokenAmount, 0);
  }

  /**
   * Track who is the customer making the payment so we can send thank you email.
   */
  function investWithCustomerId(address addr, uint128 customerId) public payable {
    require(!requiredSignedAddress);
    require(customerId != 0);
    investInternal(addr, customerId);
  }

  /**
   * Allow anonymous contributions to this crowdsale.
   */
  function invest(address addr) public payable {
    require(!requireCustomerId);
    
    require(!requiredSignedAddress);
    investInternal(addr, 0);
  }

  /**
   * Invest to tokens, recognize the payer and clear his address.
   *
   */
  
  // function buyWithSignedAddress(uint128 customerId, uint8 v, bytes32 r, bytes32 s) public payable {
  //   investWithSignedAddress(msg.sender, customerId, v, r, s);
  // }

  /**
   * Invest to tokens, recognize the payer.
   *
   */
  function buyWithCustomerId(uint128 customerId) public payable {
    investWithCustomerId(msg.sender, customerId);
  }

  /**
   * The basic entry point to participate the crowdsale process.
   *
   * Pay for funding, get invested tokens back in the sender address.
   */
  function buy() public payable {
    invest(msg.sender);
  }

  /**
   * Finalize a succcesful crowdsale.
   *
   * The owner can triggre a call the contract that provides post-crowdsale actions, like releasing the tokens.
   */
  function finalize() public inState(State.Success) onlyOwner stopInEmergency {

    // Already finalized
    require(!finalized);

    // Finalizing is optional. We only call it if we are given a finalizing agent.
    if(address(finalizeAgent) != 0) {
      finalizeAgent.finalizeCrowdsale();
    }

    finalized = true;
  }

  /**
   * Allow to (re)set finalize agent.
   *
   * Design choice: no state restrictions on setting this, so that we can fix fat finger mistakes.
   */
  function setFinalizeAgent(FinalizeAgent addr) public onlyOwner {
    finalizeAgent = addr;

    // Don't allow setting bad agent
    require(finalizeAgent.isFinalizeAgent());
  }

  /**
   * Set policy do we need to have server-side customer ids for the investments.
   *
   */
  function setRequireCustomerId(bool value) public onlyOwner {
    requireCustomerId = value;
    InvestmentPolicyChanged(requireCustomerId, requiredSignedAddress, signerAddress);
  }

  /**
   * Allow addresses to do early participation.
   *
   * TODO: Fix spelling error in the name
   */
  function setEarlyParicipantWhitelist(address addr, bool status) public onlyOwner {
    earlyParticipantWhitelist[addr] = status;
    Whitelisted(addr, status);
  }

  /**
   * Allow crowdsale owner to close early or extend the crowdsale.
   *
   * This is useful e.g. for a manual soft cap implementation:
   * - after X amount is reached determine manual closing
   *
   * This may put the crowdsale to an invalid state,
   * but we trust owners know what they are doing.
   *
   */
  function setEndsAt(uint time) public onlyOwner {

    require(now <= time);

    endsAt = time;
    EndsAtChanged(endsAt);
  }

  /**
   * Allow to (re)set pricing strategy.
   *
   * Design choice: no state restrictions on the set, so that we can fix fat finger mistakes.
   */
  function setPricingStrategy(PricingStrategy _pricingStrategy) public onlyOwner {
    pricingStrategy = _pricingStrategy;

    // Don't allow setting bad agent
    require(pricingStrategy.isPricingStrategy());
  }

  /**
   * Allow to change the team multisig address in the case of emergency.
   *
   * This allows to save a deployed crowdsale wallet in the case the crowdsale has not yet begun
   * (we have done only few test transactions). After the crowdsale is going
   * then multisig address stays locked for the safety reasons.
   */
  function setMultisig(address addr) public onlyOwner {

    // Change
    require(investorCount <= MAX_INVESTMENTS_BEFORE_MULTISIG_CHANGE);

    multisigWallet = addr;
  }

  /**
   * Allow load refunds back on the contract for the refunding.
   *
   * The team can transfer the funds back on the smart contract in the case the minimum goal was not reached..
   */
  function loadRefund() public payable inState(State.Failure) {
    require(msg.value != 0);
    loadedRefund = safeAdd(loadedRefund,msg.value);
  }

  /**
   * Investors can claim refund.
   */
  function refund() public inState(State.Refunding) {
    uint256 weiValue = investedAmountOf[msg.sender];
    require(weiValue != 0);
    investedAmountOf[msg.sender] = 0;
    weiRefunded = safeAdd(weiRefunded,weiValue);
    Refund(msg.sender, weiValue);
    require(msg.sender.send(weiValue));
  }

  /**
   * @return true if the crowdsale has raised enough money to be a succes
   */
  function isMinimumGoalReached() public constant returns (bool reached) {
    return weiRaised >= minimumFundingGoal;
  }

  /**
   * Check if the contract relationship looks good.
   */
  function isFinalizerSane() public constant returns (bool sane) {
    return finalizeAgent.isSane();
  }

  /**
   * Check if the contract relationship looks good.
   */
  function isPricingSane() public constant returns (bool sane) {
    return pricingStrategy.isSane(address(this));
  }

  /**
   * Crowdfund state machine management.
   *
   * We make it a function and do not assign the result to a variable, so there is no chance of the variable being stale.
   */
  function getState() public constant returns (State) {
    if(finalized) return State.Finalized;
    else if (address(finalizeAgent) == 0) return State.Preparing;
    else if (!finalizeAgent.isSane()) return State.Preparing;
    else if (!pricingStrategy.isSane(address(this))) return State.Preparing;
    else if (block.timestamp < startsAt) return State.PreFunding;
    else if (block.timestamp <= endsAt && !isCrowdsaleFull()) return State.Funding;
    else if (isMinimumGoalReached()) return State.Success;
    else if (!isMinimumGoalReached() && weiRaised > 0 && loadedRefund >= weiRaised) return State.Refunding;
    else return State.Failure;
  }

  /** This is for manual testing of multisig wallet interaction */
  function setOwnerTestValue(uint val) public onlyOwner {
    ownerTestValue = val;
  }

  /** Interface marker. */
  function isCrowdsale() public pure returns (bool) {
    return true;
  }

  //
  // Modifiers
  //

  /** Modified allowing execution only if the crowdsale is currently running.  */
  modifier inState(State state) {
    require(getState() == state);
    _;
  }


  //
  // Abstract functions
  //

  /**
   * Check if the current invested breaks our cap rules.
   *
   *
   * The child contract must define their own cap setting rules.
   * We allow a lot of flexibility through different capping strategies (ETH, token count)
   * Called from invest().
   *
   * @param weiAmount The amount of wei the investor tries to invest in the current transaction
   * @param tokenAmount The amount of tokens we try to give to the investor in the current transaction
   * @param weiRaisedTotal What would be our total raised balance after this transaction
   * @param tokensSoldTotal What would be our total sold tokens count after this transaction
   *
   * @return true if taking this investment would break our cap rules
   */
  function isBreakingCap(uint weiAmount, uint tokenAmount, uint weiRaisedTotal, uint tokensSoldTotal) public constant returns (bool limitBroken);
  /**
   * Check if the current crowdsale is full and we can no longer sell any tokens.
   */
  function isCrowdsaleFull() public constant returns (bool);

  /**
   * Create new tokens or transfer issued tokens to the investor depending on the cap model.
   */
  function assignTokens(address receiver, uint tokenAmount) private;
}
