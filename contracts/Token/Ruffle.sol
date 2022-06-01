contract RUFFLE is ERC20, AdvancedTax {
  using SafeMath for uint256;

  modifier lockSwap() {
    _inSwap = true;
    _;
    _inSwap = false;
  }

  modifier liquidityAdd() {
    _inLiquidityAdd = true;
    _;
    _inLiquidityAdd = false;
  }

  //token
  uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
  uint256 public maxWallet;
  uint256 public minTokenBalance = 9_490_000 ether; //This is the max amount you can win with a 500k buy to not go over max wallet

  //uniswap
  IUniswapV2Router02 internal _router = IUniswapV2Router02(address(0));
  address internal _pair;
  bool internal _inSwap = false;
  bool internal _inLiquidityAdd = false;
  bool public tradingActive = false;
  uint256 public tradingActiveBlock;
  uint256 public deadBlocks = 2;
  uint256 public cooldown = 45;
  mapping(address => uint256) private _balances;
  mapping(address => uint256) private lastBuy;

  //

  constructor(
    address _uniswapFactory,
    address _uniswapRouter,
    address payable _lotteryWallet,
    address payable _marketingWallet,
    address payable _apadWallet,
    address payable _acapWallet
  ) ERC20("Ruffle Inu", "RUFFLE") Ownable() {
    addTaxExcluded(owner());
    addTaxExcluded(address(0));
    addTaxExcluded(_lotteryWallet);
    addTaxExcluded(address(this));
    addTaxExcluded(_marketingWallet);
    setChanceToWin0SellTax(50);
    _mint(address(this), MAX_SUPPLY);
    lotteryWallet = _lotteryWallet;
    marketingWallet = _marketingWallet;
    _router = IUniswapV2Router02(_uniswapRouter);
    IUniswapV2Factory uniswapContract = IUniswapV2Factory(_uniswapFactory);
    _pair = uniswapContract.createPair(address(this), _router.WETH());
    _secretNumber = uint256(
      keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))
    );
  }

  //receive function
  receive() external payable {}

  /// @notice Add liquidity to uniswap
  /// @param tokens The number of tokens to add when liquidity is added
  function addLiquidity(uint256 tokens)
    external
    payable
    onlyOwner
    liquidityAdd
  {
    _approve(address(this), address(_router), tokens);

    _router.addLiquidityETH{ value: msg.value }(
      address(this),
      tokens,
      0,
      0,
      owner(),
      // solhint-disable-next-line not-rely-on-time
      block.timestamp
    );
  }

  /// @notice a function to airdrop tokens to an array of accounts
  /// @dev -mint function protected by total supply
  function airdrop(address[] memory accounts, uint256[] memory amounts)
    external
    onlyOwner
  {
    require(accounts.length == amounts.length, "array lengths must match");

    for (uint256 i = 0; i < accounts.length; i++) {
      _rawTransfer(address(this), accounts[i], amounts[i]);
    }
  }

  /// @notice Enables trading on Uniswap
  /// @param _tradingActive the new value of tradingActive
  function enableTrading(bool _tradingActive) external onlyOwner {
    tradingActive = _tradingActive;
    emit EnableTrading(true);
  }

  /// @notice Change the standard max wallet
  /// @param newMaxWallet The new cooldown in seconds
  function setMaxWallet(uint256 newMaxWallet) external onlyOwner {
    uint256 _oldValue = maxWallet;
    maxWallet = newMaxWallet;
    emit SetMaxWallet(_oldValue, newMaxWallet);
  }

  /// @notice Change the minimum contract ruffle balance before `_swap` gets invoked
  /// @param _minTokenBalance The new minimum balance
  function setMinimumTokenBalance(uint256 _minTokenBalance) external onlyOwner {
    uint256 _oldValue = minTokenBalance;
    minTokenBalance = _minTokenBalance;
    emit SetMinTokenBalance(_oldValue, _minTokenBalance);
  }

  /// @notice Enable or disable whether swap occurs during `_transfer`
  /// @param _swapFees If true, enables swap during `_transfer`
  function setSwapFees(bool _swapFees) external onlyOwner {
    swapFees = _swapFees;
    emit SetSwapFees(_swapFees);
  }

  /// @notice A function that is being run when someone buys the token
  /// @param sender The pair
  /// @param recipient The receiver of the tokens
  /// @param amount The number of tokens that is being sent
  function _buyOrder(
    address sender,
    address recipient,
    uint256 amount
  ) internal {
    uint256 send = amount;
    uint256 marketing;
    uint256 lottery;
    uint256 acap;
    uint256 apad;
    uint256 buyTax;
    (send, buyTax, marketing, lottery, acap, apad) = _getBuyTaxInfo(
      amount,
      recipient
    );
    if (buyWinnersActive && amount >= minimumBuyToWin) {
      _addToBuyLottery(recipient);
    }
    if (bigSellWinner && bigSellParticipants < 20) {
      _addToBigSellLottery(recipient, amount);
      //new logic using keepers and vrf with array
    }
    if (amount > biggestBuy) {
      biggestBuyer = recipient;
      biggestBuy = amount;
    }
    _rawTransfer(sender, recipient, send);
    _takeTaxes(sender, marketing, lottery, acap, apad);
    lastBuy[recipient] = block.timestamp;
  }

  function _mint(address account, uint256 amount) internal override {
    require(_totalSupply.add(amount) <= MAX_SUPPLY, "Max supply exceeded");
    _totalSupply = _totalSupply.add(amount);
    _addBalance(account, amount);
    emit Transfer(address(0), account, amount);
  }

  function _rawTransfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal {
    require(sender != address(0), "transfer from the zero address");
    require(recipient != address(0), "transfer to the zero address");

    uint256 senderBalance = balanceOf(sender);
    require(senderBalance >= amount, "transfer amount exceeds balance");
    unchecked {
      _subtractBalance(sender, amount);
    }
    _addBalance(recipient, amount);

    emit Transfer(sender, recipient, amount);
  }

  /// @notice Transfers ruffle from an account to this contract for taxes
  /// @param _account The account to transfer ruffle from
  /// @param _marketingAmount The amount of marketing tax to transfer
  /// @param _lotteryAmount The amount of treasury tax to transfer
  function _takeTaxes(
    address _account,
    uint256 _marketingAmount,
    uint256 _lotteryAmount,
    uint256 _acapAmount,
    uint256 _apadAmount
  ) internal {
    require(_account != address(0), "taxation from the zero address");

    uint256 totalAmount = _marketingAmount
      .add(_lotteryAmount)
      .add(_acapAmount)
      .add(_apadAmount);
    _rawTransfer(_account, address(this), totalAmount);
    totalMarketing = totalMarketing.add(_marketingAmount);
    totalLottery = totalLottery.add(_lotteryAmount);
    totalAcap = totalAcap.add(_acapAmount);
    totalApad = totalApad.add(_apadAmount);
  }

  /// @notice A function that overrides the standard transfer function and takes into account the taxes
  /// @param sender The sender of the tokens
  /// @param recipient The receiver of the tokens
  /// @param amount The number of tokens that is being sent
  function _transfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    if (isTaxExcluded(sender) || isTaxExcluded(recipient)) {
      _rawTransfer(sender, recipient, amount);
      return;
    }

    uint256 contractTokenBalance = balanceOf(address(this));
    bool overMinTokenBalance = contractTokenBalance > minTokenBalance;

    if (sender != _pair && recipient != _pair) {
      _rawTransfer(sender, recipient, amount);
    }
    if (overMinTokenBalance && !_inSwap && sender != _pair && swapFees) {
      uint256 _amountAboveMinimumBalance = contractTokenBalance.sub(
        minTokenBalance
      );
      _swap(_amountAboveMinimumBalance);
    }
    require(tradingActive, "Trading is not yet active");
    if (sender == _pair) {
      if (cooldown > 0) {
        require(
          lastBuy[recipient] + cooldown <= block.timestamp,
          "Cooldown is still active"
        );
      }
      _buyOrder(sender, recipient, amount);
    } else if (recipient == _pair) {
      _sellOrder(sender, recipient, amount);
    }
  }
}