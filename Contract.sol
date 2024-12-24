// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract P2PShipping is Ownable, ReentrancyGuard {
    // Structs
    struct Package {
        address sender;
        address carrier;
        string pickupLocation;
        string deliveryLocation;
        uint256 reward;
        uint256 deposit;
        uint256 deadline;
        PackageStatus status;
        bool isDisputed;
    }

    struct Carrier {
        bool isRegistered;
        uint256 successfulDeliveries;
        uint256 rating;
        uint256 totalRatings;
    }

    // Enums
    enum PackageStatus {
        Created,
        Accepted,
        InTransit,
        Delivered,
        Completed,
        Cancelled
    }

    // State variables
    mapping(uint256 => Package) public packages;
    mapping(address => Carrier) public carriers;
    uint256 public packageCount;
    uint256 public platformFee = 2; // 2% platform fee
    
    // Events
    event PackageCreated(uint256 indexed packageId, address indexed sender, string pickupLocation, string deliveryLocation);
    event PackageAccepted(uint256 indexed packageId, address indexed carrier);
    event PackageInTransit(uint256 indexed packageId);
    event PackageDelivered(uint256 indexed packageId);
    event PackageCompleted(uint256 indexed packageId);
    event PackageCancelled(uint256 indexed packageId);
    event DisputeRaised(uint256 indexed packageId);
    event DisputeResolved(uint256 indexed packageId, address winner);
    event CarrierRegistered(address indexed carrier);
    event CarrierRated(address indexed carrier, uint256 rating);

    // Modifiers
    modifier onlyRegisteredCarrier() {
        require(carriers[msg.sender].isRegistered, "Not a registered carrier");
        _;
    }

    modifier onlyPackageSender(uint256 _packageId) {
        require(packages[_packageId].sender == msg.sender, "Not the package sender");
        _;
    }

    modifier onlyPackageCarrier(uint256 _packageId) {
        require(packages[_packageId].carrier == msg.sender, "Not the package carrier");
        _;
    }

    // Constructor
    constructor(address initialOwner) Ownable(initialOwner) {}

    // Functions
    function registerCarrier() external {
        require(!carriers[msg.sender].isRegistered, "Already registered");
        carriers[msg.sender] = Carrier(true, 0, 0, 0);
        emit CarrierRegistered(msg.sender);
    }

    function createPackage(
        string memory _pickupLocation,
        string memory _deliveryLocation,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Reward must be greater than 0");
        require(_deadline > block.timestamp, "Invalid deadline");

        uint256 deposit = msg.value * 10 / 100; // 10% deposit
        uint256 reward = msg.value - deposit;

        packages[packageCount] = Package({
            sender: msg.sender,
            carrier: address(0),
            pickupLocation: _pickupLocation,
            deliveryLocation: _deliveryLocation,
            reward: reward,
            deposit: deposit,
            deadline: _deadline,
            status: PackageStatus.Created,
            isDisputed: false
        });

        emit PackageCreated(packageCount, msg.sender, _pickupLocation, _deliveryLocation);
        packageCount++;
    }

    function acceptPackage(uint256 _packageId) external onlyRegisteredCarrier nonReentrant {
        Package storage package = packages[_packageId];
        require(package.status == PackageStatus.Created, "Package not available");
        require(package.deadline > block.timestamp, "Package expired");

        package.carrier = msg.sender;
        package.status = PackageStatus.Accepted;
        
        emit PackageAccepted(_packageId, msg.sender);
    }

    function startDelivery(uint256 _packageId) external onlyPackageCarrier(_packageId) {
        Package storage package = packages[_packageId];
        require(package.status == PackageStatus.Accepted, "Package not accepted");
        
        package.status = PackageStatus.InTransit;
        emit PackageInTransit(_packageId);
    }

    function confirmDelivery(uint256 _packageId) external onlyPackageCarrier(_packageId) {
        Package storage package = packages[_packageId];
        require(package.status == PackageStatus.InTransit, "Package not in transit");
        
        package.status = PackageStatus.Delivered;
        emit PackageDelivered(_packageId);
    }

    function completeDelivery(uint256 _packageId, uint256 _rating) external onlyPackageSender(_packageId) nonReentrant {
        Package storage package = packages[_packageId];
        require(package.status == PackageStatus.Delivered, "Package not delivered");
        require(_rating >= 1 && _rating <= 5, "Invalid rating");

        // Update carrier rating
        Carrier storage carrier = carriers[package.carrier];
        carrier.rating = ((carrier.rating * carrier.totalRatings) + _rating) / (carrier.totalRatings + 1);
        carrier.totalRatings++;
        carrier.successfulDeliveries++;

        // Calculate and transfer payments
        uint256 platformFeeAmount = (package.reward * platformFee) / 100;
        uint256 carrierPayment = package.reward - platformFeeAmount;

        // Transfer reward and deposit to carrier
        payable(package.carrier).transfer(carrierPayment + package.deposit);
        payable(owner()).transfer(platformFeeAmount);

        package.status = PackageStatus.Completed;
        emit PackageCompleted(_packageId);
        emit CarrierRated(package.carrier, _rating);
    }

    function cancelPackage(uint256 _packageId) external onlyPackageSender(_packageId) nonReentrant {
        Package storage package = packages[_packageId];
        require(package.status == PackageStatus.Created, "Cannot cancel package");

        package.status = PackageStatus.Cancelled;
        payable(msg.sender).transfer(package.reward + package.deposit);
        
        emit PackageCancelled(_packageId);
    }

    function raiseDispute(uint256 _packageId) external {
        Package storage package = packages[_packageId];
        require(msg.sender == package.sender || msg.sender == package.carrier, "Not authorized");
        require(!package.isDisputed, "Dispute already raised");
        require(package.status == PackageStatus.InTransit || package.status == PackageStatus.Delivered, "Invalid status for dispute");

        package.isDisputed = true;
        emit DisputeRaised(_packageId);
    }

    function resolveDispute(uint256 _packageId, address _winner) external onlyOwner nonReentrant {
        Package storage package = packages[_packageId];
        require(package.isDisputed, "No dispute raised");
        require(_winner == package.sender || _winner == package.carrier, "Invalid winner address");

        if (_winner == package.carrier) {
            // Transfer full amount to carrier
            payable(package.carrier).transfer(package.reward + package.deposit);
        } else {
            // Return funds to sender
            payable(package.sender).transfer(package.reward + package.deposit);
        }

        package.status = PackageStatus.Completed;
        package.isDisputed = false;
        emit DisputeResolved(_packageId, _winner);
    }

    // View functions
    function getPackage(uint256 _packageId) external view returns (Package memory) {
        return packages[_packageId];
    }

    function getCarrier(address _carrier) external view returns (Carrier memory) {
        return carriers[_carrier];
    }

    function setPlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 5, "Fee too high"); // Max 5%
        platformFee = _newFee;
    }
}