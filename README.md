# OUSD Token: 4.0

We are revamping the our rebasing token contract.

The primary objective is to allow delegated yield. Delegated yield an account to seemlessly transfer all earned yield to another account.

Secondarily, we'd like to fix the tiny rounding issues around transfers and between local account information and global tracking slots.


## How old OUSD works.

OUSD is a rebasing token. It's mission in life is to be able to distribute increases in backing assets on to users by having user's balances go up each time the token rebases. 

**`_rebasingCreditsPerToken`** is a global variable that converts between "credits" stored on a account, and the actual balance of the account. This allows this single variable to be updated and all "rebasing" users have their account balance change proportionally. Counterintuitively, this is not a multiplier on users credits, but a divider. So it's `user balance = user credits / _rebasingCreditsPerToken`. Because it's a divider, OUSD will slowly lose resolution over very long timeframes, as opposed to  abruptly stoping working suddenly once enough yield has been earned.

**_creditBalances[account]** This account mapping stores the internal credits for each account. 

**nonRebasingCreditsPerToken[account]** This account mapping stores an alternative conversion factor for the value used in creditBalances.

## Default / Rebasing Account



