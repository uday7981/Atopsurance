// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

// import "./Oracle.sol";

interface Oracle{
    function getPrecipitation(string memory) external view returns(uint);
}

contract FarmInsure {
    //for BaseMin to BaseMax -> BasePayout% . for > Max -> MaxPayout%
    uint8 constant floodBaseMin = 10;
    uint8 constant floodBaseMax = 15;
    uint8 constant floodBasePayout = 50;  //50% of coverage
    uint8 constant floodMaxPayout = 100;  //100% of coverage

    //for BaseMin to BaseMax -> BasePayout% . for < Min -> MaxPayout%
    uint8 constant droughtBaseMin = 2;
    uint8 constant droughtBaseMax = 5;
    uint8 constant droughtBasePayout = 50;  //50% of coverage
    uint8 constant droughtMaxPayout = 100;  //100% of coverage

    struct cropType {
        string name;
        uint premiumPerAcre;    //in wei
        uint duration;          //in months
        uint coveragePerAcre;   //in wei
    }

    cropType[2] public cropTypes; //crops defined in constructor

    enum policyState {Pending, Active, PaidOut, TimedOut}

    struct policy {
        uint policyId;
        address payable user;
        uint premium;
        uint area;
        uint startTime;
        uint endTime;         //crop's season dependent
        string location;
        uint coverageAmount;  //depends on crop type
        bool forFlood;
        uint8 cropId;
        policyState state;
    }

    policy[] public policies;

    mapping(address => uint[]) public userPolicies;  //user address to array of policy IDs

    function newPolicy (uint _area, string memory _location, bool _forFlood, uint8 _cropId) external payable{
        require(msg.value == (cropTypes[_cropId].premiumPerAcre * _area),"Incorrect Premium Amount");

        uint pId = policies.length;
        userPolicies[msg.sender].push(pId);
        policies.push(
            policy({
                policyId: pId,
                user: payable(msg.sender),
                premium: cropTypes[_cropId].premiumPerAcre * _area,
                area: _area,
                startTime: block.timestamp,
                endTime: block.timestamp + cropTypes[_cropId].duration * 30*24*60*60,  //converting months to second
                location: _location,
                coverageAmount: cropTypes[_cropId].coveragePerAcre * _area,
                forFlood: _forFlood,
                cropId: _cropId,
                state: policyState.Active
            })
        );     
    }

    function newCrop(uint8 _cropId,string memory _name, uint _premiumPerAcre, uint _duration, uint _coveragePerAcre) internal {
        cropType memory c = cropType(_name, _premiumPerAcre, _duration, _coveragePerAcre);
        cropTypes[_cropId] = c;
    }

    Oracle public oracle;

    constructor(address _oracle) {
        oracle = Oracle(_oracle);

        newCrop(0, "rabi", 0.001 ether, 6, 0.007 ether);
        newCrop(1, "kharif", 0.002 ether, 4, 0.010 ether);
    }

    function claim(uint _policyId) public {
        require(msg.sender == policies[_policyId].user, "User Not Authorized");
        require(policies[_policyId].state == policyState.Active, "Policy Not Active");

        if(block.timestamp > policies[_policyId].endTime)
        {
            policies[_policyId].state = policyState.TimedOut;
            revert("Policy's period has Ended.");
        }
        
        queryOracle(_policyId, policies[_policyId].location);
    }

    function queryOracle(uint claimPolicyId, string memory location) internal {
        uint _result = oracle.getPrecipitation(location);

        uint payoutAmount;

        if(policies[claimPolicyId].forFlood)
        {
            if(_result < floodBaseMin)
                revert("There is No Flood");

            if(_result > floodBaseMax)
            {
                payoutAmount = uint(policies[claimPolicyId].coverageAmount * floodMaxPayout/100);
                policies[claimPolicyId].user.transfer(payoutAmount);
                policies[claimPolicyId].state = policyState.PaidOut;
            }
            else
            {
                payoutAmount = uint(policies[claimPolicyId].coverageAmount * floodBasePayout/100);
                policies[claimPolicyId].user.transfer(payoutAmount);
                policies[claimPolicyId].state = policyState.PaidOut;
            }
        }
        else
        {
            if(_result > droughtBaseMax)
                revert("There is No Drought");

            if(_result < droughtBaseMin)
            {
                payoutAmount = uint(policies[claimPolicyId].coverageAmount * droughtMaxPayout/100);
                policies[claimPolicyId].user.transfer(payoutAmount);
                policies[claimPolicyId].state = policyState.PaidOut;
            }
            else
            {
                payoutAmount = uint(policies[claimPolicyId].coverageAmount * droughtBasePayout/100);
                policies[claimPolicyId].user.transfer(payoutAmount);
                policies[claimPolicyId].state = policyState.PaidOut;
            }
        }
    }

    receive() external payable{}
}
