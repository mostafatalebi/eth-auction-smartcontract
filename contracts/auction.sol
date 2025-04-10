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
    // than this amount. The amount is in gwei
    uint private minimumAllowedBid = 0;

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

    constructor(){
        owner = msg.sender;
        minimumDurationOfAuction = 30 * 60; // 30 minutes

    }


    function getCurrentBids(uint productCode, address bidderAddress) public view returns (uint) {
        require(msg.sender == owner, "FORBIDDEN");
        require(currentBids[productCode][bidderAddress].put == true, "BID_NOT_FOUND");
        return currentBids[productCode][bidderAddress].amount;
    }


    function getHighestBid(uint productCode) public view returns (uint) {
        require(msg.sender == owner, "FORBIDDEN");
        require(winningBids[productCode].put == true, "BID_NOT_FOUND");
        return winningBids[productCode].amount;
    }


    function setAuctionTiming(uint start, uint end) external {
        require(msg.sender == owner, "FORBIDDEN");
        require(start < end && end - start >= minimumDurationOfAuction, "DURATION_TOO_SHORT");
        require(block.timestamp < start, "BAD_START_TIME");

        auctionStartTime = start;
        auctionEndTime = end;
    }

    // this function is used to authorize an entity to
    // be able to participate in the auction
    function authorize(address toBeBuyer) external {
        require(
            owner == msg.sender, 
        "FORBIDDEN");

        require(
            allowedBuyers[toBeBuyer] == false,
            "DUPLICATE"
        );


        allowedBuyers[toBeBuyer] = true;
    }

    function unauthorize(address toBeBuyer) external {
        require(
            toBeBuyer == msg.sender, 
        "FORBIDDEN");

        require(
            allowedBuyers[toBeBuyer] == true,
            "NOT_FOUND"
        );
        delete allowedBuyers[toBeBuyer];
    }

    function bid(uint productCode, uint amount) external returns (bool) {
        require(allowedBuyers[msg.sender] == true, "FORBIDDEN");
        require(block.timestamp > auctionStartTime, "NOT_STARTED");
        require(block.timestamp < auctionEndTime, "ALREADY_CLOSED");
        require(productsMap[productCode].exists == true, "PRODUCT_NOT_FOUND");
        require(amount >= minimumAllowedBid, "BID_TOO_LOW");

        if(currentBids[productCode][msg.sender].put == true){
            require(currentBids[productCode][msg.sender].amount < amount, "BID_LOWER_THAN_PREVIOUS");
            currentBids[productCode][msg.sender].amount = amount;
        } else {
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
    }

    // adds/removes a product to biddable products. It allows adding/removing product only before
    // an acution starts
    // isRemove if true, removes the product
    function product(uint productCode, uint startingBidPrice, bool isRemove) external {
        require(msg.sender == owner, "FORBIDDEN");
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
    function getWinners() public view returns(string memory) {
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
}