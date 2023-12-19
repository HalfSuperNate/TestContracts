// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract TestNFT1155 is ERC1155Supply, Ownable(msg.sender) {
    string public name = "Test ERC1155 NFTs"; //name your NFT collection
    string public symbol = "TEFF"; //few letters to represent the symbol of your collection
    
    uint256 public tokenCounter;
    uint256 public batchCounter;
    uint256 private createFee = 0.001 ether;
    uint256 private mintFee = 0.001 ether;
    uint256 private adjustFee = 0.0005 ether;
    uint256 private sellFee = 10;
    uint256 private _dMax = 1000;
    uint256 private _cPBuffer = 800;
    uint256 private minBalance = 1000000000000000;
    address private vault;

    mapping(uint => uint) private supplyLimit;
    mapping(uint => uint) private mintCost;
    mapping(uint => uint[3]) public batchStartEndOn;
    mapping(uint => bool) private useAsBatch;
    mapping(uint => bool) private paused;
    mapping(uint => bool) private creatorLock;
    mapping(uint => bool) private mintInOrder;

    mapping(uint => string) private tokenURIs;
    mapping(uint => string[2]) private batchPrefixSuffix;
    mapping(uint => address) private tokenCreator;
    mapping(uint => address[]) public tokenOwners;
    mapping(uint => mapping(address => bool)) public listedForSale;
    mapping(uint => mapping(address => uint)) public salePrice;

    mapping(address => uint) public creatorPercentage;
    mapping(address => address payable) public creatorRouting;
    mapping(address => uint) public strikes;

    constructor() ERC1155("") {
        vault = msg.sender;
    }

    /**
    @dev Mints a single token and assigns it to the specified account.
    @param account The account to which the token will be assigned.
    @param id The ID of the token to mint.
    @param amount The amount of the token to mint.
    @param data Optional data to pass to the recipient.
    */
    function mint(address account, uint256 id, uint256 amount, bytes memory data) public onlyOwner
    {
        _mint(account, id, amount, data);
    }

    /**
    @dev Mints multiple tokens and assigns them to the specified account.
    @param to The account to which the tokens will be assigned.
    @param ids The IDs of the tokens to mint.
    @param amounts The amounts of each token to mint.
    @param data Optional data to pass to the recipient.
    */
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) public onlyOwner
    {
        _mintBatch(to, ids, amounts, data);
    }

    /**
    @dev Mint tokens to a specified address.
    @param to The address to which the tokens will be minted to.
    @param id The token ID to be minted.
    @param amount The amount of tokens to be minted.
    Requirements:
        Minting must not be paused for the token ID.
        If the token is minted in order, the batch supply limit must not be exceeded.
        If the token is minted directly, the supply limit must not be exceeded.
        If the sender is not the creator of the token, sufficient funds must be provided to cover the cost.
    Emits an {IERC1155-TransferSingle} event on successful minting and transfer of the tokens.
    */
    function __mint(address to, uint256 id, uint256 amount) public payable {
        uint _batch = getBatch(id);
        require(!getPaused(id), "Minting Paused For Token ID");
        if (!mintInOrder[_batch]) {
            require(totalSupply(id) + amount <= getSupplyLimit(id), "Supply Limit Exceeded");
        }
        if (msg.sender != getCreator(id)) {
            require(msg.value >= getCost(id) * amount, "Insufficient Funds");
            address payable creatorRoutingAddress = payable(creatorRouting[getCreator(id)]);
            sendFunds(creatorRoutingAddress, msg.value);
        }
        
        if (mintInOrder[_batch]) {
            require(batchStartEndOn[_batch][2] + amount <= batchStartEndOn[_batch][1], "Batch Limit Exceeded");
            uint256[] memory _ids = new uint256[](amount);
            uint256[] memory _amounts = new uint256[](amount);
            for (uint256 i = 0; i < amount; i++) {
                batchStartEndOn[_batch][2] += 1;
                require(totalSupply(batchStartEndOn[_batch][2]) + 1 <= getSupplyLimit(batchStartEndOn[_batch][2]), "Supply Limit Exceeded For Batch Item");
                _ids[i] = batchStartEndOn[_batch][2];
                _amounts[i] = 1;
            }
            _mintBatch(to, _ids, _amounts, "");
        }
        else {
            _mint(to, id, amount, "");
        }
    }

    /**
    @dev Mint multiple tokens to a specified address.
    @param to The address to which the tokens will be minted to.
    @param ids The array of token IDs to be minted.
    @param amounts The corresponding array of token amounts to be minted.
    Requirements:
        The to address must not be zero.
        The lengths of the ids and amounts arrays must be the same.
        Minting must not be paused for any of the token IDs.
        The supply limits must not be exceeded for direct supply or batch supply tokens.
        Sufficient funds must be provided to cover the total cost of the tokens.
    Emits an {IERC1155-TransferBatch} event on successful minting and transfer of the tokens.
    */
    function __mintCart(address to, uint256[] memory ids, uint256[] memory amounts) public payable {
        require(to != address(0), "Address cannot be 0");
        require(ids.length == amounts.length, "ids and amounts lengths are off");
        uint256 totalCost;
        uint256 _arrayLength;
        for (uint256 a = 0; a < ids.length; a++) {
            require(!getPaused(ids[a]), "Minting Paused For Token ID");
            uint _batch = getBatch(ids[a]);
            if (!mintInOrder[_batch]) {
                _arrayLength++;
                require(totalSupply(ids[a]) + amounts[a] <= getSupplyLimit(ids[a]), "Supply Limit Exceeded");
            }
            else {
                _arrayLength += amounts[a];
                require(batchStartEndOn[_batch][2] + amounts[a] <= batchStartEndOn[_batch][1], "Batch Limit Exceeded");
            }

            if (msg.sender != getCreator(ids[a])) {
                totalCost += getCost(ids[a]) * amounts[a];
            }
            
        }
        require(msg.value >= totalCost, "Insufficient Funds");
        
        uint256 _onArrayIndex;
        uint256[] memory _idsTotal = new uint256[](_arrayLength);
        uint256[] memory _amountsTotal = new uint256[](_arrayLength);
        for (uint256 i = 0; i < ids.length; i++) {
            uint _batch = getBatch(ids[i]);
            if (!mintInOrder[_batch]) {
                //direct supply
                _idsTotal[_onArrayIndex] = ids[i];
                _amountsTotal[_onArrayIndex] = amounts[i];
                _onArrayIndex++;
            }
            else {
                //batch supply
                for (uint256 k = 0; k < amounts[i]; k++) {
                    batchStartEndOn[_batch][2] += 1;
                    _idsTotal[_onArrayIndex] = batchStartEndOn[_batch][2];
                    _amountsTotal[_onArrayIndex] = 1;
                    _onArrayIndex++;
                }
            }
            
            if (msg.sender != getCreator(ids[i])) {
                uint256 _calcCost = getCost(ids[i]) * amounts[i];
                require(msg.value >= _calcCost, "Insufficient Funds");
                address payable creatorRoutingAddress = payable(creatorRouting[getCreator(ids[i])]);
                sendFunds(creatorRoutingAddress, _calcCost);
            }
        }
        
        _mintBatch(to, _idsTotal, _amountsTotal, "");
    }

    function mintCreatorToken(uint256 _numberOfTokens, string[] calldata _uri, uint256[] calldata _supply, uint256[] calldata _cost, bool[] calldata _paused, bool isBatch) private  {
        batchCounter++;
        if (isBatch) {
            require(_uri.length == 2, "Batch _uri must have 2 entries for Prefix and Suffix");
            require(_supply.length == 1, "Batch _supply must have 1 entry");
            require(_cost.length == 1, "Batch _cost must have 1 entry");
            require(_paused.length == 1, "Batch _paused must have 1 entry");

            useAsBatch[batchCounter] = true;
            //a batch defaults the mintInOrder state to true
            mintInOrder[batchCounter] = true;
            tokenCounter++;
            uint _id = tokenCounter;
            batchStartEndOn[batchCounter][0] = tokenCounter; //start
            tokenCounter += _numberOfTokens - 1;
            batchStartEndOn[batchCounter][1] = tokenCounter;//end
            batchStartEndOn[batchCounter][2] = _id; //on
            batchPrefixSuffix[batchCounter][0] = _uri[0];
            batchPrefixSuffix[batchCounter][1] = _uri[1];
            //a batch uses the first token entry to represent the batch data
            tokenCreator[_id] = msg.sender;
            supplyLimit[_id] = _supply[0];
            mintCost[_id] = _cost[0];
            paused[_id] = _paused[0];

            _mint(msg.sender, _id, 1, "");
        }
        else {
            require(_uri.length == 0 || _uri.length == _numberOfTokens, "Invalid URIs To Number Of Tokens");
            require(_supply.length == 0 || _supply.length == _numberOfTokens, "Invalid Supply To Number Of Tokens");
            require(_cost.length == 0 || _cost.length == _numberOfTokens, "Invalid Cost To Number Of Tokens");

            uint256[] memory _ids = new uint256[](_numberOfTokens);
            uint256[] memory _amounts = new uint256[](_numberOfTokens);

            batchStartEndOn[batchCounter][0] = tokenCounter + 1;
            batchStartEndOn[batchCounter][1] = tokenCounter + _numberOfTokens;
            for (uint256 i = 0; i < _numberOfTokens; i++) {
                tokenCounter++;
                _ids[i] = tokenCounter;
                _amounts[i] = 1;
                tokenCreator[tokenCounter] = msg.sender;

                if (_uri.length == _numberOfTokens) {
                    tokenURIs[tokenCounter] = _uri[i];
                }
                if (_supply.length == _numberOfTokens) {
                    supplyLimit[tokenCounter] = _supply[i];
                }
                if (_cost.length == _numberOfTokens) {
                    mintCost[tokenCounter] = _cost[i];
                }
                if (_paused.length == _numberOfTokens) {
                    paused[tokenCounter] = _paused[i];
                }
            }

            _mintBatch(msg.sender, _ids, _amounts, "");
        }
    }

    /**
    @dev Calculates the Batch Creation Fee.
    @param _X_ The number of tokens in Batch.
    Note: There are 5 tiers to calculate fee.
        1. _X_ <= 10 : (createFee * _X_) / 2
        2. _X_ <= 100 : (createFee * _X_) / 4
        3. _X_ <= 1000 : (createFee * _X_) / 8
        4. _X_ <= 10000 : (createFee * _X_) / 12
        5. _X_ < 10000 : (createFee * _X_) / 16
    */
    function getBatchCreateFee(uint256 _X_) public view returns(uint) {
        if (_X_ <= 10) {
            return (createFee * _X_) / 2;
        } else if (_X_ <= 100) {
            return (createFee * _X_) / 4;
        } else if (_X_ <= 1000) {
            return (createFee * _X_) / 8;
        } else if (_X_ <= 10000) {
            return (createFee * _X_) / 12;
        } else {
            return (createFee * _X_) / 16;
        }
    }

    /**
    @dev Creates a specified number of tokens with the given URIs.
    @param _numberOfTokens The number of tokens to mint.
    @param _uri The URIs of the tokens.
    @param _supply The supply limit of the tokens, if supply is 0 it is max supply.
    @param _cost The cost of the tokens to mint.
    @param _paused The pause state of the mint for the token.
    @param isBatch Flag true if using _uri[0] as Prefix and _uri[1] as Suffix for a Batch of tokens.
    Note: URI, Supply, Cost, and Pause State can be adjusted.
    */
    function _A_createTokens(uint256 _numberOfTokens, string[] calldata _uri, uint256[] calldata _supply, uint256[] calldata _cost, bool[] calldata _paused, bool isBatch) public payable {
        if (msg.sender != owner()) {
            require(strikes[msg.sender] < 3, "Banned Account");
            if (isBatch) {
                require(_numberOfTokens > 1 && msg.value >= getBatchCreateFee(_numberOfTokens), "Insufficient Funds");
            } else {
                require(_numberOfTokens > 0 && msg.value >= createFee * _numberOfTokens, "Insufficient Funds");
            }
        }
        creatorRouting[msg.sender] = payable(msg.sender);

        mintCreatorToken(_numberOfTokens, _uri, _supply, _cost, _paused, isBatch);
    }

    /**
    @dev Allows a user to purchase a token that is listed for sale.
    @param _id The ID of the token to purchase.
    */
    function _B_buyItem(uint _id) public payable {
        require(msg.sender != getCreator(_id), "You cannot purchase your own token");
        address[] memory _tokenOwners = getAddressArray(0,_id);
        require(_tokenOwners.length > 0, "Not Yet Created For Sale");
        for (uint256 i = 0; i < _tokenOwners.length; i++) {
            if (listedForSale[_id][_tokenOwners[i]]) {
                require(msg.value >= salePrice[_id][_tokenOwners[i]], "Insufficient Funds");
                uint _cP = creatorPercentage[getCreator(_id)];
                uint payoutToCreator = (msg.value * _cP) / _dMax;
                uint _sellFee = ((msg.value - payoutToCreator) * sellFee) / _dMax;
                uint payout = (msg.value - payoutToCreator) - _sellFee;
                if (_cP != 0 && payoutToCreator != 0) {
                    address payable creatorRoutingAddress = payable(creatorRouting[getCreator(_id)]);
                    sendFunds(creatorRoutingAddress, payoutToCreator);
                }
                if (payout != 0) {
                    address payable sellerAddress = payable(_tokenOwners[i]);
                    sendFunds(sellerAddress, payout);
                }

                IERC1155(address(this)).safeTransferFrom(_tokenOwners[i], msg.sender, _id, 1, "");
                listedForSale[_id][_tokenOwners[i]] = false;
                return;
            }
        }
        revert("Not Listed For Sale");
    }

    /**
    @dev Lists the specified token for sale at the given price.
    @param _id The ID of the token to sell.
    @param _salePrice The price at which to sell the token.
    @param isNotFree Flag indicating if the token is being sold for a price or for free.
    */
    function _C_sellItem(uint _id, uint _salePrice, bool isNotFree) public {
        require(balanceOf(msg.sender, _id) != 0, "Must own the token to sell it");
        if (isNotFree) {
            require(_salePrice != 0, "Must set a sale price");
        }
        else {
            require(_salePrice == 0, "Must set a sale price to 0 if it is Free");
        }
        listedForSale[_id][msg.sender] = true;
        salePrice[_id][msg.sender] = _salePrice;
        setApprovalForAll(address(this), true);
    }

    /**
    @dev Cancels the sale listing for the specified token.
    @param _id The ID of the token to cancel the sale for.
    */
    function _D_cancelSellItem(uint _id) public {
        listedForSale[_id][msg.sender] = false;
    }

    /**
    @dev Sets the value for a specific option.
    @param option The option to set. 
                  - Option 0: Mint fee.
                  - Option 1: Adjust fee.
                  - Option 2: Denominator max.
                  - Option 3: Minimum balance.
                  - Option 4: Sell fee.
                  - Option 5: Creator percentage buffer.
                  - Option 251: Set Mint In Order to false.
                  - Option 252: Set Mint In Order to true.
                  - Option 254: Set Creator Lock to false.
                  - Option 255: Set Creator Lock to true.
    @param value The value to set for the specified option.
    */
    function setOption(uint8 option, uint256 value) external onlyOwner {
        if (option == 0) {
            mintFee = value;
            return;
        }
        if (option == 1) {
            adjustFee = value;
            return;
        }
        if (option == 2) {
            _dMax = value;
            return;
        }
        if (option == 3) {
            minBalance = value;
            return;
        }
        if (option == 4) {
            sellFee = value;
            return;
        }
        if (option == 5) {
            _cPBuffer = value;
            return;
        }
        if (option == 251) {
            mintInOrder[getBatch(value)] = false;
            return;
        }
        if (option == 252) {
            mintInOrder[getBatch(value)] = true;
            return;
        }
        if (option == 254) {
            creatorLock[value] = false;
            return;
        }
        if (option == 255) {
            creatorLock[value] = true;
            return;
        }
        revert("Not An Option");
    }

    /**
    @dev Get the value for a specific option.
    @param option The option to get. 
                  - Option 0: Mint fee.
                  - Option 1: Adjust fee.
                  - Option 2: Denominator max.
                  - Option 3: Minimum balance.
                  - Option 4: Sell fee.
                  - Option 5: Creator percentage buffer.
                  - Option 253: Creator percentage max.
    */
    function getOptionValue(uint8 option) public view returns(uint) {
        if (option == 0) {
            return mintFee;
        }
        if (option == 1) {
            return adjustFee;
        }
        if (option == 2) {
            return _dMax;
        }
        if (option == 3) {
            return minBalance;
        }
        if (option == 4) {
            return sellFee;
        }
        if (option == 5) {
            return _cPBuffer;
        }
        if (option == 253) {
            return _dMax - _cPBuffer;
        }
        revert("Not An Option");
    }

    /**
    @dev Returns a batch ID from a token ID
    */
    function getBatch(uint256 _tokenId) public view returns(uint) {
        for (uint256 i = 1; i < batchCounter + 1; i++) {
            if (_tokenId >= batchStartEndOn[i][0] && _tokenId <= batchStartEndOn[i][1]) {
                return i;
            }
        }
        return 0;
    }

    /**
    @dev Returns an URI for a given token ID
    */
    function uri(uint256 _tokenId) override public view returns(string memory) {
        if(keccak256(abi.encodePacked((tokenURIs[_tokenId]))) != keccak256(abi.encodePacked(("")))) {
            return tokenURIs[_tokenId];
        }
        if(keccak256(abi.encodePacked((getBatchURI(_tokenId)))) != keccak256(abi.encodePacked(("")))) {
            return getBatchURI(_tokenId);
        }
        return "";
    }

    /**
    @dev Returns an URI for a given batch from a token ID
    */
    function getBatchURI(uint256 _tokenId) public view returns(string memory) {
        uint _batch = getBatch(_tokenId);
        if (keccak256(abi.encodePacked((batchPrefixSuffix[_batch][0]))) == keccak256(abi.encodePacked(("")))) {
            return "";
        }
        string memory _uri = string(abi.encodePacked(
            batchPrefixSuffix[_batch][0],
            Strings.toString(_tokenId),
            batchPrefixSuffix[_batch][1]
        ));
        return _uri;
    }

    /**
    * Set the URI of a single token.
    */
    function setURI(uint _id, string calldata _prefix, string calldata _suffix, bool _isIpfsCID) private {
        if (_isIpfsCID) {
            string memory _uriIPFS = string(abi.encodePacked(
                "ipfs://",
                _prefix,
                "/",
                Strings.toString(_id),
                ".json"
            ));

            tokenURIs[_id] = _uriIPFS;
        }
        else {
            string memory _uriPrefixSuffix = string(abi.encodePacked(
                _prefix,
                Strings.toString(_id),
                _suffix
            ));
            tokenURIs[_id] = _uriPrefixSuffix;
        }
    }

    //Check Adjustment Requirements
    function check_A(uint _id) internal {
        require(!getCreatorLock(_id), "Locked");
        require(getCreator(_id) == msg.sender, "Not Token Creator");
        require(msg.value >= adjustFee, "Insufficient Funds");
    }

    /**
    * Set the entire Batch Prefix and Suffix from a single token.
    */
    function _setAdjustBatchPrefixSuffix(uint _id, string[2] calldata prefixSuffix) public payable {
        if (msg.sender != owner()) {
            check_A(_id);
        }
        batchPrefixSuffix[getBatch(_id)][0] = prefixSuffix[0];
        batchPrefixSuffix[getBatch(_id)][1] = prefixSuffix[1];
    }

    /**
    @dev Allows Token Creator or Admin to set the URI of token ids.
    Note: Set _isIpfsCID to true if using only IPFS CID for all the ids.
    */
    function _setAdjustURI(uint256[] calldata _ids, string[] calldata _prefix, string[] calldata _suffix, bool _isIpfsCID) public payable {
        require(_ids.length == _prefix.length && _ids.length == _suffix.length , "lengths off");
        for (uint256 i = 0; i < _ids.length; i++) {
            if (msg.sender != owner()) {
                check_A(_ids[i]);
            }
            setURI(_ids[i], _prefix[i], _suffix[i], _isIpfsCID);
        }
    }

    /**
    @dev Allows Token Creator or Admin to set the Supply Limit of token ids.
    Note: Supply set to 0 is considered Max limit.
    */
    function _setAdjustSupply(uint256[] calldata _ids, uint256[] calldata _supply) public payable {
        require(_ids.length == _supply.length, "lengths off");
        for (uint256 i = 0; i < _ids.length; i++) {
            if (msg.sender != owner()) {
                check_A(_ids[i]);
                require(_supply[i] > getSupplyLimit(_ids[i]) || _supply[i] == 0, "Supply must be greater than current supply limit.");
            }
            uint _batch = getBatch(_ids[i]);
            if (useAsBatch[_batch]) {
                supplyLimit[batchStartEndOn[_batch][0]] = _supply[i];
            }
            else {
                supplyLimit[_ids[i]] = _supply[i];
            }
        }
    }

    /**
    @dev Returns Supply Limit of token id.
    */
    function getSupplyLimit(uint256 _tokenId) public view returns(uint) {
        uint _batch = getBatch(_tokenId);
        if (useAsBatch[_batch]) {
            return supplyLimit[batchStartEndOn[_batch][0]];
        }
        else {
            return supplyLimit[_tokenId];
        }
    }

    /**
    @dev Allows Token Creator or Admin to set the mint cost of token ids.
    Note: Cost set to 0 is considered a free mint.
    */
    function _setAdjustCost(uint256[] calldata _ids, uint256[] calldata _cost) public payable {
        require(_ids.length == _cost.length, "lengths off");
        for (uint256 i = 0; i < _ids.length; i++) {
            if (msg.sender != owner()) {
                check_A(_ids[i]);
            }
            uint _batch = getBatch(_ids[i]);
            if (useAsBatch[_batch]) {
                mintCost[batchStartEndOn[_batch][0]] = _cost[i];
            }
            else {
                mintCost[_ids[i]] = _cost[i];
            }
        }
    }

    /**
    @dev Returns Mint Cost of token id.
    */
    function getCost(uint256 _tokenId) public view returns(uint) {
        uint _batch = getBatch(_tokenId);
        if (useAsBatch[_batch]) {
            return mintCost[batchStartEndOn[_batch][0]];
        }
        else {
            return mintCost[_tokenId];
        }
    }

    /**
    @dev Allows Token Creator to set the minting pause state for tokens.
    @param _ids The tokens to lock.
    @param _paused The tokens pause state.
    */
    function _setPaused(uint256[] calldata _ids, bool[] calldata _paused) public {
        require(_ids.length == _paused.length, "lengths off");
        for (uint256 i = 0; i < _ids.length; i++) {
            require(getCreator(_ids[i]) == msg.sender, "Not Token Creator");
            uint _batch = getBatch(_ids[i]);
            if (useAsBatch[_batch]) {
                paused[batchStartEndOn[_batch][0]] = _paused[i];
            }
            else {
                paused[_ids[i]] = _paused[i];
            }
        }
    }

    /**
    @dev Returns Minting Pause state of token id.
    */
    function getPaused(uint256 _tokenId) public view returns(bool) {
        uint _batch = getBatch(_tokenId);
        if (useAsBatch[_batch]) {
            return paused[batchStartEndOn[_batch][0]];
        }
        else {
            return paused[_tokenId];
        }
    }

    /**
    @dev Allows Token Creator to shut off the mintInOrder state for a token batch.
    @param _id The token of the batch to shut off mintInOrder.
    @param _confirm Type "CONFIRM" all uppercase.
    WARNING: Single use and cannot be undone.
    Note: If mintInOrder is off tokens in the batch will need to be minted by id.
    */
    function _offMintInOrder(uint256 _id, string calldata _confirm) public {
        require(getCreator(_id) == msg.sender, "Not Token Creator");
        require(keccak256(abi.encodePacked(_confirm)) == keccak256(abi.encodePacked("CONFIRM")), "Please CONFIRM");
        uint _batch = getBatch(_id);
        if (useAsBatch[_batch]) {
            require(mintInOrder[batchStartEndOn[_batch][0]], "Already Off");
            mintInOrder[batchStartEndOn[_batch][0]] = false;
        }
        else {
            revert("NA");
        }
    }

    /**
    @dev Allows Token Creator to lock tokens URI and Supply.
    @param _ids The tokens to lock.
    Note: Tokens Locked can no longer be adjusted by the Creator.
    */
    function _setCreatorLock(uint256[] calldata _ids) public {
        for (uint256 i = 0; i < _ids.length; i++) {
            require(!getCreatorLock(_ids[i]), "Already Locked");
            require(getCreator(_ids[i]) == msg.sender, "Not Token Creator");
            uint _batch = getBatch(_ids[i]);
            if (useAsBatch[_batch]) {
                creatorLock[batchStartEndOn[_batch][0]] = true;
            }
            else {
                creatorLock[_ids[i]] = true;
            }
        }
    }

    /**
    @dev Returns Token Creator Lock state of token id.
    */
    function getCreatorLock(uint256 _tokenId) public view returns(bool) {
        uint _batch = getBatch(_tokenId);
        if (useAsBatch[_batch]) {
            return creatorLock[batchStartEndOn[_batch][0]];
        }
        else {
            return creatorLock[_tokenId];
        }
    }

    /**
    @dev Returns Token Creator of token id.
    */
    function getCreator(uint256 _tokenId) public view returns(address) {
        uint _batch = getBatch(_tokenId);
        if (useAsBatch[_batch]) {
            return tokenCreator[batchStartEndOn[_batch][0]];
        }
        else {
            return tokenCreator[_tokenId];
        }
    }

    /**
    @dev Get batches created by a specific creator.
    @param _creator The address of the creator.
    @return _batches A comma-separated string containing the IDs of the batches created by the specified creator.
    Note:
    Each ID represents a batch.
    */
    function getBatchesByCreator(address _creator) public view returns(string memory) {
        string memory _batches;
        for (uint256 i = 0; i < batchCounter + 1; i++) {
            if (getCreator(batchStartEndOn[i][0]) == _creator) {
                if (keccak256(abi.encodePacked(_batches)) == keccak256(abi.encodePacked(""))) {
                    _batches = string(abi.encodePacked(
                        Strings.toString(i)
                    ));
                }
                else {
                    _batches = string(abi.encodePacked(
                        _batches,
                        ",",
                        Strings.toString(i)
                    ));
                }
            }
        }

        return _batches;
    }

    /**
    @dev Sets the new owner for a token or batch of tokens.
    @param _tokenId The id to search if single or a batch.
    @param _newOwner The address that will be the new owner.
    Requirements:
    - Wallet calling this function must be the token or batch creator.
    Note: If the _tokenId is part of a batch the _newOwner will own the entire batch.
    */
    function passOwnership(uint256 _tokenId, address _newOwner) public {
        require(getCreator(_tokenId) == msg.sender, "Not Token Creator");
        uint _batch = getBatch(_tokenId);
        if (useAsBatch[_batch]) {
            tokenCreator[batchStartEndOn[_batch][0]] = _newOwner;
        }
        else {
            tokenCreator[_tokenId] = _newOwner;
        }
        creatorRouting[_newOwner] = payable(_newOwner);
    }

    /**
    @dev Sets the address for receiving creator percentage.
    @param _percentage The percentage value of the sell price to be added as a creator cut.
    @param _creatorRouting The address that will receive the creator cut.
    Requirements:
    - Wallet calling this function must have a minimum balance (getOptionValue(3)).
    - The percentage must be (getOptionValue(253)) or less.
    */
    function _setCreatorPercentage(uint256 _percentage, address _creatorRouting) public {
        require(_creatorRouting != address(0), "Address cannot be 0");
        require(_creatorRouting != creatorRouting[msg.sender], "Address already set to that routing");
        require(msg.sender.balance >= getOptionValue(3), "Wallet must hold a Minimum Balance");
        require(_percentage >= 0 && _percentage <= getOptionValue(253), "Creator percentage must be less");
        creatorRouting[msg.sender] = payable(_creatorRouting);
        creatorPercentage[msg.sender] = _percentage;
    }

    /**
    @dev Sends the specified amount of Ether to the recipient.
    @param recipient The address of the recipient to receive the Ether.
    @param amount The amount of Ether to send in Wei.
    Note: Use https://etherscan.io/unitconverter for ETH to WEI conversions.
    */
    function sendFunds(address payable recipient, uint256 amount) public payable {
        require(msg.value >= amount, "Insufficient funds");
        recipient.transfer(amount);
    }

    /**
    @notice Retrieves an array based on the specified option and index.
    @dev This function is used to retrieve specific address arrays.
    @param option The option indicating which array to retrieve:
         - 0: Retrieve `tokenOwners` array
    @param index The index of the option for the array.
    @return The array of address values based on the specified option and index.
         If the specified option is invalid an empty array is returned.
    */
    function getAddressArray(uint8 option, uint index) public view returns (address[] memory) {
        if (option == 0) {
            //lists all token owners of an id
            return tokenOwners[index];
        }
        else {
            return new address[](0);
        } 
    }

    /**
    @notice Retrieves an array based on the specified option and index.
    @dev This function is used to retrieve specific uint arrays.
    @param option The option indicating which array to retrieve:
         - 0: Retrieve `batchStartEndOn` array by batch index
         - 1: Retrieve `batchStartEndOn` array by token id
    @param index The index of the option for the array.
    @return The array of uint values based on the specified option and index.
         If the specified option is invalid an empty array is returned.
    */
    function getUintArray(uint8 option, uint index) public view returns (uint[] memory) {
        if (option == 0 || option == 1) {
            uint[] memory result = new uint[](3);
            result[0] = batchStartEndOn[option == 0 ? index : getBatch(index)][0];
            result[1] = batchStartEndOn[option == 0 ? index : getBatch(index)][1];
            result[2] = batchStartEndOn[option == 0 ? index : getBatch(index)][2];
            return result;
        }
        else {
            return new uint[](0);
        }
    }

    /**
    @dev Admin can set the strike amount for an address.
    Note: 3 strikes and an account can no longer create tokens. Set to 100 for banned.
    */
    function setStrike(address account, uint _x) external onlyOwner {
        strikes[account] = _x;
    }

    /**
    @dev Admin can set the withdraw to address.
    */
    function adminSetVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /**
    @dev Returns vault address.
    */
    function getVault() external view returns (address) {
        return vault;
    }

    /**
    @dev Admin can pull withdraw funds.
    */
    function withdraw() public onlyOwner {
        uint256 payout = address(this).balance;
        (bool success, ) = payable(vault).call{ value: payout } ("");
        require(success, "Failed to send funds to admin");
    }

    /**
    * @dev Hook that is called for any token transfer. 
    * This includes minting and burning, as well as batched variants.
    */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory amounts) 
        internal virtual override {
        // ... before action here ...
        require(strikes[from] < 100 || strikes[to] < 100, "Restricted Address");

        super._update(from, to, ids, amounts); // Call parent hook

        // ... after action here ...
        for (uint256 i = 0; i < ids.length; i++) {
            if (totalSupply(ids[i]) == 1) {
                if (tokenOwners[ids[i]].length == 0) {
                    tokenOwners[ids[i]].push(to);
                } else {
                    tokenOwners[ids[i]][0] = to;
                }
            } else {
                if (totalSupply(ids[i]) == tokenOwners[ids[i]].length) {
                    for (uint256 j = 0; j < amounts[i]; j++) {
                        uint256 searched;
                        uint256 startAt = searched;
                        for (uint256 k = startAt; k < tokenOwners[ids[i]].length; k++) {
                            searched++;
                            if (tokenOwners[ids[i]][k] == from) {
                                tokenOwners[ids[i]][k] = to;
                                break;
                            }
                        }
                    }
                } else {
                    for (uint256 l = 0; l < amounts[i]; l++) {
                        tokenOwners[ids[i]].push(to);
                    }
                }
            }
        }   
    }
}