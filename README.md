# OUSD Token: Version 4.0

We are revamping the our rebasing token contract.

The primary objective is to allow delegated yield. Delegated yield allows an account to seemlessly transfer all earned yield to another account.

Secondarily, we'd like to fix the tiny rounding issues around transfers and between local account information and global tracking slots.


## How OUSD works.

OUSD is a rebasing token. It's mission in life is to be able to distribute increases in backing assets on to users by having user's balances go up each time the token rebases. 

**`_rebasingCreditsPerToken`** is a global variable that converts between "credits" stored on a account, and the actual balance of the account. This allows this single variable to be updated and in turn all "rebasing" users have their account balance change proportionally. Counterintuitively, this is not a multiplier on users credits, but a divider. So it's `user balance = user credits / _rebasingCreditsPerToken`. Because it's a divider, OUSD will slowly lose resolution over very long timeframes, as opposed to  abruptly stopping working suddenly once enough yield has been earned.

**_creditBalances[account]** This per account mapping stores the internal credits for each account. 

**alternativeCreditsPerToken[account]** This per account mapping stores an alternative, optional conversion factor for the value used in creditBalances. When it is set to zero, it says that it is unused, and the global `_rebasingCreditsPerToken` should be used instead. Because this alternative conversion factor does not update on rebases, it allows an account to be "frozen" and no longer change balances as rebases happen.

**rebaseState[account]** This holds user preferences for what type of accounting is used on an account. For historical reasons the default, `NotSet` value on this could mean that the account is using either `StdRebasing` or `StdNonRebasing` accounting (see details later).

### StdRebasing Account (Default)

This is the "normal" account in the system. It gets yield and its balance goes up over time. Almost account is this type.

Reads:

- `rebaseState`: could be either `NotSet` or `StdRebasing`. Almost all accounts are `NotSet`, and typicly only contracts that want to receive yield are set to `StdRebasing` (though there's nothing preventing regular users making an from an explicitly marking their account as recieving yield).
- `alternativeCreditsPerToken`: will always be zero, thus using the global _rebasingCreditsPerToken
- `_creditBalances`: credits for the account

Writes:

- `rebaseState`: if explicitly moving to this state from another state `StdRebasing` is set. Otherwise, the account remains `NotSet`.
- `alternativeCreditsPerToken`: will always be zero
- `_creditBalances`: credits for the account

Transitions to:

- automatic conversion to a `StdNonRebasing` account if funds are moved to or from a contract* AND the account is currently `NotSet`.
- to `StdNonRebasing` if the account calls `rebaseOptOut()`
- to `YieldDelegationTarget` if it is the destinataion account in a `delegateYield()`

### StdNonRebasing Account (Default)

This account does not earn yield. It was orignaly created for backwards compatibility with systems that did not support balance changes, as well not wasting yield on third party contracts holding tokens that did not support any distribution to users. As a side benefit, regular users earn at a higher rate than the increase in assets.

Reads:

- `rebaseState`: could be either `NotSet` or `StdNonRebasing`. Historicaly, almost all accounts are `NotSet` and you can only determine which kind of account `NotSet` is by looking at `alternativeCreditsPerToken`.
- `alternativeCreditsPerToken` Will always be non-zero. Probably ranges from 1e17-ish to 1e27, with most at 1e27.
- `_creditBalances` will either be a "frozen credits style" that can be converted via `alternativeCreditsPerToken`, or "frozen balance" style, losslessly convertable via an 1e18 or 1e27 in `alternativeCreditsPerToken`.

Writes:

- `rebaseState`: Set to `StdNonRebasing` when new contracts are automaticly moved to this state, or when explicitly converted to this account type. This was not previously the case for historical automatic conversions.
- `alternativeCreditsPerToken`: New balance writes will always use 1e18, which will result in the account's credits being equal to the balance.
- `_creditBalances`: New balance writes will always use 1:1 a credits/balance ratio, which will make this be the account balance.

Transitions to:

- to `StdRebasing` via a `rebaseOptIn()` call or a governance `governanceRebaseOptIn()`.
- to `YieldDelegationSource` if the source account in a `delegateYield()` call


### YieldDelegationSource

This account does not earn yield, instead its yield is passed on to another account.

It does this by keeping a non-rebasing style fixed balance locally, while storing all its rebasing credits on the target account. This makes the target account's credits be `(target account's credits + source account's credits)`

Reads / Writes (no historical accounts to deal with!):

- `rebaseState`: `YieldDelegationSource`
- `alternativeCreditsPerToken`: Always 1e18.
- `_creditBalances`: Always set to the account balance in 1:1 credits.
- Target account's `_creditBalances`: Increased by this accounts credits at the global `_rebasingCreditsPerToken`. 

Transitions to:
- to `StdNonRebasing` if `undelegateYield()` is called on the yield delegation

### YieldDelegationTarget

This account earns extra yield from exactly one account. YieldDelegationTargets can have their own balances, and these balances to do earn. This works by having both account's credits stored in this account, but then subtracting the other account's fixed balance from the total. 

For example, someone loans you an intrest free $10,000. You now have an extra $10,000, but also owe them $10,000 so that nets out to a zero change in your wealth. You take that $10,000 and invest it in T-bills, so you are now getting more yield than you did before.


Reads / Writes (no historical accounts to deal with!):
- `rebaseState`: `YieldDelegationTarget`
- `alternativeCreditsPerToken`: Always 0
- `_creditBalances`: The sum of this account's credits and the yield sources credits.
- Source account's `_creditBalances`: This balance is subtracted by that value

Transitions to:
- to `StdRebasing` if `undelegateYield()` is called on the yield delegation