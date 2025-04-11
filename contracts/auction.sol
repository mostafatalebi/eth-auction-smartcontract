pragma solidity ^0.8.26;
// SPDX-License-Identifier: GPL-1.0-or-later
import "solidity-json-writer/contracts/JsonWriter.sol";


struct Bid {
        address buyer;
        uint productCode; // name of the item being bid
        uint amount;
        bool put;
}


contract Auction {

    using JsonWriter for JsonWriter.Json;


    
    address public owner;
    
    // you cannot add more than this amount of
    // products for bidding
    uint private maxProductsCount = 3;

    // no bid for no product can be lower 
    // than this amount. 
    uint private minimumAllowedBid = 1000000 gwei;

    mapping (address => bool) public allowedBuyers;

    // unix timestamp of auction start time
    uint auctionStartTime;
    
    // unix timestamp of auction end time
    uint auctionEndTime;

    uint private minimumDurationOfAuction;    

    struct Product {
        uint code;
        uint startingPrice;
        bool exists;
    }

    // any call to addProduct() will add a new product
    // to this array. Only maxProductsCount amount is allowed
    mapping (uint => Product) public productsMap;
    
    // this is used to keep track of currently live products
    // + and - with each addition/removal
    uint public liveProductsCount = 0;

    uint[] public productsKeys;


    // currently put bids, a map of productCode => buyerAddress => Bid
    mapping (uint => mapping (address => Bid)) public currentBids;

    // the winners for each item
    mapping (uint => Bid) winningBids;


    // any eth transfered through bid() function
    // will be kept here. This includes all
    // previous bids upon which the user has
    // put newer (higher) bids. User needs to 
    // call withdraw() to get the unused eth of his/her
    mapping (address => uint) balances;

    // keeps track of deposited eth by bidders.
    // depositing happens when a bid is placed using
    // bid() function (there is no direct way to deposit unless
    // for a specific product).
    // if a bidder calls withdraw(), only the difference
    // between this deposit and his/her balance in 
    // balances[] storage would be transfered. The amount
    // here will be locked until the end of auction for
    // corresponding bids. After the auction ends, the user's
    // won bids will be subtracted from deposit and the rest will
    // be available for withdrawing (withdraw() must be called by user)
    mapping (address => uint)  biddersDeposit;

    modifier onlyOwner {
        require(msg.sender == owner, "FORBIDDEN");
        _;
    }

    modifier authorizedBidder {
        require(allowedBuyers[msg.sender] == true, "FORBIDDEN");
        _;
    }

    constructor(){
        owner = msg.sender;
        minimumDurationOfAuction = 30 * 60; // 30 minutes
        allowedBuyers[owner] = true;
    }


    function getCurrentBids(uint productCode, address bidderAddress) public view onlyOwner returns (uint) {
        require(currentBids[productCode][bidderAddress].put == true, "BID_NOT_FOUND");
        return currentBids[productCode][bidderAddress].amount;
    }


    function getHighestBid(uint productCode) public view onlyOwner returns (uint) {
        require(winningBids[productCode].put == true, "BID_NOT_FOUND");
        return winningBids[productCode].amount;
    }


    function setAuctionTiming(uint start, uint end) external onlyOwner {
        require(start < end && end - start >= minimumDurationOfAuction, "DURATION_TOO_SHORT");
        require(block.timestamp < start, "BAD_START_TIME");

        auctionStartTime = start;
        auctionEndTime = end;
    }

    // this function is used to authorize an entity to
    // be able to participate in the auction
    function authorize(address toBeBuyer) external onlyOwner {
        require(
            allowedBuyers[toBeBuyer] == false,
            "DUPLICATE"
        );

        allowedBuyers[toBeBuyer] = true;
    }

    function unauthorize(address toBeBuyer) external onlyOwner {
        require(
            allowedBuyers[toBeBuyer] == true,
            "NOT_FOUND"
        );
        delete allowedBuyers[toBeBuyer];
    }

    // bidding doesn't handle any sort of refund or withdrawal. If the bidder
    // has attempted several bids, for each individual bid, the amount of ether
    // should be sent along this function call. To withdraw his/her fund, the bidder
    // needs to call withdraw function.
    function bid(uint productCode) external payable authorizedBidder {
        require(block.timestamp > auctionStartTime, "NOT_STARTED");
        require(block.timestamp < auctionEndTime, "ALREADY_CLOSED");
        require(productsMap[productCode].exists == true, "PRODUCT_NOT_FOUND");
        uint amount = msg.value;
        require(amount >= minimumAllowedBid, "BID_TOO_LOW");

        if(currentBids[productCode][msg.sender].put == true){
            require(currentBids[productCode][msg.sender].amount < amount, "BID_LOWER_THAN_PREVIOUS");
             biddersDeposit[msg.sender] -= currentBids[productCode][msg.sender].amount;
             biddersDeposit[msg.sender] += amount;
            currentBids[productCode][msg.sender].amount = amount;
        } else {
             biddersDeposit[msg.sender] += amount;
            currentBids[productCode][msg.sender] = Bid({ 
                buyer: msg.sender,
                productCode: productCode,
                amount: amount,
            put: true}); 
        }

        if(winningBids[productCode].amount < amount) {
            winningBids[productCode] = Bid({ 
                buyer: msg.sender,
                productCode: productCode,
                amount: amount,
                put: true});
        }

        balances[msg.sender] += amount;
    }


    function withdraw() external authorizedBidder {
        require(balances[msg.sender] > 0, "OUT_OF_BALANCE");
        uint spending =  biddersDeposit[msg.sender];
        uint remainder = balances[msg.sender] - spending;
        balances[msg.sender] -= remainder;
        require(payable(msg.sender).send(remainder) == true, "TRANSFER_FAILED");
    }

    // adds/removes a product form the auction. It allows adding/removing product only before
    // an acution starts
    // isRemove if true, removes the product
    function product(uint productCode, uint startingBidPrice, bool isRemove) external onlyOwner {
        if(isRemove == false) {
            addProduct(productCode, startingBidPrice);
        } else {
            removeProduct(productCode);
        }
    }

    function addProduct(uint productCode, uint startingBidPrice) internal {
            require(block.timestamp < auctionStartTime, "BID_ALREADY_STARTED");
            require(productsKeys.length < maxProductsCount, "TOO_MANY_PRODUCTS");
            require(productCode > 0, "BAD_PCODE");
            if(productsMap[productCode].exists == true){
                productsMap[productCode].startingPrice = startingBidPrice;
            } else {
                productsMap[productCode] = Product({code: productCode, startingPrice: startingBidPrice, exists: true});
                productsKeys.push(productCode);
                liveProductsCount++;
            }
    }

    function removeProduct(uint productCode) internal {
            require(block.timestamp < auctionStartTime, "BID_ALREADY_STARTED");
            require(productsMap[productCode].exists == true, "NOT_FOUND");
            require(productCode > 0, "ZERO_PCODE");
            if(productsKeys.length == 1) {
                productsKeys[0] = 0;
            } else {
                for(uint i = 0; i < productsKeys.length; i++) {
                if(productsKeys[i] != productCode) {
                    uint lastElement = productsKeys[productsKeys.length-1];
                    productsKeys[productsKeys.length-1] = 0;
                    productsKeys[i] = lastElement;
                    productsKeys.pop();
                    break;
                }
            }
            }
            
            delete productsMap[productCode];
            liveProductsCount--;
    }

    // returns list of winners
    function getWinners() public view authorizedBidder returns(string memory)  {
        require(block.timestamp > auctionEndTime, "winners are announced after auction ends");
        JsonWriter.Json memory writer;
        writer = writer.writeStartArray();
        for(uint i = 0; i < productsKeys.length; i++) {
            if(winningBids[productsKeys[i]].put == true) {
                writer = writer.writeStartObject();
                writer = writer.writeUintProperty("productCode", winningBids[productsKeys[i]].productCode);
                writer = writer.writeUintProperty("amount", winningBids[productsKeys[i]].amount);
                writer = writer.writeAddressProperty("winner", winningBids[productsKeys[i]].buyer);
                writer = writer.writeEndObject();
            }            
        }
        writer = writer.writeEndArray();

        return writer.value;
    }

    receive() external payable {}
}