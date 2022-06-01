//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Ruffle is ERC721, ERC721Enumerable, ERC721Burnable, Ownable {
  uint256 MAX_MINTS = 1;
  uint256 MAX_SUPPLY = 500;
  uint256 public mintRate = 0.0069 ether;
  mapping(address => bool) hasMinted;

  struct NFTProperties {
    uint256 lotteryMultiplier;
    uint256 onBuyMultiplier;
    uint256 buyAmountMultiplier;
    uint256 taxReducer;
    bool bigSellEntry;
    bool freeSell;
  }

  mapping(uint256 => NFTProperties) nftIdProperties;

  string public baseURI =
    "ipfs://bafybeieyetlp2c2vubffzjjap7utuz5jwo2k5b5kupvezfchc5tnfg4fh4/";

  constructor() public ERC721("Ruffles", "RUFFLEs") {}

  /// @notice a function to update onchain properties
  /// @dev -mint function protected by total supply
  function updateMappings(
    uint256[] memory tokenIds,
    uint256[] memory lotteryMultipliers,
    uint256[] memory onBuyMultipliers,
    uint256[] memory buyAmountMultipliers,
    uint256[] memory taxReducers,
    bool[] memory bigSellEntries
  ) external onlyOwner {
    require(
      tokenIds.length == lotteryMultipliers.length,
      "array lengths must match"
    );
    require(
      tokenIds.length == onBuyMultipliers.length,
      "array lengths must match"
    );
    require(
      tokenIds.length == buyAmountMultipliers.length,
      "array lengths must match"
    );
    require(tokenIds.length == taxReducers.length, "array lengths must match");
    require(
      tokenIds.length == bigSellEntries.length,
      "array lengths must match"
    );

    for (uint256 i = 0; i < tokenIds.length; i++) {
      nftIdProperties[tokenIds[i]] = NFTProperties(
        lotteryMultipliers[i],
        onBuyMultipliers[i],
        buyAmountMultipliers[i],
        taxReducers[i],
        bigSellEntries[i]
      );
    }
  }

  function mint() external payable {
    require(hasMinted[msg.sender] == false);
    require(totalSupply() + 1 <= MAX_SUPPLY, "Not enough tokens left");
    require(msg.value >= (mintRate), "Not enough ether sent");
    _safeMint(msg.sender, 1);
    hasMinted[msg.sender] = true;
  }

  function claim() external {
    uint256 timeStaked = ILottery(lotteryAddress).getTimeStaked(msg.sender);
    require(
      timeStaked > 100000,
      "you have to stake longer to be elgible to claim"
    );
    require(totalSupply() + 1 <= MAX_SUPPLY, "Not enough tokens left");
    _safeMint(msg.sender, 1);
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

  function getBuyAmountMultiplier(uint256 n) public view returns (uint256) {
    return nftIdProperties[n].buyAmountMultiplier;
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
