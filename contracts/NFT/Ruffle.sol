//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./INFT721.sol";
import "../TOKEN/ILottery.sol";
import "../TOKEN/IRuffle.sol";

contract Ruffle is ERC721, ERC721Enumerable, ERC721Burnable, Ownable {
  using Counters for Counters.Counter;
  Counters.Counter private _tokenIds;
  uint256 MAX_MINTS = 1;
  uint256 MAX_SUPPLY = 500;
  uint256 public mintRate = 0.0069 ether;
  mapping(address => bool) hasMinted;
  address public lotteryAddress;
  IRuffle public ruffleToken;

  struct NFTProperties {
    uint256 lotteryMultiplier;
    uint256 freeTokens;
    uint256 taxReducer;
    bool freeSell;
  }

  mapping(uint256 => NFTProperties) nftIdProperties;

  string public baseURI =
    "ipfs://bafybeieyetlp2c2vubffzjjap7utuz5jwo2k5b5kupvezfchc5tnfg4fh4/";

  constructor() ERC721("Ruffles", "RUFFLEs") {}

  /// @notice a function to update onchain properties
  function updateMapping(uint256 tokenId) internal {
    uint256 _lotteryMultiplier;
    uint256 _freeTokens;
    uint256 _taxReducer;
    bool _freeSell;
    //Request random number
    uint256 randomNumber = uint256(
      keccak256(abi.encodePacked(block.timestamp, block.difficulty))
    );
    if (randomNumber.mod(5) == 0) {
      _freeSell = true;
    } else if (randomNumber.mod(7) == 1) {
      _taxReducer = 100;
    } else if (randomNumber.mod(25) == 1) {
      _taxReducer = 250;
    } else if (randomNumber.mod(100) == 1) {
      _taxReducer == 500;
    }

    if ((randomNumber.add(67)).mod(5) == 2) {
      _freeTokens = 100_000.mul(10**18);
    } else if ((randomNumber.add(67)).mod(10) == 2) {
      _freeTokens = 250_000.mul(10**18);
    } else if ((randomNumber.add(67)).mod(50) == 2) {
      _freeTokens = 500_000.mul(10**18);
    } else if ((randomNumber.add(67)).mod(100) == 2) {
      _freeTokens = 1_000_000.mul(10**18);
    }

    if ((randomNumber.add(19)).mod(10) == 7) {
      _lotteryMultiplier = 110;
    } else if ((randomNumber.add(19)).mod(20) == 7) {
      _lotteryMultiplier = 125;
    } else if ((randomNumber.add(19)).mod(100) == 7) {
      _lotteryMultiplier = 150;
    }

    nftIdProperties[tokenId] = NFTProperties(
      _lotteryMultiplier,
      _freeTokens,
      _taxReducer,
      _freeSell
    );
  }

  function mint() external payable {
    require(hasMinted[msg.sender] == false);
    require(totalSupply() + 1 <= MAX_SUPPLY, "Not enough tokens left");
    require(msg.value >= (mintRate), "Not enough ether sent");
    _tokenIds.increment();
    uint256 newItemId = _tokenIds.current();
    hasMinted[msg.sender] = true;
    _safeMint(msg.sender, newItemId);
  }

  function claimLongStaker() external {
    uint256 timeStaked = ILottery(lotteryAddress).getTimeStaked(msg.sender);
    require(
      timeStaked > 100000,
      "you have to stake longer to be elgible to claim"
    );
    require(totalSupply() + 1 <= MAX_SUPPLY, "Not enough tokens left");
    _safeMint(msg.sender, 1);
  }

  function claimBiggestBuyer() external {
    bool isBiggestBuyer = ruffleToken.getIsBiggestBuyer(msg.sender);
    if (isBiggestBuyer) _safeMint(msg.sender, 1);
  }

  /// @notice a function to set the address of the ruffle token
  /// @param ruffleAddress is the address of the ruffle token
  function setRuffleInuToken(IRuffle ruffleAddress) external onlyOwner {
    ruffleToken = IRuffle(ruffleAddress);
    //emit SetRuffleInuToken(ruffleAddress);
  }

  function setLotteryAddress(address _lotteryAddress) external onlyOwner {
    lotteryAddress = _lotteryAddress;
  }

  function withdraw() external payable onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }

  function _baseURI() internal view override returns (string memory) {
    return baseURI;
  }

  function setMintRate(uint256 _mintRate) public onlyOwner {
    mintRate = _mintRate;
  }

  function getLotteryMultiplier(uint256 n) public view returns (uint256) {
    return nftIdProperties[n].lotteryMultiplier;
  }

  function getOnBuyMultiplier(uint256 n) public view returns (uint256) {
    return nftIdProperties[n].onBuyMultiplier;
  }

  function getFreeTokens(uint256 n) public view returns (uint256) {
    return nftIdProperties[n].freeTokens;
  }

  function getTaxReducer(uint256 n) public view returns (uint256) {
    return nftIdProperties[n].taxReducer;
  }

  function getBigSellEntries(uint256 n) public view returns (bool) {
    return nftIdProperties[n].bigSellEntry;
  }

  function getFreeSell(uint256 n) public view returns (bool) {
    return nftIdProperties[n].freeSell;
  }

  function getBurnEntries(uint256 n) public view returns (uint256) {
    return nftIdProperties[n].burnEntries;
  }

  // The following functions are overrides required by Solidity.

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal override(ERC721, ERC721Enumerable) {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
//https://rinkeby.etherscan.io/address/0xc14ab28ed0e626ee0558ee7dfb81d3fe879e5788#code
