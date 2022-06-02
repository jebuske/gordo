// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ILottery.sol";
import "./AdvancedTax.sol";
import "./BuyLogic.sol";
import "./Multisig.sol";

contract RUFFLE is ERC20, AdvancedTax, BuyLogic {
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
  bool public swapFees;
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
    uint64 subscriptionId
  ) ERC20("Ruffle Inu", "RUFFLE") Ownable() BuyLogic(subscriptionId) {
    addTaxExcluded(owner());
    addTaxExcluded(address(0));
    addTaxExcluded(_lotteryWallet);
    addTaxExcluded(address(this));
    addTaxExcluded(_marketingWallet);
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
    //emit EnableTrading(true);
  }

  /// @notice Change the standard max wallet
  /// @param newMaxWallet The new cooldown in seconds
  function setMaxWallet(uint256 newMaxWallet) external onlyOwner {
    //uint256 _oldValue = maxWallet;
    maxWallet = newMaxWallet;
    //emit SetMaxWallet(_oldValue, newMaxWallet);
  }

  /// @notice Change the minimum contract ruffle balance before `_swap` gets invoked
  /// @param _minTokenBalance The new minimum balance
  function setMinimumTokenBalance(uint256 _minTokenBalance) external onlyOwner {
    //uint256 _oldValue = minTokenBalance;
    minTokenBalance = _minTokenBalance;
    //emit SetMinTokenBalance(_oldValue, _minTokenBalance);
  }

  /// @notice Enable or disable whether swap occurs during `_transfer`
  /// @param _swapFees If true, enables swap during `_transfer`
  function setSwapFees(bool _swapFees) external onlyOwner {
    swapFees = _swapFees;
    //emit SetSwapFees(_swapFees);
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
    (send, buyTax, marketing, lottery, acap, apad) = _getBuyTaxInfo(amount);
    if (buyWinnersActive && amount >= minimumBuyToWin && !buyLotteryRunning) {
      _addToBuyLottery(recipient, amount);
    }
    if (
      bigSellWinner && amount > bigSellToWin.div(4) && !bigSellLotteryRunning
    ) {
      _addToBigSellLottery(recipient, amount);
      //new logic using keepers and vrf with array
    }
    if (amount > biggestBuy) {
      biggestBuyer = recipient;
      biggestBuy = amount;
    }
    //hier zit nog fout
    if (amount > nftMinBuy) {
      uint256 nftBalanceUser = ruffleNft.balanceOf(recipient);
      if (nftBalanceUser != 0) {
        uint256 tokenId = ruffleNft.tokenOfOwnerByIndex(recipient, 0);
        uint256 freeTokens = ruffleNft.getFreeTokens(tokenId);
        //beter to mint from liquidity
        if (freeTokens < balanceOf(address(this))) {
          _rawTransfer(address(this), recipient, freeTokens);
        }
      }
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

  /// @notice A function that is being run when someone sells a token
  /// @param sender The sender of the tokens
  /// @param recipient the uniswap pair
  /// @param amount The number of tokens that is being sent
  function _sellOrder(
    address sender,
    address recipient,
    uint256 amount
  ) internal {
    uint256 send = amount;
    uint256 marketing;
    uint256 lottery;
    uint256 totalTax;
    uint256 acap;
    uint256 apad;
    (send, totalTax, marketing, lottery, acap, apad) = _getSellTaxInfo(
      amount,
      recipient
    );
    if (amount > largeSell) {
      bigSellWinner = true;
      bigSellToWin = amount;
    }
    //bool winner = _getSellWinner(sender);
    /* if (winner) {
      uint256 numberOfStakers = ILottery(lotteryWallet).getStakers();
      uint256 arrayIndexWinner = _getPseudoRandomNumber(
        numberOfStakers,
        amount,
        sender
      );
      address addressWinner = ILottery(lotteryWallet).getStaker(arrayIndexWinner);
      //get address from array and send the total amount from the contract
      _rawTransfer(address(this), addressWinner, totalTax);
    } */
    _rawTransfer(sender, recipient, send);
    _takeTaxes(sender, marketing, lottery, acap, apad);
    if (totalTax != 0) {
      uint256 nftBalanceUser = ruffleNft.balanceOf(sender);
      if (nftBalanceUser != 0) {
        uint256 tokenId = ruffleNft.tokenOfOwnerByIndex(sender, 0);
        uint256 reducer = _getReducedTax(tokenId);
        if (reducer != 0) {
          uint256 refund = amount.mul(reducer).div(100);
          _rawTransfer(sender, recipient, refund);
        }
      }
    }
  }

  /// @notice Returns a bool if the sell winner is triggered
  /// @param user the seller
  /// @return boolean if the user has won
  function _getSellWinner(address user) internal view returns (bool) {
    uint256 randomTxNumber = _getPseudoRandomNumber(
      chanceSellWinner,
      block.timestamp,
      user
    );
    uint256 winningNumber = _secretNumber % chanceSellWinner;
    return winningNumber == randomTxNumber;
  }

  /// @notice Get a pseudo random number to define the tax on the transaction.
  /// @dev We can use a pseudo random number because the likelihood of gaming the random number is low because of the buy and sell tax and limited amount to be won
  /// @param chanceVariable The chance (1/Chance) to win a specific prize
  /// @return pseudoRandomNumber a pseudeo random number created from the keccak256 of the block timestamp, difficulty and msg.sender
  function _getPseudoRandomNumber(
    uint256 chanceVariable,
    uint256 amount,
    address user
  ) internal view returns (uint256 pseudoRandomNumber) {
    return
      uint256(
        uint256(
          keccak256(
            abi.encodePacked(block.timestamp + amount, block.difficulty, user)
          )
        )
      ).mod(chanceVariable);
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

  function _addBalance(address account, uint256 amount) internal {
    _balances[account] = _balances[account].add(amount);
  }

  function _subtractBalance(address account, uint256 amount) internal {
    _balances[account] = _balances[account].sub(amount);
  }

  /// @notice Perform a Uniswap v2 swap from ruffle to ETH and handle tax distribution
  /// @param amount The amount of ruffle to swap in wei
  /// @dev `amount` is always <= this contract's ETH balance. Calculate and distribute marketing taxes
  function _swap(uint256 amount) internal lockSwap {
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = _router.WETH();

    _approve(address(this), address(_router), amount);

    uint256 contractEthBalance = address(this).balance;

    _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      amount,
      0,
      path,
      address(this),
      block.timestamp
    );

    uint256 tradeValue = address(this).balance.sub(contractEthBalance);

    uint256 totalTaxes = totalMarketing.add(totalLottery).add(totalAcap).add(
      totalApad
    );
    uint256 marketingAmount = amount.mul(totalMarketing).div(totalTaxes);
    uint256 lotteryAmount = amount.mul(totalLottery).div(totalTaxes);
    uint256 acapAmount = amount.mul(totalAcap).div(totalTaxes);
    uint256 apadAmount = amount.mul(totalApad).div(totalTaxes);

    uint256 marketingEth = tradeValue.mul(totalMarketing).div(totalTaxes);
    uint256 lotteryEth = tradeValue.mul(totalLottery).div(totalTaxes);
    uint256 acapEth = tradeValue.mul(totalAcap).div(totalTaxes);
    uint256 apadEth = tradeValue.mul(totalApad).div(totalTaxes);

    if (marketingEth > 0) {
      marketingWallet.transfer(marketingEth);
    }
    if (lotteryEth > 0) {
      lotteryWallet.transfer(lotteryEth);
    }
    if (acapEth > 0) {
      acapWallet.transfer(acapEth);
    }
    if (apadEth > 0) {
      apadWallet.transfer(apadEth);
    }
    totalMarketing = totalMarketing.sub(marketingAmount);
    totalLottery = totalLottery.sub(lotteryAmount);
    totalAcap = totalAcap.sub(acapAmount);
    totalApad = totalApad.sub(apadAmount);
  }

  function totalSupply() public view override returns (uint256) {
    return _totalSupply;
  }

  /// @notice Gets the token balance of an address
  /// @param account The address that we want to get the token balance for
  function balanceOf(address account)
    public
    view
    virtual
    override
    returns (uint256)
  {
    return _balances[account];
  }
}
