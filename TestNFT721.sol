// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

//Goerli: 0x98Bd4e74DE0fB950a97A67c70179dE92F1BB01F6
contract TestNFT721 is ERC721, Ownable {
    mapping(uint => string) private tokenURIs;
    uint256 public totalSupply;
    uint256 public maxMintAmount = 20;
    
    constructor() ERC721("Test ERC721 NFTs", "TSTO") Ownable(msg.sender) {}

    function mint(address to) public onlyOwner {
        totalSupply++;
        _safeMint(to, totalSupply);
    }

    function mintAmount(address _to, uint256 _amount) public onlyOwner {
        require(_amount <= maxMintAmount, "AMOUNT MUST BE 20 or LESS");
        for (uint256 i = 0; i < _amount; i++) {
            mint(_to);
        }
    }

    /**
    * @dev Returns an URI for a given token ID
    */
    function tokenURI(uint256 _tokenId) override public view returns(string memory) {
        return tokenURIs[_tokenId];
    }

    /**
    * @dev Allows Admin to set the URI of a single token.
    * Note: Set _isIpfsCID to true if using only IPFS CID for the _uri.
    */
    function setURI(uint _id, string memory _uri, bool _isIpfsCID) external onlyOwner {
        if (_isIpfsCID) {
            string memory _uriIPFS = string(abi.encodePacked(
                "ipfs://",
                _uri,
                "/",
                Strings.toString(_id),
                ".json"
            ));

            tokenURIs[_id] = _uriIPFS;
        }
        else {
            tokenURIs[_id] = _uri;
        }
    }
}