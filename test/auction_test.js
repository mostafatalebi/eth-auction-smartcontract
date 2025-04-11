const { expect, assert } = require("chai");
const hre = require("hardhat");
const { time, helpers } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Auction", function () {
    const timestamp = Date.now();
    const singleDayTs = 60 * 60 * 24;
    let auctionFactory, auctionContract;
    let unauthorized, owner, bidder1, bidder2;

    // setup the test
    beforeEach(async function () {
      [owner, unauthorized, bidder1, bidder2] = await hre.ethers.getSigners();

      auctionFactory = await hre.ethers.getContractFactory("Auction");
      auctionContract = await auctionFactory.deploy(owner);
    });

    // check if the owner is set correctly

    it("OK Must set the owner address correctly", async function(){
      expect(await auctionContract.owner()).to.equal(owner.address);
    })
    

    it("FAIL Must error on authorizing someone with a non-owner address", async function() {
      try {
        // the following line should throw an exception, else
        // the test should fail
        var result = await auctionContract.connect(bidder1).authorize(bidder1)
        assert.fail("FAIL! called authorize() with a non-owner address and encountered no error");
      } catch(e) {
        expect(e).to.not.empty;        
        expect(e.message).to.contain("FORBIDDEN");
      }      
    });

    it("OK Must be OK to add a new buyer with a owner address", async function(){
        await auctionContract.connect(owner).authorize(bidder1);
        var result = await auctionContract.allowedBuyers(bidder1.address);
        expect(await auctionContract.allowedBuyers(bidder1.address)).to.true;
    });

    it("FAIL Must error on setting auction timing with a non-owner address", async function(){
        try {
          await auctionContract.connect(bidder1).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2);
          assert.fail("FAIL! called setAuctionTiming() with a non-owner address and encountered no error");
        } catch(e) {
          expect(e).to.not.empty;
          expect(e.message).to.contain("FORBIDDEN");
        }
    });

    it("OK Must be OK and set proper timing for the auction", async function(){
      await auctionContract.connect(owner).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2); 
  });


    it("FAIL Must error on adding a product with a non-owner address", async function(){
        await auctionContract.connect(owner).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2);
        try {          
          await auctionContract.connect(bidder1).product(1, 1000, false);
          assert.fail("FAIL! called product() with a non-owner address and encountered no error");
        } catch(e) {
          expect(e).to.not.empty;
          expect(e.message).to.contain("FORBIDDEN");
          console.log(e.message);
        }
    });

    it("FAIL Must error on adding a product, zero product code", async function(){
      await auctionContract.connect(owner).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2);
      try {          
        await auctionContract.connect(owner).product(0, 1000, false);
        assert.fail("FAIL! called product() with a productCode < 1 and encountered no error");
      } catch(e) {
        expect(e).to.not.empty;
        expect(e.message).to.contain("BAD_PCODE");
        console.log(e.message);
      }
   });


    it("FAIL Must error on removing a product with a non-owner address", async function(){
      await auctionContract.connect(owner).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2);
      try {          
        await auctionContract.connect(bidder1).product(1, 1000, true);
        assert.fail("FAIL! called product() with a non-owner address and encountered no error");
      } catch(e) {
        expect(e).to.not.empty;
        expect(e.message).to.contain("FORBIDDEN");
        console.log(e.message);
      }
  });

    it("OK Must be OK on adding a product", async function(){
      await auctionContract.connect(owner).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2);
      await auctionContract.connect(owner).product(1, 1000, false);
      // get the product count
      expect(await auctionContract.liveProductsCount()).to.equal(1);
      // get the first index
      var productKey = await auctionContract.productsKeys(0);
      expect(Number(productKey)).to.equal(1);
      // get product by productCode
      var createdProduct = await auctionContract.productsMap(1);
      assert.deepEqual(createdProduct, [1n, 1000n, true]);
  });

  it("OK Must be OK removing a product", async function(){
    await auctionContract.connect(owner).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2);
    await auctionContract.connect(owner).product(1, 1000, false);
    await auctionContract.connect(owner).product(1, 0, true);
    // get the product count
    expect(await auctionContract.liveProductsCount()).to.equal(0);
    // get the first index
    var productKey = await auctionContract.productsKeys(0);
    expect(Number(productKey)).to.equal(0);
    // get product by productCode
    var createdProduct = await auctionContract.productsMap(1);
    assert.deepEqual(createdProduct, [0n, 0n, false]);
  });

  it("FAIL must error on bidding with a non-authorized user", async function(){
    const exampleProductCode = 1001
    await auctionContract.connect(owner).authorize(bidder1)
    await auctionContract.connect(owner).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2);
    await auctionContract.connect(owner).product(1, 1000, false);

    try {
      // note: we have authorized bidder1, but we are trying to bid() with bidder2
      await auctionContract.connect(bidder2).bid();
    } catch(e) {
      try {
        var currentBid = await auctionContract.getCurrentBids(1n, bidder1.address); // must not exists
      } catch (ee) {
        expect(ee.message).to.contain("BID_NOT_FOUND");
      }
    }
  });

  it("OK bid with both bidder users, and check their current and main highestBid. "+
    "Then move blockchain to past the endTime of the auction, and retry to assert an exception", async function(){
    var bidAmount = hre.ethers.parseEther("1.0");

    await auctionContract.connect(owner).authorize(bidder1)
    await auctionContract.connect(owner).setAuctionTiming(timestamp+singleDayTs, timestamp+singleDayTs*2);
    await auctionContract.connect(owner).product(1, 1000, false);
    await time.increaseTo(timestamp+singleDayTs+10); // make blockchain to move to this timestamp
    await auctionContract.connect(bidder1).bid(1, { value: bidAmount });
    var currentBid = await auctionContract.getCurrentBids(1, bidder1.address); 
    expect(currentBid).to.equal(bidAmount);
    var productKey = await auctionContract.productsKeys(0);
    expect(Number(productKey)).to.equal(1n);
    var createdProduct = await auctionContract.productsMap(1);
    assert.deepEqual(createdProduct, [1n, 1000n, true]);
    var highestBid = await auctionContract.getHighestBid(1); 
    expect(highestBid).to.equal(bidAmount);
    
    // make another bid, lowe than prevoious one by another bidder
    await auctionContract.connect(owner).authorize(bidder2)
    await auctionContract.connect(bidder2).bid(1, { value: hre.ethers.parseEther("0.99") });
    var currentBid = await auctionContract.getCurrentBids(1, bidder2.address); 
    expect(currentBid).to.equal(hre.ethers.parseEther("0.99"));
    highestBid = await auctionContract.getHighestBid(1); 
    expect(highestBid).to.equal(bidAmount);
    
    // now do a second bid with second user (third in total) and the
    // currentBid for the bidder2 as well as the highestBid must be changed
    await auctionContract.connect(bidder2).bid(1, { value: hre.ethers.parseEther("2.0")} );
    currentBid = await auctionContract.getCurrentBids(1, bidder2.address); 
    expect(currentBid).to.equal(hre.ethers.parseEther("2.0"));
    highestBid = await auctionContract.getHighestBid(1); 
    expect(highestBid).to.equal(hre.ethers.parseEther("2.0"));    
    
    // now move the blockchain to past the auction's end
    await time.increaseTo(timestamp+singleDayTs*2+10); 
    
    try {
      await auctionContract.connect(bidder2).bid(1, { value: hre.ethers.parseEther("2.0") });
    } catch(e) {
      expect(e.message).to.contain("ALREADY_CLOSED");
    }

    var winningBidsJson = await auctionContract.connect(owner).getWinners();
    expect(winningBidsJson).to.not.empty;

    var winningBids = JSON.parse(winningBidsJson);
    expect(Array.isArray(winningBids)).to.be.true;
    expect(winningBids.length).to.equal(1);

    if(winningBids.length == 1) {
      expect(winningBids[0].productCode).to.equal(1);
      expect(BigInt(winningBids[0].amount)).to.equal(hre.ethers.parseEther("2.0"));
      expect(winningBids[0].winner).to.equal(bidder2.address);
    }
    
  });

});

