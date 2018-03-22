# IHT Token Crowdsale Audit

This is an audit of IHT Token's crowdsale contracts.

No potential vulnerabilities have been identified in the crowdsale and token contracts.

Details of the reviews are below.

<br />

<hr />

## Table Of Contents

* [Deployment](#deployment)
* [Scope](#scope)
* [Limitations](#limitations)
* [Due Diligence](#due-diligence)
* [Risks](#risks)
* [Trustlessness Of The Crowdsale Contract](#trustlessness-of-the-crowdsale-contract)
* [Potential Vulnerabilities](#potential-vulnerabilities)
* [Recommendations](#recommendations)
* [Notes](#notes)
* [Crowdsale And Token Contracts Overview](#crowdsale-and-token-contracts-overview)
* [References](#references)


<br />

<hr />

## Deployment

* Jan 31 2018 - The IHT Token Crowdsale contract is live at [0xe702E16D904F191aB75b8dBb5504960eAE5Af950](https://etherscan.io/address/0xe702E16D904F191aB75b8dBb5504960eAE5Af950),
  with the funds flowing into the multisig at [0x9e3741a7a7F34194F1368F6dD673Fdf3e9B13c98](https://etherscan.io/address/0x9e3741a7a7F34194F1368F6dD673Fdf3e9B13c98).

<br />

<hr />

## Scope

This audit is into the technical aspects of the crowdsale contracts. The primary aim of this audit is to ensure that funds contributed to these contracts are not easily attacked or stolen by third parties. 
The secondary aim of this audit is that ensure the coded algorithms work as expected. This audit does not guarantee that that the code is bugfree, but intends to highlight any areas of
weaknesses.

<br />

<hr />

## Limitations
This audit makes no statements or warranties about the viability of the IHT's business proposition, the individuals involved in this business or the regulatory regime for the business model.

<br />

<hr />

## Due Diligence
As always, potential participants in any crowdsale are encouraged to perform their due diligence on the business proposition before funding the crowdsale.

Potential participants are also encouraged to only send their funds to the official crowdsale Ethereum address, published on IHT's official communication channel.

Scammers have been publishing phishing address in the forums, twitter and other communication channels, and some go as far as duplicating crowdsale websites.
Potential participants should NOT just click on any links received through these messages.
 
Potential participants should also confirm that the verified source code on EtherScan.io for the published crowdsale address matches the audited source code, and that 
the deployment parameters are correctly set, including the constant parameters.

Potential participants should note that there is a minimum funding goal in this crowdsale and there are refunds if this minimum funding goal is not reached.

HireMatch will have to load funds back into the crowdsale contract for investors to withdraw their refunds.

This contract has no mechanism to enforce any vesting of HIRE's tokens.

<br />

<hr />

## Risks

This crowdfunding contract has a relatively low risk of losing large amounts of ethers in an attack or a bug, as funds contributed by participants are immediately transferred
into a multisig wallet.

The flow of funds from this crowdsale contract should be monitored using a script and visually through EtherScan. Should there be any abnormal 
gaps in the crowdfunding contracts, potential participants should be informed to stop contributing to this crowdsale contract. Most of the funds
will be held in the multisig wallet, so any potential losses due to flaws in the crowdsale contract should be minimal.

In the case of the crowdfunding contract allocating an incorrect number of tokens for each contribution, the token numbers can be manually
recalculated and a new token contract can be deployed at a new address.

<br />

<hr />

## Trustlessness Of The Crowdsale Contract

* The PricingStrategy can be changed at any point by the owner when the crowdsale is running. Comment in the source code:

  > Design choice: no state restrictions on the set, so that we can fix fat finger mistakes.

  A change in the pricing strategy can only be detected by looking for this `setPricingStrategy(...)` transaction, and the ETH to token rate changes.

* The crowdsale end date can be changed by the owner at any point during the crowdsale, to a time later than when the change is made. Comment in the source code:

  > Allow crowdsale owner to close early or extend the crowdsale.
  >
  > This is useful e.g. for a manual soft cap implementation:
  > - after X amount is reached determine manual closing
  >
  > This may put the crowdsale to an invalid state,
  > but we trust owners know what they are doing.

  The `EndsAtChanged(...)` event is logged.

  The crowdsale contract owner can also re-open a closed crowdsale using this parameter, if the crowdsale has not been `finalized`.

* Some negative scenarios:

  * An investor may decide to invest near the end of the crowdsale if only a small amount has been contributed by other investors. The crowdsale
    contract owner may extend the crowdsale closing date to any point in the future.

  * An investor may decide to wait nearer to the end of the crowdsale to invest, but the owners can suddenly close down the crowdsale. They would normally
    inform their community that they plan to close down the crowdsale prematurely, but this could be 24 hours and not be enough time for this investor to respond. 

* This crowdsale contract moves all investor contributions straight into the crowdsale team's multisig wallet. If the minimum funding goal
  is not reached, investors will only be able to claim their refunds IF the crowdsale team moves all original funds back from the
  multisig into the crowdsale contract.

* The upgrade agent can be set by the upgrade master (crowdsale team's account), but accounts have to execute the upgrades themselves, which is a good trustless upgrade

* Once the crowdsale if finalised, the token contract has the right elements for a trustless token contract

<br />

<hr />

## Potential Vulnerabilities

No potential vulnerabilities have been identified in the crowdsale and token contract.

<br />

<hr />

## Recommendations

* See note below re `preallocate(...)` and refunds. The crowdsale team should reconcile the crowdsale contract `weiRaised` variable against
  the funds received during the preallocation phase - after all the `preallocate(...)` entries have been entered. If these numbers do not
  reconcile, it may be best to deploy a new crowdsale contract and enter the correct `preallocate(...)` entries.

* As the interactions between the different contracts is quite convoluted, prepare some scripts to check the relationships between the contracts are correct 
  and that the crowdsale numbers add up.

<br />

<hr />

## Notes

* If the crowdsale does not reach the minimum funding goal by the end of the crowdsale period, all funds supporting the tokens issued must be moved
  back into the crowdsale contract before the refund state is activated. This includes the funds that support the tokens created using the
  `preallocate(...)` function.

  It is important to get the `weiPrice` parameter of the `preallocate(...)` function correct, as no one will be able claim their refunds and 
  the ethers may be trapped in this crowdsale contract.

  One scenario is where the `preallocate(...)` function has the `weiPrice` out by a factor of 10 times. 10 times as much funds that were 
  collected during the preallocation phase will need to be moved back into the crowdsale contract for refunds to be active.

* The `preallocate(...)` function can be executed at any time before, during and after the crowdsale, but before finalisation of the crowdsale. Normally
  this function is used before the crowdsale starts.

* The `preallocate(...)` function can only be used to allocate round token amounts and not fractional token amounts. E.g. 10 instead of 10.123456789000000000

* If `setUpgradeMaster(...)` is called with an invalid new upgrade master, upgrades can be prevented forever

* The team bonus tokens are created as a percentage on top of the crowdsale tokens. If the team bonus tokens is 10% on top of the crowdsale tokens,
  the team bonus tokens will end up being 9.090909091% of the totalSupply. Let's say 1,000,000 tokens are raised by the crowdsale. 10% of this is 100,000 tokens.
  100,000 / (1,000,000 + 100,000) = 100,000 / 1,100,000 = 9.090909090909091% .

* There is no mechanism to transfer out any other ERC20 tokens from the crowdsale or token contracts.

<br />

<hr />

## Crowdsale And Token Contracts Overview

* [x] This token contract is of moderate complexity
* [x] The code has been tested for the normal [ERC20](https://github.com/ethereum/EIPs/issues/20) use cases
  * [x] Deployment, with correct `symbol()`, `name()`, `decimals()` and `totalSupply()`
  * [x] `transfer(...)` from one account to another
  * [x] `approve(...)` and `transferFrom(...)` from one account to another
  * [x] While the `transfer(...)` and `transferFrom(...)` uses safe maths, there are checks so the function is able to return **true** and **false** instead of throwing an error
* [x] `transfer(...)` and `transferFrom(...)` is only enabled when the crowdsale is finalised, when either the funds raised matches the cap, or the current time is beyond the crowdsale end date
* [x] `transferOwnership(...)` has `acceptOwnership()` to prevent errorneous transfers of ownership of the token contract
* [x] ETH contributed to the crowdsale contract is immediately moved to a separate wallet
* [x] ETH cannot be trapped in the token contract as the default `function () payable` is not implemented
* [x] Check potential division by zero
* [x] All numbers used are **uint** (which is **uint256**), with the exception of `decimals`, reducing the risk of errors from type conversions
* [x] Areas with potential overflow errors in `transfer(...)` and `transferFrom(...)` have the logic to prevent overflows
* [x] Areas with potential underflow errors in `transfer(...)` and `transferFrom(...)` have the logic to prevent underflows
* [x] Function and event names are differentiated by case - function names begin with a lowercase character and event names begin with an uppercase character
* [x] The default function will NOT receive contributions during the crowdsale phase and mint tokens. Users have to execute a specific function to contribute to the crowdsale contract
* [x] The testing has been done using geth v1.6.5-stable-cf87713d/darwin-amd64/go1.8.3 and solc 0.4.11+commit.68ef5810.Darwin.appleclang instead of one of the testing frameworks and JavaScript VMs to simulate the live environment as closely as possible
* [x] There is a switch to pause and then restart the contract being able to receive contributions
* [x] The [`transfer(...)`](https://github.com/ConsenSys/smart-contract-best-practices#be-aware-of-the-tradeoffs-between-send-transfer-and-callvalue) call is the last statements in the control flow of `investInternal(...)` to prevent the hijacking of the control flow
* [x] The token contract does not implement the check for the number of bytes sent to functions to reject errors from the [short address attack](http://vessenes.com/the-erc20-short-address-attack-explained/). This technique is now NOT recommended
* [x] This contract implement a modified `approve(...)` functions to mitigate the risk of [double spending](https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit#) by requiring the account to set a non-zero approval limit to 0 before modifying this limit

<br />

<hr />


## References

* [Ethereum Contract Security Techniques and Tips](https://github.com/ConsenSys/smart-contract-best-practices)

<br />

<br />

