// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title OUSD Token Contract
 * @dev ERC20 compatible contract for OUSD
 * @dev Implements an elastic supply
 * @author Origin Protocol Inc
 */
import { Governable } from "../governance/Governable.sol";
import {console} from "forge-std/Test.sol";

/**
 * NOTE that this is an ERC20 token but the invariant that the sum of
 * balanceOf(x) for all x is not >= totalSupply(). This is a consequence of the
 * rebasing design. Any integrations with OUSD should be aware.
 */

contract OUSD is Governable {

    event TotalSupplyUpdatedHighres(
        uint256 totalSupply,
        uint256 rebasingCredits,
        uint256 rebasingCreditsPerToken
    );
    event AccountRebasingEnabled(address account);
    event AccountRebasingDisabled(address account);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    enum RebaseOptions {
        NotSet,
        OptOut,
        OptIn,
        YieldDelegationSource,
        YieldDelegationTarget
    }

    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1
    uint256 public _totalSupply;
    mapping(address => mapping(address => uint256)) private _allowances;
    address public vaultAddress = address(0);
    mapping(address => uint256) private _creditBalances;
    uint256 private _rebasingCredits; // Sum of all rebasing credits (_creditBalances for rebasing accounts)
    uint256 private _rebasingCreditsPerToken;
    uint256 public nonRebasingSupply;  // All nonrebasing balances
    mapping(address => uint256) public nonRebasingCreditsPerToken;
    mapping(address => RebaseOptions) public rebaseState;
    mapping(address => uint256) public isUpgraded;
    mapping(address => address) public yieldTo;
    mapping(address => address) public yieldFrom;

    uint256 private constant RESOLUTION_INCREASE = 1e9;

    function initialize(
        string calldata,
        string calldata,
        address _vaultAddress,
        uint256 _initialCreditsPerToken
    ) external onlyGovernor {
        require(vaultAddress == address(0), "Already initialized");
        require(_rebasingCreditsPerToken == 0, "Already initialized");
        _rebasingCreditsPerToken = _initialCreditsPerToken;
        vaultAddress = _vaultAddress;
    }

    function name() external pure returns (string memory) {
        return "Origin Dollar";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function symbol() external pure returns (string memory) {
        return "OUSD";
    }

    /**
     * @dev Verifies that the caller is the Vault contract
     */
    modifier onlyVault() {
        require(vaultAddress == msg.sender, "Caller is not the Vault");
        _;
    }

    /**
     * @return The total supply of OUSD.
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @return Low resolution rebasingCreditsPerToken
     */
    function rebasingCreditsPerToken() public view returns (uint256) {
        return _rebasingCreditsPerToken / RESOLUTION_INCREASE;
    }

    /**
     * @return Low resolution total number of rebasing credits
     */
    function rebasingCredits() public view returns (uint256) {
        return _rebasingCredits / RESOLUTION_INCREASE;
    }

    /**
     * @return High resolution rebasingCreditsPerToken
     */
    function rebasingCreditsPerTokenHighres() public view returns (uint256) {
        return _rebasingCreditsPerToken;
    }

    /**
     * @return High resolution total number of rebasing credits
     */
    function rebasingCreditsHighres() public view returns (uint256) {
        return _rebasingCredits;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _account Address to query the balance of.
     * @return A uint256 representing the amount of base units owned by the
     *         specified address.
     */
    function balanceOf(address _account)
        public
        view
        returns (uint256)
    {
        RebaseOptions state = rebaseState[_account];
        if(state == RebaseOptions.YieldDelegationSource){
            // Saves a slot read when transfering to or from a yield delegating source
            // since we know creditBalances equals the balance.
            return _creditBalances[_account];
        }
        uint256 baseBalance = _creditBalances[_account] * 1e18 / _creditsPerToken(_account);
        if (state == RebaseOptions.YieldDelegationTarget) {
            return baseBalance - _creditBalances[yieldFrom[_account]];
        }
        return baseBalance;
    }

    /**
     * @dev Gets the credits balance of the specified address.
     * @dev Backwards compatible with old low res credits per token.
     * @param _account The address to query the balance of.
     * @return (uint256, uint256) Credit balance and credits per token of the
     *         address
     */
    function creditsBalanceOf(address _account)
        public
        view
        returns (uint256, uint256)
    {
        uint256 cpt = _creditsPerToken(_account);
        if (cpt == 1e27) {
            // For a period before the resolution upgrade, we created all new
            // contract accounts at high resolution. Since they are not changing
            // as a result of this upgrade, we will return their true values
            return (_creditBalances[_account], cpt);
        } else {
            return (
                _creditBalances[_account] / RESOLUTION_INCREASE,
                cpt / RESOLUTION_INCREASE
            );
        }
    }

    /**
     * @dev Gets the credits balance of the specified address.
     * @param _account The address to query the balance of.
     * @return (uint256, uint256, bool) Credit balance, credits per token of the
     *         address, and isUpgraded
     */
    function creditsBalanceOfHighres(address _account)
        public
        view
        returns (
            uint256,
            uint256,
            bool
        )
    {
        return (
            _creditBalances[_account],
            _creditsPerToken(_account),
            isUpgraded[_account] == 1
        );
    }

    /**
     * @dev Transfer tokens to a specified address.
     * @param _to the address to transfer to.
     * @param _value the amount to be transferred.
     * @return true on success.
     */
    function transfer(address _to, uint256 _value)
        public
        returns (bool)
    {
        require(_to != address(0), "Transfer to zero address");

        _executeTransfer(msg.sender, _to, _value);

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param _from The address you want to send tokens from.
     * @param _to The address you want to transfer to.
     * @param _value The amount of tokens to be transferred.
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public returns (bool) {
        require(_to != address(0), "Transfer to zero address");

        _allowances[_from][msg.sender] = _allowances[_from][msg.sender] - _value;

        _executeTransfer(_from, _to, _value);

        emit Transfer(_from, _to, _value);

        return true;
    }

    /**
     * @dev Update the count of non rebasing credits in response to a transfer
     * @param _from The address you want to send tokens from.
     * @param _to The address you want to transfer to.
     * @param _value Amount of OUSD to transfer
     */
    function _executeTransfer(
        address _from,
        address _to,
        uint256 _value
    ) internal {
        if(_from == _to){
            return;
        }

        (int256 fromRebasingCreditsDiff, int256 fromNonRebasingSupplyDiff) 
            = _adjustAccount(_from, -int256(_value));
        (int256 toRebasingCreditsDiff, int256 toNonRebasingSupplyDiff) 
            = _adjustAccount(_to, int256(_value));

        _adjustGlobals(
            fromRebasingCreditsDiff + toRebasingCreditsDiff,
            fromNonRebasingSupplyDiff + toNonRebasingSupplyDiff
        );
    }

    function _adjustAccount(address account, int256 balanceChange) internal returns (int256 rebasingCreditsDiff, int256 nonRebasingSupplyDiff) {
        RebaseOptions state = rebaseState[account];
        int256 currentBalance = int256(balanceOf(account));
        uint256 newBalance = uint256(int256(currentBalance) + int256(balanceChange));
        if(newBalance < 0){
            revert("Transfer amount exceeds balance");
        }
        if (state == RebaseOptions.YieldDelegationSource) {
            address target = yieldTo[account];
            uint256 targetPrevBalance = balanceOf(target);
            uint256 targetNewCredits = _balanceToRebasingCredits(targetPrevBalance + newBalance);
            rebasingCreditsDiff = int256(targetNewCredits) - int256(_creditBalances[target]);

            _creditBalances[account] = newBalance;
            _creditBalances[target] = targetNewCredits;
            nonRebasingCreditsPerToken[account] = 1e18;

        } else if (state == RebaseOptions.YieldDelegationTarget) {
            uint256 newCredits = _balanceToRebasingCredits(newBalance + _creditBalances[yieldFrom[account]]);
            rebasingCreditsDiff = int256(newCredits) - int256(_creditBalances[account]);
            _creditBalances[account] = newCredits;

        } else if(_isNonRebasingAccount(account)){
            nonRebasingSupplyDiff = balanceChange;
            nonRebasingCreditsPerToken[account] = 1e18;
            _creditBalances[account] = newBalance;

        } else {
            uint256 newCredits = _balanceToRebasingCredits(newBalance);
            rebasingCreditsDiff = int256(newCredits) - int256(_creditBalances[account]);
            _creditBalances[account] = newCredits;
        }
    }

    function _adjustGlobals(int256 rebasingCreditsDiff, int256 nonRebasingSupplyDiff) internal {
        if(rebasingCreditsDiff !=0){
            if (uint256(int256(_rebasingCredits) + rebasingCreditsDiff) < 0){
                revert("rebasingCredits underflow");
            }
            _rebasingCredits = uint256(int256(_rebasingCredits) + rebasingCreditsDiff);
        }
        if(nonRebasingSupplyDiff !=0){
            if (int256(nonRebasingSupply) + nonRebasingSupplyDiff < 0){
                revert("nonRebasingSupply underflow");
            }
            nonRebasingSupply = uint256(int256(nonRebasingSupply) + nonRebasingSupplyDiff);
        }
    }

    /**
     * @dev Function to check the amount of tokens that _owner has allowed to
     *      `_spender`.
     * @param _owner The address which owns the funds.
     * @param _spender The address which will spend the funds.
     * @return The number of tokens still available for the _spender.
     */
    function allowance(address _owner, address _spender)
        public
        view
        returns (uint256)
    {
        return _allowances[_owner][_spender];
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens
     *      on behalf of msg.sender. This method is included for ERC20
     *      compatibility. `increaseAllowance` and `decreaseAllowance` should be
     *      used instead.
     *
     *      Changing an allowance with this method brings the risk that someone
     *      may transfer both the old and the new allowance - if they are both
     *      greater than zero - if a transfer transaction is mined before the
     *      later approve() call is mined.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value)
        public
        returns (bool)
    {
        _allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
     * @dev Mints new tokens, increasing totalSupply.
     */
    function mint(address _account, uint256 _amount) external onlyVault {
        _mint(_account, _amount);
    }

    /**
     * @dev Creates `_amount` tokens and assigns them to `_account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address _account, uint256 _amount) internal nonReentrant {
        require(_account != address(0), "Mint to the zero address");

        // Account
        (int256 toRebasingCreditsDiff, int256 toNonRebasingSupplyDiff) 
            = _adjustAccount(_account, int256(_amount));
        // Globals
        _adjustGlobals(toRebasingCreditsDiff, toNonRebasingSupplyDiff);
        _totalSupply = _totalSupply + _amount;

        require(_totalSupply < MAX_SUPPLY, "Max supply");
        emit Transfer(address(0), _account, _amount);
    }

    /**
     * @dev Burns tokens, decreasing totalSupply.
     */
    function burn(address account, uint256 amount) external onlyVault {
        _burn(account, amount);
    }

    /**
     * @dev Destroys `_amount` tokens from `_account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `_account` cannot be the zero address.
     * - `_account` must have at least `_amount` tokens.
     */
    function _burn(address _account, uint256 _amount) internal nonReentrant {
        require(_account != address(0), "Burn from the zero address");
        if (_amount == 0) {
            return;
        }

        // Account
        (int256 toRebasingCreditsDiff, int256 toNonRebasingSupplyDiff) 
            = _adjustAccount(_account, -int256(_amount));
        // Globals
        _adjustGlobals(toRebasingCreditsDiff, toNonRebasingSupplyDiff);
        _totalSupply = _totalSupply - _amount;

        emit Transfer(_account, address(0), _amount);
    }

    /**
     * @dev Get the credits per token for an account. Returns a fixed amount
     *      if the account is non-rebasing.
     * @param _account Address of the account.
     */
    function _creditsPerToken(address _account)
        internal
        view
        returns (uint256)
    {
        if (nonRebasingCreditsPerToken[_account] != 0) {
            return nonRebasingCreditsPerToken[_account];
        } else {
            return _rebasingCreditsPerToken;
        }
    }

    /**
     * @dev Is an account using rebasing accounting or non-rebasing accounting?
     *      Also, ensure contracts are non-rebasing if they have not opted in.
     * @param _account Address of the account.
     */
    function _isNonRebasingAccount(address _account) internal returns (bool) {
        bool isContract = _account.code.length > 0;
        if (isContract && rebaseState[_account] == RebaseOptions.NotSet && nonRebasingCreditsPerToken[_account] != 0) {
            _rebaseOptOut(msg.sender);
        }
        return nonRebasingCreditsPerToken[_account] > 0;
    }

    function _balanceToRebasingCredits(uint256 balance) internal view returns (uint256) {
        // Rounds up, because we need to ensure that accounts allways have
        // at least the balance that they should have.
        // Note this should always be used on an absolute account value,
        // not on a possibly negative diff, because then the rounding would be wrong.
        return ((balance) * _rebasingCreditsPerToken + 1e18 - 1) / 1e18;
    }

    /**
     * @notice Enable rebasing for an account.
     * @dev Add a contract address to the non-rebasing exception list. The
     * address's balance will be part of rebases and the account will be exposed
     * to upside and downside.
     * @param _account Address of the account.
     */
    function governanceRebaseOptIn(address _account)
        public
        nonReentrant
        onlyGovernor
    {
        _rebaseOptIn(_account);
    }

    /**
     * @dev Add a contract address to the non-rebasing exception list. The
     * address's balance will be part of rebases and the account will be exposed
     * to upside and downside.
     */
    function rebaseOptIn() public nonReentrant {
        _rebaseOptIn(msg.sender);
    }

    function _rebaseOptIn(address _account) internal {
        require(_isNonRebasingAccount(_account), "Account has not opted out");
        require(rebaseState[msg.sender] != RebaseOptions.YieldDelegationTarget, "Cannot opt in while yield delegating");

        uint256 balance = balanceOf(msg.sender);
        
        // Account
        rebaseState[msg.sender] = RebaseOptions.OptIn;
        nonRebasingCreditsPerToken[msg.sender] = 0;
        _creditBalances[msg.sender] = _balanceToRebasingCredits(balance);

        // Globals
        nonRebasingSupply -= balance;
        _rebasingCredits += _creditBalances[msg.sender];

        emit AccountRebasingEnabled(_account);
    }

    function rebaseOptOut() public nonReentrant {
        _rebaseOptOut(msg.sender);
    }

    function _rebaseOptOut(address _account) internal {
        require(!_isNonRebasingAccount(_account), "Account has not opted in");
        require(rebaseState[_account] != RebaseOptions.YieldDelegationSource, "Cannot opt out while receiving yield");
        
        uint256 oldCredits = _creditBalances[_account];
        uint256 balance = balanceOf(_account);
        
        // Account
        rebaseState[_account] = RebaseOptions.OptOut;
        nonRebasingCreditsPerToken[_account] = 1e18;
        _creditBalances[_account] = balance;

        // Globals
        nonRebasingSupply += balance;
        _rebasingCredits -= oldCredits;

        emit AccountRebasingDisabled(_account);
    }

    /**
     * @dev Modify the supply without minting new tokens. This uses a change in
     *      the exchange rate between "credits" and OUSD tokens to change balances.
     * @param _newTotalSupply New total supply of OUSD.
     */
    function changeSupply(uint256 _newTotalSupply)
        external
        onlyVault
        nonReentrant
    {
        require(_totalSupply > 0, "Cannot increase 0 supply");

        if (_totalSupply == _newTotalSupply) {
            emit TotalSupplyUpdatedHighres(
                _totalSupply,
                _rebasingCredits,
                _rebasingCreditsPerToken
            );
            return;
        }

        _totalSupply = _newTotalSupply > MAX_SUPPLY
            ? MAX_SUPPLY
            : _newTotalSupply;

        _rebasingCreditsPerToken = _rebasingCredits 
            * 1e18 / (_totalSupply - nonRebasingSupply);

        require(_rebasingCreditsPerToken > 0, "Invalid change in supply");

        _totalSupply = (_rebasingCredits * 1e18 / _rebasingCreditsPerToken)
            + nonRebasingSupply;

        emit TotalSupplyUpdatedHighres(
            _totalSupply,
            _rebasingCredits,
            _rebasingCreditsPerToken
        );
    }

    function delegateYield(address from, address to) external onlyGovernor nonReentrant() {
        require(from != to, "Cannot delegate to self");
        require(
            yieldFrom[to] == address(0) 
            && yieldTo[to] == address(0)
            && yieldFrom[from] == address(0)
            && yieldTo[from] == address(0)
            , "Blocked by existing yield delegation");
        require(!_isNonRebasingAccount(to), "Must delegate to a rebasing account");
        require(_isNonRebasingAccount(from), "Must delegate from a non-rebasing account");
        // Todo, tighter scope on above checks, partucularly the state
        
        yieldTo[from] = to;
        yieldFrom[to] = from;
        rebaseState[from] = RebaseOptions.YieldDelegationSource;
        rebaseState[to] = RebaseOptions.YieldDelegationTarget;

        uint256 balance = balanceOf(from);
        uint256 credits = _balanceToRebasingCredits(balance);
        // Local
        _creditBalances[from] = balance;
        _creditBalances[to] += credits;

        // Global
        nonRebasingSupply -= balance;
        _rebasingCredits += credits;
    }

    function undelegateYield(address from) external onlyGovernor nonReentrant() {
        require(yieldTo[from] != address(0), "");
        address to = yieldTo[from];
        uint256 fromBalance = balanceOf(from);
        uint256 toBalance = balanceOf(to);
        uint256 toCreditsBefore = _creditBalances[to];
        uint256 toNewCredits = _balanceToRebasingCredits(toBalance);
        
        yieldFrom[yieldTo[from]] = address(0);
        yieldTo[from] = address(0);
        rebaseState[from] = RebaseOptions.OptOut;
        _creditBalances[from] = fromBalance;
        nonRebasingCreditsPerToken[from] = 1e18;
        
        rebaseState[to] = RebaseOptions.OptIn;
        _creditBalances[to] = toNewCredits;
        nonRebasingCreditsPerToken[to] = 0; // Should be non-needed

        nonRebasingSupply += fromBalance;
        _rebasingCredits -= (toCreditsBefore - toNewCredits); // Should always go down or stay the same
    }
}