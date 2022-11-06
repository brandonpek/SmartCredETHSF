
// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
/**
* @title CreditCheck
* @dev Implements a basic credit check system.
*/

import "https://github.com/UMAprotocol/protocol/blob/master/packages/core/contracts/oracle/interfaces/OptimisticOracleV2Interface.sol";

interface IMidpoint {
  function callMidpoint(uint64 midpointId, bytes calldata _data) external returns(uint256 requestId);
}

contract SmartCredit {
   enum TransactionStatus{ LOAN, DEFAULTED, PAID, INQUIRY }

   struct Transaction {
       address lender;
       address borrower;
       uint amount;
       uint timestamp;
       TransactionStatus status;
   }

   struct Borrower {
       Transaction[] transactionHistory;
       int historyInMonths;
       int numMonthsSinceLastDefault;
       int outstandingDebt;
       int numCreditSources;
       int numRecentInquiries;
   }

   // naive MVP with one lender
   address public lender;

   mapping (address => Borrower) private borrowers;

   // transaction
   event ViewTransactionHistory(Transaction[] transactionHistory);

   uint256 ASCII_OFFSET = 48;

   // midpoint data
   address constant startpointAddress = 0x9BEa2A4C2d84334287D60D6c36Ab45CB453821eB;
   address constant whitelistedCallbackAddress = 0xC0FFEE4a3A2D488B138d090b8112875B90b5e6D9;

   // Midpoint ID
   uint64 constant midpointID = 451;

   // other bank data
   uint most_recent_interest_rate_percent_times_100 = 85;

   // future sentiment data
   uint sentiment_factor_times_100 = 100;

   /**
   * @dev Create a new credit check system with one lender
   */
   constructor() {
       lender = msg.sender;
   }

   function addBorrower(address wallet, int historyInMonths, int numMonthsSinceLastDefault, int outstandingDebt,
                        int numCreditSources, int numRecentInquiries) public {
       require(
           borrowers[msg.sender].historyInMonths != 0,
           "The borrower is already on this blockchain."
       );
       borrowers[wallet].historyInMonths = historyInMonths;
       borrowers[wallet].numMonthsSinceLastDefault = numMonthsSinceLastDefault;
       borrowers[wallet].outstandingDebt = outstandingDebt;
       borrowers[wallet].numCreditSources = numCreditSources;
       borrowers[wallet].numRecentInquiries = numRecentInquiries;
   }

   /**
   * @dev Add a transaction for a borrower. May only be called by lender.
   */
   function addTransaction(address wallet_address, Transaction calldata transaction) public {
       require(
           msg.sender == lender,
           "Only the lender can add transactions for now."
       );
       require(
           borrowers[wallet_address].historyInMonths != 0,
           "The borrower has not yet consented to be on this blockchain."
       );
       borrowers[wallet_address].transactionHistory.push(transaction);
   }

   function getCreditScore(address wallet) public view
             returns (uint creditScore_) {
   return generateCreditScore(borrowers[wallet]);
   }

   function getTransactionHistory(address wallet) public
     returns (Transaction[] memory transactionHistory) {
       emit ViewTransactionHistory(borrowers[wallet].transactionHistory);
       return borrowers[wallet].transactionHistory;
   }

   function getMyInterestRateTimesHundred() public view
                          returns (uint creditScore_) {
       return getInterestRateTimesHundred(msg.sender);
   }

   function getInterestRateTimesHundred(address wallet) public view
                                      returns (uint creditScore_) {
       uint credit_score = getCreditScore(wallet);
       return most_recent_interest_rate_percent_times_100 * 700 / credit_score * sentiment_factor_times_100 / 100;
   }

   function getMostRecentFedInterestRate() public view
                      returns (uint fedInterestRate) {
       return most_recent_interest_rate_percent_times_100;
   }

   // payment history 35% ~300
   // amounts owed 30% ~250
   // length of history 15% ~130
   // credit mix 10% ~85
   // new credit 10% ~85
   function generateCreditScore(Borrower storage borrower) internal view
                                           returns (uint creditScore_) {
       uint score = 0;

       int historyInMonths = borrower.historyInMonths;
       int numMonthsSinceLastDefault = borrower.numMonthsSinceLastDefault;
       int outstandingDebt = borrower.outstandingDebt;
       int numCreditSources = borrower.numCreditSources;
       int numRecentInquiries = borrower.numRecentInquiries;

       // length of history 15% ~130
       if (historyInMonths > 48) {
           score += 130;
       } else if (historyInMonths > 42) {
           score += 110;
       } else if (historyInMonths > 36) {
           score += 90;
       } else if (historyInMonths > 30) {
           score += 70;
       } else if (historyInMonths > 24) {
           score += 50;
       } else if (historyInMonths > 18) {
           score += 30;
       } else if (historyInMonths > 12) {
           score += 10;
       }

       // payment history 35% ~300
       if (numMonthsSinceLastDefault < 0 || numMonthsSinceLastDefault > 24) {
           score += 300;
       } else if (numMonthsSinceLastDefault > 18) {
           score += 250;
       } else if (numMonthsSinceLastDefault > 12) {
           score += 200;
       } else if (numMonthsSinceLastDefault > 6) {
           score += 150;
       } else if (numMonthsSinceLastDefault > 3) {
           score += 100;
       } else if (numMonthsSinceLastDefault > 1) {
           score += 50;
       }

       // amounts owed 30% ~250
       if (outstandingDebt < 100) {
           score += 250;
       } else if (outstandingDebt < 300) {
           score += 2000;
       } else if (outstandingDebt < 600) {
           score += 150;
       } else if (outstandingDebt < 900) {
           score += 100;
       } else if (outstandingDebt < 1100) {
           score += 80;
       } else if (outstandingDebt < 1500) {
           score += 60;
       }

       // credit mix 10% ~85
       if (numCreditSources > 5) {
           score += 85;
       } else if (numCreditSources > 4) {
           score += 65;
       } else if (numCreditSources > 3) {
           score += 45;
       } else if (numCreditSources > 2) {
           score += 25;
       } else if (numCreditSources > 1) {
           score += 10;
       }

       // new credit 10% ~85
       // number of inquiries in last 6 months
       if (numRecentInquiries > 4) {
           score += 20;
       } else if (numRecentInquiries > 3) {
           score += 40;
       } else if (numRecentInquiries > 2) {
           score += 60;
       } else if (numRecentInquiries > 1) {
           score += 70;
       } else {
           score += 85;
       }

       return score;
   }

   /*
   * This function makes a call to a midpoint with on-chain variables specified as function inputs.
   *
   * Note that this is a public function and will allow any address or contract to call midpoint 451.
   * The contract whitelist permits this entire contract to call your midpoint; calls to 'callMidpoint'
   * must be additionally restricted to intended callers.
   * Any call to 'callMidpoint' from a whitelisted contract will make a call to the midpoint;
   * there may be multiple places in this contract that call the midpoint or multiple midpoints called by the same contract.
   */
   function callMidpoint(int32 qry_time) public {
       // Argument String
       bytes memory args = abi.encodePacked(qry_time);

       // Call Your Midpoint
       IMidpoint(startpointAddress).callMidpoint(midpointID, args);

       // For Demonstration Purposes Only
       // emit RequestMade(requestId, qry_time);
   }

   /*
   * This function is the callback target specified in the prebuilt function in the midpoint response workflow.
   * The callback does not need to be defined in the same contract as the request.
   */
   function callback(uint256, uint64 _midpointId, string memory interest_rate) public {
       // Only allow the verified callback address to submit information for your midpoint.
       require(tx.origin == whitelistedCallbackAddress, "Invalid callback address");
       require(midpointID == _midpointId, "Invalid Midpoint ID");

       // Your callback function here
       bytes memory b = bytes(interest_rate);
       most_recent_interest_rate_percent_times_100 = uint(uint8(b[0]) - ASCII_OFFSET) * 100 + uint(uint8(b[2]) - ASCII_OFFSET) * 10 + uint(uint8(b[3]) - ASCII_OFFSET);
       // For Demonstration Purposes Only
       // emit ResponseReceived(_requestId, interest_rate);
   }

   // UMA OO Query
   // Create an Optimistic oracle instance at the deployed address on Görli.
   OptimisticOracleV2Interface oo = OptimisticOracleV2Interface(0xA5B9d8a0B0Fa04Ba71BDD68069661ED5C0848884);

   // Use the yes no idetifier to ask arbitary questions, such as the weather on a particular day.
   bytes32 identifier = bytes32("YES_OR_NO_QUERY");

   // Post the question in ancillary data. Note that this is a simplified form of ancillry data to work as an example. A real
   // world prodition market would use something slightly more complex and would need to conform to a more robust structure.
   bytes ancillaryData = bytes("Q:Is the unemployment rate higher among youths than it was one week ago?");

   uint256 requestTime = 0; // Store the request time so we can re-use it later.

   // Submit a data request to the Optimistic oracle.
   function requestData() public {
       requestTime = block.timestamp; // Set the request time to the current block time.
       IERC20 bondCurrency = IERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6); // Use Görli WETH as the bond currency.
       uint256 reward = 0; // Set the reward to 0 (so we dont have to fund it from this contract).

       // Now, make the price request to the Optimistic oracle and set the liveness to 30 so it will settle quickly.
       oo.requestPrice(identifier, requestTime, ancillaryData, bondCurrency, reward);
       oo.setCustomLiveness(identifier, requestTime, ancillaryData, 30);
   }

   // Settle the request once it's gone through the liveness period of 30 seconds. This acts the finalize the voted on price.
   // In a real world use of the Optimistic Oracle this should be longer to give time to disputers to catch bat price proposals.
   function settleRequest() public {
       oo.settle(address(this), identifier, requestTime, ancillaryData);
   }

   // Fetch the resolved price from the Optimistic Oracle that was settled.
   function getSettledData() public view returns (int256) {
       return oo.getRequest(address(this), identifier, requestTime, ancillaryData).resolvedPrice;
   }

   function updateFutureEconomicSentiment() public returns (uint256) {
       settleRequest();
       int256 x = getSettledData();
       if (x != 0) sentiment_factor_times_100 = 90;
       else sentiment_factor_times_100 = 110;
       return sentiment_factor_times_100;
   }

   function getSentimentFactorTimes100() public view
       returns (uint256) {
       return sentiment_factor_times_100;
   }
}
